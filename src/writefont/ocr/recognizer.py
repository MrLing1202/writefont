"""OCR 识别模块：支持 PaddleOCR 和 CRNN 两种引擎。"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple, Union

import cv2
import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

ImageLike = Union[str, Path, np.ndarray, Image.Image]


# ------------------------------------------------------------------ #
#  数据结构
# ------------------------------------------------------------------ #

@dataclass
class RecognizedChar:
    """单个识别结果。"""
    char: str                   # 识别出的字符
    confidence: float           # 置信度 [0, 1]
    bbox: Tuple[int, int, int, int]  # (x, y, w, h) 或 (x1, y1, x2, y2)

    def __repr__(self) -> str:
        return f"RecognizedChar(char={self.char!r}, conf={self.confidence:.3f}, bbox={self.bbox})"


@dataclass
class OCRResult:
    """完整 OCR 结果。"""
    text: str
    chars: List[RecognizedChar]
    engine: str

    def __repr__(self) -> str:
        return f"OCRResult(text={self.text!r}, engine={self.engine}, n_chars={len(self.chars)})"


# ------------------------------------------------------------------ #
#  基类
# ------------------------------------------------------------------ #

class OCREngine(ABC):
    """OCR 引擎抽象基类。"""

    def __init__(self, min_confidence: float = 0.5) -> None:
        """
        Args:
            min_confidence: 最低置信度阈值，低于此值的识别结果将被过滤。
        """
        self.min_confidence = min_confidence

    @abstractmethod
    def recognize(self, image: ImageLike) -> OCRResult:
        """识别图像中的文字。

        Args:
            image: 输入图像。

        Returns:
            OCRResult 对象。
        """
        ...

    def _filter_by_confidence(self, chars: List[RecognizedChar]) -> List[RecognizedChar]:
        """按置信度过滤。"""
        return [c for c in chars if c.confidence >= self.min_confidence]

    @staticmethod
    def _load_image(source: ImageLike) -> np.ndarray:
        """将多种来源统一加载为 BGR numpy 数组。"""
        if isinstance(source, np.ndarray):
            img = source
        elif isinstance(source, Image.Image):
            img = np.array(source)
            if img.ndim == 2:
                img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
            else:
                img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
        elif isinstance(source, (str, Path)):
            img = cv2.imread(str(source))
            if img is None:
                raise FileNotFoundError(f"无法读取图像: {source}")
        else:
            raise TypeError(f"不支持的图像类型: {type(source)}")
        return img


# ------------------------------------------------------------------ #
#  PaddleOCR 引擎
# ------------------------------------------------------------------ #

class PaddleOCREngine(OCREngine):
    """基于 PaddleOCR 的识别引擎。

    使用前请安装: pip install paddlepaddle paddleocr
    """

    def __init__(
        self,
        min_confidence: float = 0.5,
        lang: str = "ch",
        use_gpu: bool = False,
        det_model_dir: Optional[str] = None,
        rec_model_dir: Optional[str] = None,
    ) -> None:
        super().__init__(min_confidence)
        self.lang = lang
        self.use_gpu = use_gpu
        self.det_model_dir = det_model_dir
        self.rec_model_dir = rec_model_dir
        self._ocr = None

    def _get_ocr(self):
        """懒加载 PaddleOCR 实例。"""
        if self._ocr is None:
            try:
                from paddleocr import PaddleOCR
            except ImportError:
                raise ImportError(
                    "PaddleOCR 未安装。请运行: pip install paddlepaddle paddleocr"
                )
            kwargs = dict(
                use_angle_cls=True,
                lang=self.lang,
                use_gpu=self.use_gpu,
                show_log=False,
            )
            if self.det_model_dir:
                kwargs["det_model_dir"] = self.det_model_dir
            if self.rec_model_dir:
                kwargs["rec_model_dir"] = self.rec_model_dir
            self._ocr = PaddleOCR(**kwargs)
        return self._ocr

    def recognize(self, image: ImageLike) -> OCRResult:
        """使用 PaddleOCR 识别图像。

        Args:
            image: 输入图像。

        Returns:
            OCRResult。
        """
        ocr = self._get_ocr()
        img = self._load_image(image)
        # PaddleOCR 接受 numpy array (BGR) 或路径
        results = ocr.ocr(img, cls=True)

        chars: List[RecognizedChar] = []
        full_text_parts: List[str] = []

        if results and results[0]:
            for line in results[0]:
                box_points = line[0]  # [[x1,y1],[x2,y2],[x3,y3],[x4,y4]]
                text = line[1][0]
                conf = float(line[1][1])

                # 将四点坐标转为 (x, y, w, h)
                pts = np.array(box_points, dtype=np.int32)
                x_min, y_min = pts.min(axis=0)
                x_max, y_max = pts.max(axis=0)
                bbox = (int(x_min), int(y_min), int(x_max - x_min), int(y_max - y_min))

                # 对于单行文本，可以按字符拆分或整行返回
                # 这里整行作为一个 RecognizedChar
                chars.append(RecognizedChar(
                    char=text,
                    confidence=conf,
                    bbox=bbox,
                ))
                full_text_parts.append(text)

        chars = self._filter_by_confidence(chars)
        full_text = "".join(full_text_parts)

        return OCRResult(text=full_text, chars=chars, engine="PaddleOCR")


# ------------------------------------------------------------------ #
#  CRNN 引擎（备选方案）
# ------------------------------------------------------------------ #

class CRNNEngine(OCREngine):
    """基于 CRNN 的自训练模型识别引擎。

    需要提供 ONNX 模型文件，或使用自定义推理逻辑。
    这里提供基于 OpenCV DNN 的 ONNX 推理示例。

    使用前请确保模型文件存在，或安装 onnxruntime:
        pip install onnxruntime
    """

    def __init__(
        self,
        model_path: Optional[str] = None,
        charset: Optional[str] = None,
        input_size: Tuple[int, int] = (100, 32),
        min_confidence: float = 0.5,
        backend: str = "onnxruntime",  # "onnxruntime" | "opencv"
    ) -> None:
        """
        Args:
            model_path: ONNX 模型文件路径。
            charset: 字符集文件路径（每行一个字符）。若为 None 使用内置默认。
            input_size: 模型输入尺寸 (宽, 高)。
            min_confidence: 最低置信度。
            backend: 推理后端。
        """
        super().__init__(min_confidence)
        self.model_path = model_path
        self.input_size = input_size
        self.backend = backend
        self._model = None
        self._charset = self._load_charset(charset)

    @staticmethod
    def _load_charset(path: Optional[str]) -> List[str]:
        """加载字符集。"""
        default_chars = (
            "abcdefghijklmnopqrstuvwxyz"
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            "0123456789"
            ".,;:!?-()[]{}'\"/\\@#$%^&*+=_~`|<>"
        )
        if path is None:
            return list(default_chars)

        charset_path = Path(path)
        if not charset_path.exists():
            logger.warning("字符集文件不存在: %s，使用默认字符集", path)
            return list(default_chars)

        with open(charset_path, "r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip()]

    def _load_model(self):
        """懒加载模型。"""
        if self._model is not None:
            return

        if self.model_path is None:
            raise ValueError(
                "CRNNEngine 需要指定 model_path。"
                "请提供 ONNX 模型路径或切换到 PaddleOCREngine。"
            )

        model_file = Path(self.model_path)
        if not model_file.exists():
            raise FileNotFoundError(f"模型文件不存在: {self.model_path}")

        if self.backend == "onnxruntime":
            try:
                import onnxruntime as ort
                self._model = ort.InferenceSession(str(model_file))
            except ImportError:
                raise ImportError(
                    "onnxruntime 未安装。请运行: pip install onnxruntime"
                )
        elif self.backend == "opencv":
            self._model = cv2.dnn.readNetFromONNX(str(model_file))
        else:
            raise ValueError(f"不支持的推理后端: {self.backend}")

    def _preprocess_single(self, char_img: np.ndarray) -> np.ndarray:
        """预处理单个字符图像为模型输入格式。"""
        w, h = self.input_size
        gray = char_img if char_img.ndim == 2 else cv2.cvtColor(char_img, cv2.COLOR_BGR2GRAY)
        # 保持宽高比缩放
        ih, iw = gray.shape
        scale = min(w / iw, h / ih)
        nw, nh = int(iw * scale), int(ih * scale)
        resized = cv2.resize(gray, (nw, nh), interpolation=cv2.INTER_AREA)
        # 居中填充
        canvas = np.zeros((h, w), dtype=np.uint8)
        dx, dy = (w - nw) // 2, (h - nh) // 2
        canvas[dy:dy + nh, dx:dx + nw] = resized
        # 归一化
        blob = canvas.astype(np.float32) / 255.0
        blob = (blob - 0.5) / 0.5
        # 添加 batch 和 channel 维度: (1, 1, H, W)
        blob = blob[np.newaxis, np.newaxis, :, :]
        return blob

    def _decode_output(self, output: np.ndarray) -> Tuple[str, float]:
        """CTC 解码。"""
        # output shape: (1, seq_len, num_classes)
        preds = output.squeeze(0)  # (seq_len, num_classes)
        pred_indices = np.argmax(preds, axis=-1)
        pred_probs = np.max(preds, axis=-1)

        chars = []
        confidences = []
        prev_idx = -1

        # charset 中索引 0 通常代表 blank
        for idx, prob in zip(pred_indices, pred_probs):
            if idx != prev_idx and idx != 0:
                if idx - 1 < len(self._charset):
                    chars.append(self._charset[idx - 1])
                    confidences.append(float(prob))
            prev_idx = idx

        text = "".join(chars)
        avg_conf = float(np.mean(confidences)) if confidences else 0.0
        return text, avg_conf

    def recognize(self, image: ImageLike) -> OCRResult:
        """使用 CRNN 模型识别图像。

        Args:
            image: 输入图像（可为单字符或多字符的完整图像）。

        Returns:
            OCRResult。
        """
        self._load_model()
        img = self._load_image(image)

        # 简单处理：将整张图作为一个输入
        blob = self._preprocess_single(img)

        if self.backend == "onnxruntime":
            input_name = self._model.get_inputs()[0].name
            outputs = self._model.run(None, {input_name: blob.astype(np.float32)})
            output = outputs[0]
        else:
            self._model.setInput(blob.astype(np.float32))
            output = self._model.forward()

        text, conf = self._decode_output(output)

        chars: List[RecognizedChar] = []
        h_img, w_img = img.shape[:2]
        if text:
            chars.append(RecognizedChar(
                char=text,
                confidence=conf,
                bbox=(0, 0, w_img, h_img),
            ))

        chars = self._filter_by_confidence(chars)

        return OCRResult(text=text, chars=chars, engine="CRNN")
