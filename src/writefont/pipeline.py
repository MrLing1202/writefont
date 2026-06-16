"""
WriteFont 主流程管道

串联预处理→OCR→风格提取→生成→导出的完整流程。
"""

import json
import logging
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import yaml

logger = logging.getLogger(__name__)

# 默认配置
DEFAULT_CONFIG: dict[str, Any] = {
    "preprocessing": {
        "target_size": 128,
        "binarization_threshold": 128,
        "denoise_strength": 3,
        "char_margin": 8,
    },
    "ocr": {
        "engine": "paddleocr",
        "confidence_threshold": 0.7,
        "language": "ch",
    },
    "style": {
        "feature_dim": 200,
        "model_path": "models/style_vae.pth",
        "device": "auto",
    },
    "generator": {
        "model_type": "diffusion",
        "num_inference_steps": 50,
        "guidance_scale": 7.5,
        "batch_size": 32,
    },
    "output": {
        "formats": ["ttf", "otf"],
        "resolution": 256,
        "font_name": "MyHandwriting",
    },
}


@dataclass
class PipelineResult:
    """流程执行结果"""

    success: bool = True
    font_path: Optional[str] = None
    char_count: int = 0
    formats: list[str] = field(default_factory=list)
    output_dir: Optional[str] = None
    output_path: Optional[str] = None
    total: int = 0
    avg_confidence: float = 0.0
    feature_dim: int = 0
    details: dict[str, Any] = field(default_factory=dict)


class WriteFontPipeline:
    """
    WriteFont 主流程管道

    串联所有模块完成从手写图片到字体文件的完整流程：
    图像预处理 → OCR识别 → 风格提取 → 字体生成 → 字体打包

    Args:
        config_path: 配置文件路径，为None时使用默认配置
    """

    def __init__(self, config_path: Optional[str] = None) -> None:
        self.config = self._load_config(config_path)
        self._preprocessor = None
        self._recognizer = None
        self._style_extractor = None
        self._font_generator = None
        self._font_packager = None

    def _load_config(self, config_path: Optional[str]) -> dict[str, Any]:
        """加载配置文件，与默认配置合并"""
        config = DEFAULT_CONFIG.copy()
        if config_path and Path(config_path).exists():
            with open(config_path, "r", encoding="utf-8") as f:
                user_config = yaml.safe_load(f) or {}
            config = self._deep_merge(config, user_config)
            logger.info(f"已加载配置文件: {config_path}")
        return config

    @staticmethod
    def _deep_merge(base: dict, override: dict) -> dict:
        """深度合并两个字典"""
        result = base.copy()
        for key, value in override.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = WriteFontPipeline._deep_merge(result[key], value)
            else:
                result[key] = value
        return result

    @property
    def preprocessor(self):
        """延迟加载预处理器"""
        if self._preprocessor is None:
            from writefont.ocr.preprocessor import ImagePreprocessor
            self._preprocessor = ImagePreprocessor(self.config["preprocessing"])
        return self._preprocessor

    @property
    def recognizer(self):
        """延迟加载OCR识别器"""
        if self._recognizer is None:
            from writefont.ocr.recognizer import CharacterRecognizer
            self._recognizer = CharacterRecognizer(self.config["ocr"])
        return self._recognizer

    @property
    def style_extractor(self):
        """延迟加载风格提取器"""
        if self._style_extractor is None:
            from writefont.style.extractor import StyleExtractor
            self._style_extractor = StyleExtractor(self.config["style"])
        return self._style_extractor

    @property
    def font_generator(self):
        """延迟加载字体生成器"""
        if self._font_generator is None:
            from writefont.generator.diffusion import DiffusionGenerator
            self._font_generator = DiffusionGenerator(self.config["generator"])
        return self._font_generator

    @property
    def font_packager(self):
        """延迟加载字体打包器"""
        if self._font_packager is None:
            from writefont.font.packager import FontPackager
            self._font_packager = FontPackager(self.config["output"])
        return self._font_packager

    def run(
        self,
        input_path: str,
        output_path: str,
        charset: str = "gb2312",
    ) -> dict[str, Any]:
        """
        一键完成从图片到字体的完整流程

        Args:
            input_path: 输入图片路径
            output_path: 输出字体路径
            charset: 目标字符集

        Returns:
            包含执行结果的字典
        """
        input_path = Path(input_path)
        output_path = Path(output_path)

        if not input_path.exists():
            raise FileNotFoundError(f"输入文件不存在: {input_path}")

        # 创建临时工作目录
        with tempfile.TemporaryDirectory(prefix="writefont_") as tmp_dir:
            tmp = Path(tmp_dir)

            # 步骤1: 图像预处理
            logger.info("步骤 1/5: 图像预处理...")
            preprocess_result = self.preprocess(str(input_path), str(tmp / "processed"))

            # 步骤2: OCR识别
            logger.info("步骤 2/5: OCR识别...")
            ocr_result = self.recognize(
                str(tmp / "processed"), str(tmp / "recognized.json")
            )

            # 步骤3: 风格提取
            logger.info("步骤 3/5: 风格提取...")
            style_result = self.extract_style(
                str(tmp / "recognized.json"), str(tmp / "style_vector.pt")
            )

            # 步骤4: 字体生成
            logger.info("步骤 4/5: AI字体生成...")
            generate_result = self.generate_font(
                str(tmp / "style_vector.pt"),
                str(tmp / "glyphs"),
                charset=charset,
            )

            # 步骤5: 字体打包
            logger.info("步骤 5/5: 字体打包...")
            output_path.parent.mkdir(parents=True, exist_ok=True)
            pack_result = self.package_font(
                str(tmp / "glyphs"),
                str(output_path),
            )

        logger.info(f"✅ 字体生成完成: {output_path}")
        return {
            "success": True,
            "font_path": str(output_path),
            "char_count": pack_result.get("char_count", 0),
            "formats": pack_result.get("formats", []),
            "preprocess": preprocess_result,
            "ocr": ocr_result,
            "style": style_result,
            "generate": generate_result,
            "package": pack_result,
        }

    def preprocess(self, input_path: str, output_dir: str) -> dict[str, Any]:
        """
        图像预处理

        Args:
            input_path: 输入图片路径
            output_dir: 输出目录

        Returns:
            预处理结果
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        result = self.preprocessor.process(input_path, output_dir)
        return {
            "output_dir": str(output_dir),
            "char_count": result.get("char_count", 0),
            "images": result.get("images", []),
        }

    def recognize(self, input_dir: str, output_path: str) -> dict[str, Any]:
        """
        OCR识别

        Args:
            input_dir: 输入图片目录
            output_path: 输出JSON路径

        Returns:
            识别结果
        """
        result = self.recognizer.recognize_directory(input_dir)

        # 保存识别结果
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)

        total = len(result.get("characters", []))
        avg_conf = (
            sum(c["confidence"] for c in result.get("characters", [])) / total
            if total > 0
            else 0.0
        )

        return {
            "output_path": str(output_path),
            "total": total,
            "avg_confidence": avg_conf,
        }

    def extract_style(self, input_path: str, output_path: str) -> dict[str, Any]:
        """
        风格提取

        Args:
            input_path: 输入JSON路径
            output_path: 输出风格向量路径

        Returns:
            风格提取结果
        """
        with open(input_path, "r", encoding="utf-8") as f:
            ocr_data = json.load(f)

        result = self.style_extractor.extract(ocr_data, output_path)
        return {
            "output_path": output_path,
            "feature_dim": result.get("feature_dim", 0),
        }

    def generate_font(
        self,
        style_path: str,
        output_dir: str,
        charset: str = "gb2312",
    ) -> dict[str, Any]:
        """
        AI字体生成

        Args:
            style_path: 风格向量路径
            output_dir: 输出目录
            charset: 目标字符集

        Returns:
            生成结果
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        result = self.font_generator.generate(style_path, output_dir, charset)
        return {
            "output_dir": str(output_dir),
            "char_count": result.get("char_count", 0),
        }

    def package_font(self, glyphs_dir: str, output_path: str) -> dict[str, Any]:
        """
        字体打包

        Args:
            glyphs_dir: 字形图片目录
            output_path: 输出字体路径

        Returns:
            打包结果
        """
        result = self.font_packager.package(glyphs_dir, output_path)
        return {
            "font_path": output_path,
            "char_count": result.get("char_count", 0),
            "formats": result.get("formats", []),
        }
