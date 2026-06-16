"""Generator module: diffusion-based glyph generation."""

try:
    from .diffusion import ConditionalDiffusionModel
    from .renderer import GlyphRenderer
except ImportError:
    ConditionalDiffusionModel = None  # type: ignore[assignment,misc]
    GlyphRenderer = None  # type: ignore[assignment,misc]

__all__ = ["ConditionalDiffusionModel", "GlyphRenderer"]
