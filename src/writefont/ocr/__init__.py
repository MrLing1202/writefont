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

try:
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
except ImportError:
    BBox = None  # type: ignore[assignment,misc]
    CharRegion = None  # type: ignore[assignment,misc]
    ImagePreprocessor = None  # type: ignore[assignment,misc]
    CRNNEngine = None  # type: ignore[assignment,misc]
    OCRResult = None  # type: ignore[assignment,misc]
    OCREngine = None  # type: ignore[assignment,misc]
    PaddleOCREngine = None  # type: ignore[assignment,misc]
    RecognizedChar = None  # type: ignore[assignment,misc]

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
