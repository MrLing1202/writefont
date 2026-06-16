"""Font packager: assemble TTF / OTF / WOFF font files using FontTools.

Takes vectorised contours from :class:`GlyphVectorizer` and metadata, then
builds a standards-compliant OpenType/TrueType font file with proper glyph
metrics, kerning, and naming tables.
"""

from __future__ import annotations

import datetime
import io
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple, Union

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2Pen import T2Pen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

from .vectorizer import Contour, ContourPoint


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _contours_to_tt_pen(
    contours: List[Contour],
    units_per_em: int = 1000,
    img_width: int = 128,
    img_height: int = 128,
) -> "TTGlyphPen":
    """Draw contours onto a :class:`TTGlyphPen` (TrueType quadratic outlines).

    Contour coordinates are assumed to come from :class:`GlyphVectorizer` with
    origin at the bottom-left of the image.  They are scaled to font units.
    """
    pen = TTGlyphPen(None)
    scale = units_per_em / max(img_width, img_height)

    for contour in contours:
        if len(contour.points) < 3:
            continue
        pts = contour.points
        pen.moveTo((pts[0].x * scale, pts[0].y * scale))
        i = 1
        while i < len(pts):
            p = pts[i]
            if p.on_curve:
                pen.lineTo((p.x * scale, p.y * scale))
                i += 1
            else:
                # Quadratic Bézier: one off-curve + one on-curve
                if i + 1 < len(pts):
                    p2 = pts[i + 1]
                    pen.qCurveTo(
                        (p.x * scale, p.y * scale),
                        (p2.x * scale, p2.y * scale),
                    )
                    i += 2
                else:
                    # Fallback: treat as line
                    pen.lineTo((p.x * scale, p.y * scale))
                    i += 1
        pen.closePath()
    return pen


# ---------------------------------------------------------------------------
# FontPackager
# ---------------------------------------------------------------------------

class FontPackager:
    """Build and export font files from vectorised glyph data.

    Typical usage::

        packager = FontPackager(font_name="MyHandwriting")
        packager.add_glyph(ord("A"), contours_a, advance_width=600)
        packager.add_glyph(ord("B"), contours_b, advance_width=600)
        packager.build_kerning({(ord("A"), ord("V")): -30})
        packager.export("output.ttf")

    Parameters
    ----------
    font_name : str
        Internal PostScript name of the font.
    family_name : str
        Family name (visible to users).
    style_name : str
        Style (Regular, Bold, etc.).
    units_per_em : int
        Font coordinate space (default 1000 for TrueType).
    ascent : int
        Typographic ascent in font units.
    descent : int
        Typographic descent (negative value).
    img_size : int
        Expected input image size for coordinate scaling.
    """

    def __init__(
        self,
        font_name: str = "WriteFont",
        family_name: str = "WriteFont",
        style_name: str = "Regular",
        units_per_em: int = 1000,
        ascent: int = 800,
        descent: int = -200,
        img_size: int = 128,
    ) -> None:
        self.font_name = font_name
        self.family_name = family_name
        self.style_name = style_name
        self.units_per_em = units_per_em
        self.ascent = ascent
        self.descent = descent
        self.img_size = img_size

        self._glyphs: Dict[int, object] = {}  # unicode → TTGlyph
        self._metrics: Dict[int, Tuple[int, int]] = {}  # unicode → (advance_width, lsb)
        self._kerning: Dict[Tuple[int, int], int] = {}
        self._notdef_glyph: Optional[object] = None

    # ---- Glyph management ----

    def add_glyph(
        self,
        unicode_val: int,
        contours: List[Contour],
        advance_width: int = 600,
        left_side_bearing: Optional[int] = None,
    ) -> None:
        """Add a glyph to the font.

        Parameters
        ----------
        unicode_val : int
            Unicode code-point (e.g. ``ord("A")``).
        contours : list[Contour]
            Vectorised glyph contours from :class:`GlyphVectorizer`.
        advance_width : int
            Horizontal advance width in font units.
        left_side_bearing : int, optional
            Left side bearing.  If *None*, calculated automatically from the
            glyph bounding box.
        """
        pen = _contours_to_tt_pen(contours, self.units_per_em, self.img_size, self.img_size)
        glyph = pen.glyph()
        self._glyphs[unicode_val] = glyph

        # Compute LSB if not provided
        if left_side_bearing is None:
            bounds = glyph.getBounds(self._get_fake_glyph_set())
            left_side_bearing = int(bounds[0]) if bounds else 0

        self._metrics[unicode_val] = (advance_width, left_side_bearing)

    def set_metrics(
        self,
        unicode_val: int,
        advance_width: int,
        left_side_bearing: Optional[int] = None,
    ) -> None:
        """Update metrics for an existing glyph.

        Parameters
        ----------
        unicode_val : int
            Unicode code-point.
        advance_width : int
            New advance width.
        left_side_bearing : int, optional
            New left side bearing.
        """
        if unicode_val not in self._metrics:
            raise KeyError(f"Glyph U+{unicode_val:04X} not found")
        existing = self._metrics[unicode_val]
        self._metrics[unicode_val] = (
            advance_width,
            left_side_bearing if left_side_bearing is not None else existing[1],
        )

    def build_kerning(self, kern_pairs: Dict[Tuple[int, int], int]) -> None:
        """Set kerning pairs.

        Parameters
        ----------
        kern_pairs : dict[(int, int), int]
            Mapping of ``(left_unicode, right_unicode) → adjustment`` in
            font units (negative = bring closer).
        """
        self._kerning = dict(kern_pairs)

    # ---- Export ----

    def export(
        self,
        path: Union[str, Path],
        format: str = "ttf",
    ) -> Path:
        """Build and write the font file.

        Parameters
        ----------
        path : str or Path
            Output file path.  Extension will be adjusted to match *format*.
        format : str
            ``"ttf"`` for TrueType, ``"otf"`` for CFF/OTF, ``"woff"`` or
            ``"woff2"`` for web formats.

        Returns
        -------
        Path
            Path to the written file.
        """
        path = Path(path)
        format = format.lower().lstrip(".")

        is_ttf = format in ("ttf", "woff", "woff2")
        builder = FontBuilder(self.units_per_em, isTTF=is_ttf)
        builder.setupGlyphOrder([".notdef"] + [chr(u) for u in sorted(self._glyphs)])

        # Character map
        cmap = {u: chr(u) for u in self._glyphs}
        builder.setupCharacterMap(cmap)

        # Glyph set
        glyph_set = {".notdef": self._get_notdef_glyph()}
        char_adv_metrics = {".notdef": (500, 0)}
        for u, glyph in self._glyphs.items():
            name = chr(u)
            glyph_set[name] = glyph
            char_adv_metrics[name] = self._metrics[u]

        if is_ttf:
            builder.setupGlyf(glyph_set)
        else:
            builder.setupCFF(charNames=list(glyph_set.keys()), charStringsDict=glyph_set, widths=None)

        # Metrics
        hmtx = {k: v for k, v in char_adv_metrics.items()}
        builder.setupHorizontalMetrics(hmtx)
        builder.setupHorizontalHeader(ascent=self.ascent, descent=self.descent)

        # Naming
        now = datetime.datetime.now()
        builder.setupNameTable(
            {
                "familyName": self.family_name,
                "styleName": self.style_name,
            }
        )

        # OS/2
        builder.setupOs2(
            sTypoAscender=self.ascent,
            sTypoDescender=self.descent,
            sTypoLineGap=0,
            usWinAscent=self.ascent,
            usWinDescent=abs(self.descent),
            sxHeight=500,
            sCapHeight=700,
        )

        builder.setupPost()

        # Build TTFont object
        font = builder.font

        # Add kern table if we have pairs
        if self._kerning:
            self._add_kern_table(font)

        # Determine output path
        ext_map = {"ttf": ".ttf", "otf": ".otf", "woff": ".woff", "woff2": ".woff2"}
        if not any(path.suffix == v for v in ext_map.values()):
            path = path.with_suffix(ext_map.get(format, ".ttf"))

        if format in ("woff", "woff2"):
            # Save as TTF first, then convert
            buf = io.BytesIO()
            font.save(buf)
            buf.seek(0)
            from fontTools.ttLib import TTFont as _TT

            tmp = _TT(buf)
            if format == "woff2":
                from fontTools.ttLib.woff2 import compress

                compress(buf, str(path))
            else:
                tmp.flavor = "woff"
                tmp.save(str(path))
        else:
            font.save(str(path))

        return path

    # ---- Private helpers ----

    def _get_notdef_glyph(self):
        """Return a simple `.notdef` glyph (empty rectangle)."""
        if self._notdef_glyph is not None:
            return self._notdef_glyph
        pen = TTGlyphPen(None)
        pen.moveTo((50, 0))
        pen.lineTo((450, 0))
        pen.lineTo((450, 700))
        pen.lineTo((50, 700))
        pen.closePath()
        pen.moveTo((100, 50))
        pen.lineTo((100, 650))
        pen.lineTo((400, 650))
        pen.lineTo((400, 50))
        pen.closePath()
        self._notdef_glyph = pen.glyph()
        return self._notdef_glyph

    def _get_fake_glyph_set(self) -> dict:
        """Minimal glyph set for bounding-box queries."""
        return {".notdef": self._get_notdef_glyph()}

    def _add_kern_table(self, font: TTFont) -> None:
        """Attach a ``kern`` table with the stored kerning pairs."""
        from fontTools.ttLib.tables._k_e_r_n import table__k_e_r_n as KernTable
        from fontTools.ttLib.tables._k_e_r_n import KernTable_format_0 as KernSub

        kern = KernTable()
        kern.version = 0
        sub = KernSub()
        sub.version = 0
        sub.coverage = 1  # horizontal
        sub.tupleIndex = 0
        sub.kernPairs = []
        for (left_u, right_u), value in self._kerning.items():
            left_name = chr(left_u)
            right_name = chr(right_u)
            sub.kernPairs.append((left_name, right_name, value))
        sub.nPairs = len(sub.kernPairs)
        sub.searchRange = 1
        sub.entrySelector = 0
        sub.rangeShift = 0
        kern.kernTables = [sub]
        font["kern"] = kern
