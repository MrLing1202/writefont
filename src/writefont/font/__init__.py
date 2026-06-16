"""Font module: vectorisation and font-file packaging."""

try:
    from .vectorizer import GlyphVectorizer
    from .packager import FontPackager
except ImportError:
    GlyphVectorizer = None  # type: ignore[assignment,misc]
    FontPackager = None  # type: ignore[assignment,misc]

__all__ = ["GlyphVectorizer", "FontPackager"]
