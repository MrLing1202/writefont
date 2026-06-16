"""Glyph vectorizer: convert binary bitmaps to vector contour paths.

Implements a marching-squares based contour tracer and provides an option
to use ``potrace`` (via ``pypotrace``) when available.  The output is a
list of ``fontTools.pens.PointPen``-compatible contour data that can be
fed directly into :class:`FontPackager`.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional, Tuple

import cv2
import numpy as np


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class ContourPoint:
    """A single point on a contour path."""
    x: float
    y: float
    on_curve: bool = True  # True = line-to, False = off-curve (cubic/quadratic Bézier control point)


@dataclass
class Contour:
    """Closed contour made of points."""
    points: List[ContourPoint] = field(default_factory=list)

    def is_clockwise(self) -> bool:
        """Shoelace formula to determine winding order."""
        area = 0.0
        pts = self.points
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            area += pts[i].x * pts[j].y
            area -= pts[j].x * pts[i].y
        return area < 0  # In font coords (y-up), negative = clockwise


# ---------------------------------------------------------------------------
# Marching Squares contour tracing
# ---------------------------------------------------------------------------

def _marching_squares(binary: np.ndarray, threshold: int = 128) -> List[List[Tuple[float, float]]]:
    """Run marching-squares on a binary image, returning raw polyline loops."""
    h, w = binary.shape
    # Treat pixels >= threshold as foreground
    field = (binary >= threshold).astype(np.uint8)

    # Build a grid of cell types (0-15)
    # Pad by one so boundary cells are surrounded
    padded = np.pad(field, 1, constant_values=0)
    cells = (
        padded[:-1, :-1] * 1
        + padded[:-1, 1:] * 2
        + padded[1:, 1:] * 4
        + padded[1:, :-1] * 8
    )

    # Edge table: for each cell type, list of edge midpoints (as pairs of vertex indices)
    # Vertices: 0=top, 1=right, 2=bottom, 3=left
    EDGE_TABLE: dict[int, list] = {
        0: [], 15: [],
        1: [(3, 2)], 14: [(3, 2)],
        2: [(2, 1)], 13: [(2, 1)],
        3: [(3, 1)], 12: [(3, 1)],
        4: [(1, 0)], 11: [(1, 0)],
        5: [(3, 0), (1, 2)],  # saddle – ambiguous; choose one diagonal
        6: [(2, 0)], 9: [(2, 0)],
        7: [(3, 0)], 8: [(3, 0)],
        10: [(3, 2), (1, 0)],  # saddle
    }

    def edge_mid(r: int, c: int, edge: int) -> Tuple[float, float]:
        """Return the midpoint of the given edge of cell (r, c)."""
        if edge == 0:  # top
            return (c + 0.5, r)
        elif edge == 1:  # right
            return (c + 1, r + 0.5)
        elif edge == 2:  # bottom
            return (c + 0.5, r + 1)
        else:  # left
            return (c, r + 0.5)

    # Collect segments: each is ((x1,y1),(x2,y2))
    segments: List[Tuple[Tuple[float, float], Tuple[float, float]]] = []
    rows, cols = cells.shape
    for r in range(rows):
        for c in range(cols):
            cell_type = cells[r, c]
            edges = EDGE_TABLE.get(cell_type, [])
            for e_pair in edges:
                p1 = edge_mid(r, c, e_pair[0])
                p2 = edge_mid(r, c, e_pair[1])
                segments.append((p1, p2))

    # Chain segments into loops
    loops: List[List[Tuple[float, float]]] = []
    used = [False] * len(segments)

    def _close_enough(a: Tuple[float, float], b: Tuple[float, float], eps: float = 0.01) -> bool:
        return abs(a[0] - b[0]) < eps and abs(a[1] - b[1]) < eps

    for i, seg in enumerate(segments):
        if used[i]:
            continue
        used[i] = True
        chain = [seg[0], seg[1]]
        changed = True
        while changed:
            changed = False
            for j, s2 in enumerate(segments):
                if used[j]:
                    continue
                if _close_enough(chain[-1], s2[0]):
                    chain.append(s2[1])
                    used[j] = True
                    changed = True
                elif _close_enough(chain[-1], s2[1]):
                    chain.append(s2[0])
                    used[j] = True
                    changed = True
                elif _close_enough(chain[0], s2[1]):
                    chain.insert(0, s2[0])
                    used[j] = True
                    changed = True
                elif _close_enough(chain[0], s2[0]):
                    chain.insert(0, s2[1])
                    used[j] = True
                    changed = True
        if len(chain) >= 4:
            loops.append(chain)

    return loops


def _simplify_contour(
    points: List[Tuple[float, float]],
    epsilon: float = 1.0,
) -> List[Tuple[float, float]]:
    """Douglas-Peucker simplification on a polyline."""
    arr = np.array(points, dtype=np.float32).reshape(-1, 1, 2)
    simplified = cv2.approxPolyDP(arr, epsilon, closed=True)
    return [(float(p[0][0]), float(p[0][1])) for p in simplified]


# ---------------------------------------------------------------------------
# Main vectorizer
# ---------------------------------------------------------------------------

class GlyphVectorizer:
    """Convert binary glyph bitmaps to vector contour paths.

    Parameters
    ----------
    simplify_epsilon : float
        Tolerance for Douglas-Peucker simplification.
    use_potrace : bool
        If True and ``pypotrace`` is installed, use potrace for tracing.
        Otherwise, fall back to built-in marching squares.
    upsample : int
        Factor to upsample the bitmap before tracing for smoother curves.
    """

    def __init__(
        self,
        simplify_epsilon: float = 1.0,
        use_potrace: bool = False,
        upsample: int = 2,
    ) -> None:
        self.simplify_epsilon = simplify_epsilon
        self.use_potrace = use_potrace
        self.upsample = upsample

    def vectorize(self, binary_image: np.ndarray) -> List[Contour]:
        """Convert a binary glyph bitmap into a list of :class:`Contour` objects.

        Parameters
        ----------
        binary_image : ndarray, shape (H, W), dtype uint8
            Binary image with 0 = background, 255 = foreground.

        Returns
        -------
        list[Contour]
            Extracted contours.  Coordinates are in font units (origin at
            bottom-left, y pointing up).
        """
        h, w = binary_image.shape[:2]

        # Optionally upsample for smoother contours
        if self.upsample > 1:
            big = cv2.resize(
                binary_image,
                (w * self.upsample, h * self.upsample),
                interpolation=cv2.INTER_NEAREST,
            )
        else:
            big = binary_image

        if self.use_potrace:
            contours = self._trace_potrace(big)
        else:
            contours = self._trace_marching(big)

        # Flip y-axis: image coords → font coords (origin bottom-left)
        img_h = big.shape[0]
        for contour in contours:
            for pt in contour.points:
                pt.y = img_h - pt.y

        # Scale coordinates back to original resolution
        if self.upsample > 1:
            for contour in contours:
                for pt in contour.points:
                    pt.x /= self.upsample
                    pt.y /= self.upsample

        return contours

    # ---- internal strategies ----

    def _trace_marching(self, binary: np.ndarray) -> List[Contour]:
        """Use marching squares to extract contours."""
        loops = _marching_squares(binary)
        contours: List[Contour] = []
        for loop in loops:
            simplified = _simplify_contour(loop, self.simplify_epsilon)
            if len(simplified) < 3:
                continue
            c = Contour(points=[ContourPoint(x=p[0], y=p[1], on_curve=True) for p in simplified])
            contours.append(c)
        return contours

    def _trace_potrace(self, binary: np.ndarray) -> List[Contour]:
        """Use pypotrace for contour extraction (falls back to marching squares)."""
        try:
            import potrace
        except ImportError:
            return self._trace_marching(binary)

        bmp = potrace.Bitmap(binary < 128)
        path = bmp.trace()
        contours: List[Contour] = []
        for curve in path:
            pts: List[ContourPoint] = []
            for segment in curve:
                if segment.is_corner:
                    pts.append(ContourPoint(x=segment.c[0], y=segment.c[1], on_curve=True))
                    pts.append(ContourPoint(x=segment.end_point.x, y=segment.end_point.y, on_curve=True))
                else:
                    pts.append(ContourPoint(x=segment.c1[0], y=segment.c1[1], on_curve=False))
                    pts.append(ContourPoint(x=segment.c2[0], y=segment.c2[1], on_curve=False))
                    pts.append(ContourPoint(x=segment.end_point.x, y=segment.end_point.y, on_curve=True))
            if len(pts) >= 3:
                contours.append(Contour(points=pts))
        return contours

    def vectorize_to_svg(
        self,
        binary_image: np.ndarray,
        width: int = 1000,
        height: int = 1000,
    ) -> str:
        """Return an SVG string of the traced glyph (useful for debugging)."""
        contours = self.vectorize(binary_image)
        h_orig = binary_image.shape[0]
        scale_x = width / binary_image.shape[1]
        scale_y = height / h_orig

        paths_data = []
        for c in contours:
            if not c.points:
                continue
            d = f"M {c.points[0].x * scale_x:.1f} {c.points[0].y * scale_y:.1f}"
            for pt in c.points[1:]:
                if pt.on_curve:
                    d += f" L {pt.x * scale_x:.1f} {pt.y * scale_y:.1f}"
            d += " Z"
            paths_data.append(d)

        svg = (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">\n'
            + "\n".join(f'  <path d="{d}" fill="black"/>' for d in paths_data)
            + "\n</svg>"
        )
        return svg
