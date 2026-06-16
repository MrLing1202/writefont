"""
writefont.style - 笔迹风格分析模块。

提供风格特征提取、VAE模型和风格向量管理功能。
"""

try:
    from .features import HandwritingFeatures
    from .model import StyleVAE
    from .extractor import StyleExtractor
except ImportError:
    HandwritingFeatures = None  # type: ignore[assignment,misc]
    StyleVAE = None  # type: ignore[assignment,misc]
    StyleExtractor = None  # type: ignore[assignment,misc]

__all__ = ["HandwritingFeatures", "StyleVAE", "StyleExtractor"]
