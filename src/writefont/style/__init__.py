"""
writefont.style - 笔迹风格分析模块。

提供风格特征提取、VAE模型和风格向量管理功能。
"""

from .features import HandwritingFeatures
from .model import StyleVAE
from .extractor import StyleExtractor

__all__ = ["HandwritingFeatures", "StyleVAE", "StyleExtractor"]
