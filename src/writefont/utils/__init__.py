"""Utility modules: charset loading and image helpers."""

from .charset import get_gb2312_chars

try:
    from .image import resize, pad_to_square, to_grayscale
except ImportError:
    resize = None  # type: ignore[assignment]
    pad_to_square = None  # type: ignore[assignment]
    to_grayscale = None  # type: ignore[assignment]

__all__ = ["get_gb2312_chars", "resize", "pad_to_square", "to_grayscale"]
