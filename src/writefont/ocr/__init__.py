"""writefont OCR 模块。

提供图像预处理和文字识别功能。

用法示例::

    from writefont.ocr import OCREngine, PaddleOCREngine, CRNNEngine
    from writefont.ocr.preprocessor import ImagePreprocessor

    # 预处理
    preprocessor = ImagePreprocessor()
    regions = preprocessor.preprocess_pipeline("scan.jpg")

    # 识别
    engine = PaddleOCREngine(min_confidence=0.6)
    result = engine.recognize("scan.jpg")
    print(result.text, result.chars)
"""

from writefont.ocr.preprocessor import (
    BBox,
    CharRegion,
    ImagePreprocessor,
)
from writefont.ocr.recognizer import (
    CRNNEngine,
    OCRResult,
    OCREngine,
    PaddleOCREngine,
    RecognizedChar,
)

__all__ = [
    "BBox",
    "CharRegion",
    "CRNNEngine",
    "ImagePreprocessor",
    "OCREngine",
    "OCRResult",
    "PaddleOCREngine",
    "RecognizedChar",
]
