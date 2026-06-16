"""WriteFont 主流程管道

串联预处理→OCR→风格提取→字形生成→字体打包的完整流程，
支持 LOCAL / API / HYBRID 三种运行模式。

用法::

    from writefont.pipeline import WriteFontPipeline, EngineMode

    pipe = WriteFontPipeline(mode=EngineMode.HYBRID)
    result = pipe.run("handwriting.jpg", "output.ttf")
"""

from __future__ import annotations

import json
import logging
import math
import random
import tempfile
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple, Union

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
#  EngineMode
# ---------------------------------------------------------------------------


class EngineMode(str, Enum):
    """运行模式枚举。"""

    LOCAL = "local"
    API = "api"
    HYBRID = "hybrid"


# ---------------------------------------------------------------------------
#  默认配置
# ---------------------------------------------------------------------------

DEFAULT_CONFIG: Dict[str, Any] = {
    "mode": "hybrid",
    "preprocessing": {
        "target_size": [128, 128],
        "blur_kernel": [3, 3],
        "median_kernel": 3,
        "block_size": 25,
        "c_offset": 10,
        "min_char_area": 50,
        "max_char_area_ratio": 0.5,
    },
    "ocr": {
        "engine": "paddleocr",
        "min_confidence": 0.7,
        "language": "ch",
    },
    "style": {
        "model_path": None,
        "latent_dim": 200,
        "device": "auto",
        "image_size": 128,
    },
    "generator": {
        "model_path": None,
        "img_size": 64,
        "img_channels": 1,
        "style_dim": 200,
        "char_vocab_size": 8000,
        "char_emb_dim": 256,
        "num_diffusion_steps": 1000,
        "num_inference_steps": 50,
    },
    "renderer": {
        "target_size": [128, 128],
        "threshold_method": "otsu",
    },
    "vectorizer": {
        "simplify_epsilon": 1.0,
        "upsample": 2,
    },
    "packager": {
        "font_name": "MyHandwriting",
        "family_name": "My Handwriting",
        "style_name": "Regular",
        "units_per_em": 1000,
        "ascent": 800,
        "descent": -200,
        "img_size": 128,
    },
    "output": {
        "formats": ["ttf"],
        "font_name": "MyHandwriting",
    },
    "api": {
        "provider": "openai",
        "model": "gpt-4o",
        "api_key_env": "OPENAI_API_KEY",
        "base_url": None,
        "vision_model": None,
        "chat_model": None,
    },
}

# ---------------------------------------------------------------------------
#  PipelineResult
# ---------------------------------------------------------------------------


@dataclass
class PipelineResult:
    """流程执行结果。"""

    success: bool = True
    font_path: Optional[str] = None
    char_count: int = 0
    formats: List[str] = field(default_factory=list)
    output_dir: Optional[str] = None
    output_path: Optional[str] = None
    total: int = 0
    avg_confidence: float = 0.0
    feature_dim: int = 0
    style_vector: Optional[List[float]] = None
    mode_used: str = ""
    elapsed_seconds: float = 0.0
    demo_mode: bool = False
    details: Dict[str, Any] = field(default_factory=dict)


# ---------------------------------------------------------------------------
#  StyleTransformer (API 模式下的字形生成替代方案)
# ---------------------------------------------------------------------------


class StyleTransformer:
    """基于风格参数对基础字形做仿射变换模拟手写风格。

    当 API 模式下无法直接调用扩散模型生成字形时，使用此变换器
    对基础字体渲染结果进行风格化处理。
    """

    def __init__(self, style_params: Dict[str, float]) -> None:
        """初始化。

        Args:
            style_params: 风格参数字典，包含 stroke_width, slant_angle,
                         connection_level, curvature 等。
        """
        self.params = style_params

    def transform(self, image: Any) -> Any:
        """对图像应用风格变换。

        Args:
            image: PIL.Image 对象。

        Returns:
            变换后的 PIL.Image 对象。
        """
        try:
            import cv2
            import numpy as np
            from PIL import Image
        except ImportError:
            return image

        img_array = np.array(image)

        # 倾斜变换
        slant = self.params.get("slant_angle", 0.0)
        if abs(slant) > 0.1:
            h, w = img_array.shape[:2]
            M = np.float32([[1, slant / 10.0, 0], [0, 1, 0]])
            img_array = cv2.warpAffine(
                img_array, M, (w, h), borderValue=0
            )

        # 笔画粗细调整（形态学操作）
        stroke_width = self.params.get("stroke_width", 1.0)
        if abs(stroke_width - 1.0) > 0.05:
            k = max(1, int(abs(stroke_width - 1.0) * 3))
            kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
            if stroke_width > 1.0:
                img_array = cv2.dilate(img_array, kernel, iterations=1)
            else:
                img_array = cv2.erode(img_array, kernel, iterations=1)

        # 轻微随机扭曲（模拟手写抖动）
        curvature = self.params.get("curvature", 0.0)
        if curvature > 0.01:
            h, w = img_array.shape[:2]
            noise_x = np.random.randn(h, w).astype(np.float32) * curvature * 3
            noise_y = np.random.randn(h, w).astype(np.float32) * curvature * 3
            map_x = np.float32(np.arange(w)[None, :].repeat(h, 0) + noise_x)
            map_y = np.float32(np.arange(h)[:, None].repeat(w, 1) + noise_y)
            img_array = cv2.remap(
                img_array, map_x, map_y, cv2.INTER_LINEAR, borderValue=0
            )

        return Image.fromarray(img_array)


# ---------------------------------------------------------------------------
#  DemoProvider
# ---------------------------------------------------------------------------


class DemoProvider:
    """无预训练模型且无 API 配置时的模拟结果提供者。

    让用户在没有任何后端可用的情况下也能看到完整流程。
    """

    def __init__(self, charset: str = "gb2312") -> None:
        self.charset = charset

    def demo_ocr(self, image_path: str) -> List[Dict[str, Any]]:
        """返回模拟 OCR 结果。"""
        demo_chars = list("永和九年岁在癸丑暮春之初会于会稽山阴之兰亭")
        results = []
        for i, ch in enumerate(demo_chars):
            results.append({
                "char": ch,
                "confidence": round(random.uniform(0.85, 0.99), 3),
                "bbox": [10 + i * 60, 10, 50, 50],
            })
        logger.info(f"[Demo] 模拟 OCR 识别了 {len(results)} 个字符")
        return results

    def demo_style_vector(self) -> List[float]:
        """返回模拟 200 维风格向量。"""
        vec = [random.gauss(0, 0.1) for _ in range(200)]
        logger.info("[Demo] 生成模拟 200 维风格向量")
        return vec

    def demo_generate_glyphs(
        self, chars: List[str], output_dir: Path
    ) -> List[str]:
        """为每个字符生成简单的模拟字形图像。"""
        try:
            from PIL import Image, ImageDraw, ImageFont
        except ImportError:
            logger.warning("[Demo] PIL 不可用，跳过字形生成")
            return []

        output_dir.mkdir(parents=True, exist_ok=True)
        paths: List[str] = []

        for ch in chars:
            img = Image.new("L", (128, 128), color=0)
            draw = ImageDraw.Draw(img)

            # 尝试用系统字体渲染
            font = None
            font_size = 90
            for font_path in [
                "/System/Library/Fonts/STHeiti Medium.ttc",
                "/System/Library/Fonts/PingFang.ttc",
                "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
                "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
            ]:
                try:
                    font = ImageFont.truetype(font_path, font_size)
                    break
                except (OSError, IOError):
                    continue

            if font is None:
                try:
                    font = ImageFont.truetype("arial.ttf", font_size)
                except (OSError, IOError):
                    font = ImageFont.load_default()

            # 居中绘制白字
            bbox = draw.textbbox((0, 0), ch, font=font)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            x = (128 - tw) // 2 - bbox[0]
            y = (128 - th) // 2 - bbox[1]
            draw.text((x, y), ch, fill=255, font=font)

            # 添加手写感抖动（如果 numpy 可用）
            try:
                import numpy as np

                arr = np.array(img)
                noise = np.random.randint(0, 20, arr.shape, dtype=np.uint8)
                arr = np.clip(arr.astype(np.int16) + noise - 10, 0, 255).astype(
                    np.uint8
                )
                img = Image.fromarray(arr)
            except ImportError:
                pass  # numpy 不可用时跳过抖动

            char_path = output_dir / f"{ord(ch):05d}.png"
            img.save(str(char_path))
            paths.append(str(char_path))

        logger.info(f"[Demo] 生成了 {len(paths)} 个模拟字形")
        return paths


# ---------------------------------------------------------------------------
#  WriteFontPipeline
# ---------------------------------------------------------------------------


class WriteFontPipeline:
    """WriteFont 主流程管道。

    串联所有模块完成从手写图片到字体文件的完整流程：
    图像预处理 → OCR识别 → 风格提取 → 字体生成 → 字体打包

    支持三种运行模式：
    - LOCAL：完全本地推理，需要预训练模型和相关依赖
    - API：调用云端大模型 API 完成 OCR 和风格分析
    - HYBRID：优先本地，失败时回退到 API

    Args:
        config_path: 配置文件路径，为 None 时使用默认配置。
        mode: 运行模式，默认 HYBRID。
    """

    def __init__(
        self,
        config_path: Optional[str] = None,
        mode: EngineMode = EngineMode.HYBRID,
    ) -> None:
        self.config = self._load_config(config_path)
        self.mode = mode

        # 延迟加载的子模块缓存
        self._preprocessor: Any = None
        self._ocr_engine: Any = None
        self._style_extractor: Any = None
        self._diffusion_model: Any = None
        self._glyph_renderer: Any = None
        self._vectorizer: Any = None
        self._packager: Any = None
        self._demo_provider: Optional[DemoProvider] = None

    # ------------------------------------------------------------------
    #  配置加载
    # ------------------------------------------------------------------

    def _load_config(self, config_path: Optional[str]) -> Dict[str, Any]:
        """加载配置文件，与默认配置深度合并。

        Args:
            config_path: 配置文件路径。

        Returns:
            合并后的配置字典。
        """
        config = _deep_copy_dict(DEFAULT_CONFIG)

        # 尝试加载默认配置文件
        default_yaml = Path(__file__).parent.parent.parent / "configs" / "default.yaml"
        if default_yaml.exists():
            config = self._merge_yaml(config, default_yaml)

        # 加载用户指定的配置
        if config_path and Path(config_path).exists():
            config = self._merge_yaml(config, Path(config_path))

        return config

    @staticmethod
    def _merge_yaml(base: Dict[str, Any], yaml_path: Path) -> Dict[str, Any]:
        """加载 YAML 文件并与基础配置合并。"""
        try:
            import yaml

            with open(yaml_path, "r", encoding="utf-8") as f:
                user_config = yaml.safe_load(f) or {}
            merged = _deep_merge(base, user_config)
            logger.info(f"已加载配置文件: {yaml_path}")
            return merged
        except ImportError:
            logger.warning("yaml 模块不可用，跳过配置文件加载")
            return base
        except Exception as e:
            logger.warning(f"加载配置文件失败 ({yaml_path}): {e}")
            return base

    # ------------------------------------------------------------------
    #  延迟加载子模块 (lazy properties)
    # ------------------------------------------------------------------

    @property
    def preprocessor(self) -> Any:
        """延迟加载图像预处理器。"""
        if self._preprocessor is None:
            try:
                from writefont.ocr.preprocessor import ImagePreprocessor

                cfg = self.config.get("preprocessing", {})
                ts = cfg.get("target_size", [128, 128])
                if isinstance(ts, list):
                    ts = tuple(ts)
                self._preprocessor = ImagePreprocessor(
                    target_size=ts,
                    blur_kernel=tuple(cfg.get("blur_kernel", [3, 3])),
                    median_kernel=cfg.get("median_kernel", 3),
                    block_size=cfg.get("block_size", 25),
                    c_offset=cfg.get("c_offset", 10),
                    min_char_area=cfg.get("min_char_area", 50),
                    max_char_area_ratio=cfg.get("max_char_area_ratio", 0.5),
                )
            except ImportError:
                logger.warning("ImagePreprocessor 不可用")
        return self._preprocessor

    @property
    def ocr_engine(self) -> Any:
        """延迟加载 OCR 引擎。"""
        if self._ocr_engine is None:
            ocr_cfg = self.config.get("ocr", {})
            engine_name = ocr_cfg.get("engine", "paddleocr")
            min_conf = ocr_cfg.get("min_confidence", 0.7)

            try:
                if engine_name == "paddleocr":
                    from writefont.ocr.recognizer import PaddleOCREngine

                    self._ocr_engine = PaddleOCREngine(
                        min_confidence=min_conf,
                        lang=ocr_cfg.get("language", "ch"),
                    )
                else:
                    from writefont.ocr.recognizer import CRNNEngine

                    self._ocr_engine = CRNNEngine(min_confidence=min_conf)
            except ImportError as e:
                logger.warning(f"OCR 引擎加载失败: {e}")
        return self._ocr_engine

    @property
    def style_extractor(self) -> Any:
        """延迟加载风格提取器。"""
        if self._style_extractor is None:
            try:
                from writefont.style.extractor import StyleExtractor

                cfg = self.config.get("style", {})
                device = cfg.get("device", "auto")
                if device == "auto":
                    device = None  # 让 StyleExtractor 自动选择

                self._style_extractor = StyleExtractor(
                    model_path=cfg.get("model_path"),
                    latent_dim=cfg.get("latent_dim", 200),
                    device=device,
                    image_size=cfg.get("image_size", 128),
                )
            except ImportError as e:
                logger.warning(f"StyleExtractor 加载失败: {e}")
        return self._style_extractor

    @property
    def diffusion_model(self) -> Any:
        """延迟加载扩散生成模型。"""
        if self._diffusion_model is None:
            try:
                from writefont.generator.diffusion import ConditionalDiffusionModel

                cfg = self.config.get("generator", {})
                model = ConditionalDiffusionModel(
                    img_size=cfg.get("img_size", 64),
                    img_channels=cfg.get("img_channels", 1),
                    style_dim=cfg.get("style_dim", 200),
                    char_vocab_size=cfg.get("char_vocab_size", 8000),
                    char_emb_dim=cfg.get("char_emb_dim", 256),
                    num_diffusion_steps=cfg.get("num_diffusion_steps", 1000),
                )

                # 尝试加载预训练权重
                model_path = cfg.get("model_path")
                if model_path and Path(model_path).exists():
                    import torch

                    checkpoint = torch.load(model_path, map_location="cpu")
                    if isinstance(checkpoint, dict) and "model_state_dict" in checkpoint:
                        model.load_state_dict(checkpoint["model_state_dict"])
                    else:
                        model.load_state_dict(checkpoint)
                    logger.info(f"已加载扩散模型权重: {model_path}")
                else:
                    logger.warning("扩散模型无预训练权重，将使用随机初始化")

                model.eval()
                self._diffusion_model = model
            except ImportError as e:
                logger.warning(f"ConditionalDiffusionModel 加载失败: {e}")
        return self._diffusion_model

    @property
    def glyph_renderer(self) -> Any:
        """延迟加载字形渲染器。"""
        if self._glyph_renderer is None:
            try:
                from writefont.generator.renderer import GlyphRenderer

                cfg = self.config.get("renderer", {})
                ts = cfg.get("target_size", [128, 128])
                self._glyph_renderer = GlyphRenderer(
                    target_size=tuple(ts),
                    threshold_method=cfg.get("threshold_method", "otsu"),
                )
            except ImportError as e:
                logger.warning(f"GlyphRenderer 加载失败: {e}")
        return self._glyph_renderer

    @property
    def vectorizer(self) -> Any:
        """延迟加载字形矢量化器。"""
        if self._vectorizer is None:
            try:
                from writefont.font.vectorizer import GlyphVectorizer

                cfg = self.config.get("vectorizer", {})
                self._vectorizer = GlyphVectorizer(
                    simplify_epsilon=cfg.get("simplify_epsilon", 1.0),
                    upsample=cfg.get("upsample", 2),
                )
            except ImportError as e:
                logger.warning(f"GlyphVectorizer 加载失败: {e}")
        return self._vectorizer

    @property
    def font_packager(self) -> Any:
        """延迟加载字体打包器。"""
        if self._packager is None:
            try:
                from writefont.font.packager import FontPackager

                cfg = self.config.get("packager", {})
                self._packager = FontPackager(
                    font_name=cfg.get("font_name", "MyHandwriting"),
                    family_name=cfg.get("family_name", "My Handwriting"),
                    style_name=cfg.get("style_name", "Regular"),
                    units_per_em=cfg.get("units_per_em", 1000),
                    ascent=cfg.get("ascent", 800),
                    descent=cfg.get("descent", -200),
                    img_size=cfg.get("img_size", 128),
                )
            except ImportError as e:
                logger.warning(f"FontPackager 加载失败: {e}")
        return self._packager

    @property
    def demo_provider(self) -> DemoProvider:
        """获取 Demo 提供者。"""
        if self._demo_provider is None:
            self._demo_provider = DemoProvider()
        return self._demo_provider

    # ------------------------------------------------------------------
    #  API 辅助
    # ------------------------------------------------------------------

    def _get_api_config(self) -> Dict[str, Any]:
        """获取 API 配置。"""
        return self.config.get("api", {})

    def _api_vision_completion(
        self, image_path: str, prompt: str
    ) -> Optional[str]:
        """调用视觉大模型 API 识别图片内容。

        Args:
            image_path: 图片路径。
            prompt: 提示词。

        Returns:
            模型返回的文本，失败时返回 None。
        """
        api_cfg = self._get_api_config()
        api_key_env = api_cfg.get("api_key_env", "OPENAI_API_KEY")
        api_key = _get_env(api_key_env)

        if not api_key:
            logger.warning(f"API key 环境变量 {api_key_env} 未设置")
            return None

        try:
            import base64

            with open(image_path, "rb") as f:
                img_b64 = base64.b64encode(f.read()).decode()

            base_url = api_cfg.get("base_url", "https://api.openai.com/v1")
            model = api_cfg.get("vision_model") or api_cfg.get("model", "gpt-4o")

            import urllib.request
            import urllib.error

            url = f"{base_url.rstrip('/')}/chat/completions"
            payload = {
                "model": model,
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": prompt},
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/png;base64,{img_b64}",
                                },
                            },
                        ],
                    }
                ],
                "max_tokens": 2000,
            }

            data = json.dumps(payload).encode()
            req = urllib.request.Request(
                url,
                data=data,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {api_key}",
                },
            )

            with urllib.request.urlopen(req, timeout=60) as resp:
                result = json.loads(resp.read().decode())
                return result["choices"][0]["message"]["content"]

        except Exception as e:
            logger.warning(f"视觉 API 调用失败: {e}")
            return None

    def _api_chat_completion(self, prompt: str) -> Optional[str]:
        """调用聊天大模型 API。

        Args:
            prompt: 提示词。

        Returns:
            模型返回的文本，失败时返回 None。
        """
        api_cfg = self._get_api_config()
        api_key_env = api_cfg.get("api_key_env", "OPENAI_API_KEY")
        api_key = _get_env(api_key_env)

        if not api_key:
            logger.warning(f"API key 环境变量 {api_key_env} 未设置")
            return None

        try:
            base_url = api_cfg.get("base_url", "https://api.openai.com/v1")
            model = api_cfg.get("chat_model") or api_cfg.get("model", "gpt-4o")

            import urllib.request

            url = f"{base_url.rstrip('/')}/chat/completions"
            payload = {
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 2000,
            }

            data = json.dumps(payload).encode()
            req = urllib.request.Request(
                url,
                data=data,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {api_key}",
                },
            )

            with urllib.request.urlopen(req, timeout=60) as resp:
                result = json.loads(resp.read().decode())
                return result["choices"][0]["message"]["content"]

        except Exception as e:
            logger.warning(f"聊天 API 调用失败: {e}")
            return None

    # ------------------------------------------------------------------
    #  步骤 1: OCR 识别
    # ------------------------------------------------------------------

    def ocr_step(self, image_path: str) -> List[Dict[str, Any]]:
        """OCR 识别步骤。

        根据运行模式选择不同的 OCR 策略：
        - LOCAL: 使用 PaddleOCREngine / CRNNEngine
        - API: 调用视觉大模型识别手写汉字
        - HYBRID: 先尝试本地，失败则用 API

        Args:
            image_path: 输入图片路径。

        Returns:
            识别结果列表，每个元素包含 char, confidence, bbox。
        """
        if self.mode == EngineMode.LOCAL:
            return self._ocr_local(image_path)
        elif self.mode == EngineMode.API:
            return self._ocr_api(image_path)
        else:  # HYBRID
            result = self._ocr_local(image_path)
            if result:
                return result
            logger.info("本地 OCR 失败，回退到 API 模式")
            return self._ocr_api(image_path)

    def _ocr_local(self, image_path: str) -> List[Dict[str, Any]]:
        """本地 OCR 识别。"""
        if self.ocr_engine is None:
            logger.warning("本地 OCR 引擎不可用")
            return []

        try:
            from writefont.ocr.preprocessor import ImagePreprocessor

            # 预处理
            if self.preprocessor is not None:
                regions = self.preprocessor.preprocess_pipeline(
                    image_path, do_perspective=True, do_denoise=True,
                    do_binarize=True, do_segment=True, do_normalize=True,
                )
            else:
                regions = []

            results: List[Dict[str, Any]] = []

            # 如果有分割区域，逐个识别
            if regions:
                for region in regions:
                    try:
                        ocr_result = self.ocr_engine.recognize(region.image)
                        for ch in ocr_result.chars:
                            results.append({
                                "char": ch.char,
                                "confidence": ch.confidence,
                                "bbox": list(ch.bbox),
                            })
                    except Exception as e:
                        logger.debug(f"字符区域识别失败: {e}")
                        continue
            else:
                # 直接整图识别
                ocr_result = self.ocr_engine.recognize(image_path)
                for ch in ocr_result.chars:
                    results.append({
                        "char": ch.char,
                        "confidence": ch.confidence,
                        "bbox": list(ch.bbox),
                    })

            logger.info(f"[LOCAL] OCR 识别了 {len(results)} 个字符")
            return results

        except Exception as e:
            logger.warning(f"本地 OCR 失败: {e}")
            return []

    def _ocr_api(self, image_path: str) -> List[Dict[str, Any]]:
        """API 模式 OCR 识别。"""
        prompt = (
            "请识别这张手写汉字图片中的所有汉字。"
            "请以 JSON 数组格式返回，每个元素包含："
            '"char"（汉字）、"confidence"（0-1的置信度）、'
            '"bbox"（[x,y,w,h] 边界框，可以估算）。'
            "只返回 JSON 数组，不要其他文字。"
        )

        response = self._api_vision_completion(image_path, prompt)
        if not response:
            logger.warning("API OCR 无返回结果")
            return []

        try:
            # 尝试从回复中提取 JSON
            text = response.strip()
            # 去掉可能的 markdown 代码块标记
            if text.startswith("```"):
                text = text.split("\n", 1)[-1]
            if text.endswith("```"):
                text = text.rsplit("```", 1)[0]
            text = text.strip()

            results = json.loads(text)
            if isinstance(results, list):
                logger.info(f"[API] OCR 识别了 {len(results)} 个字符")
                return results
        except (json.JSONDecodeError, KeyError) as e:
            logger.warning(f"API OCR 结果解析失败: {e}")

        return []

    # ------------------------------------------------------------------
    #  步骤 2: 风格提取
    # ------------------------------------------------------------------

    def style_step(self, characters_data: List[Dict[str, Any]]) -> Dict[str, Any]:
        """风格提取步骤。

        根据运行模式选择不同的风格提取策略：
        - LOCAL: 使用 StyleExtractor + StyleVAE
        - API: 调用大模型分析笔迹特征，输出结构化风格描述后转为向量
        - HYBRID: 先本地后 API

        Args:
            characters_data: OCR 识别结果列表。

        Returns:
            包含 style_vector 和 metadata 的字典。
        """
        if self.mode == EngineMode.LOCAL:
            return self._style_local(characters_data)
        elif self.mode == EngineMode.API:
            return self._style_api(characters_data)
        else:  # HYBRID
            result = self._style_local(characters_data)
            if result.get("style_vector"):
                return result
            logger.info("本地风格提取失败，回退到 API 模式")
            return self._style_api(characters_data)

    def _style_local(self, characters_data: List[Dict[str, Any]]) -> Dict[str, Any]:
        """本地风格提取。"""
        if self.style_extractor is None:
            logger.warning("StyleExtractor 不可用")
            return {"style_vector": None, "feature_dim": 0, "source": "local_failed"}

        try:
            # 收集字符图像路径（如果 OCR 结果中包含路径信息）
            # 由于本地模式下 OCR 可能直接返回了图像区域，
            # 这里尝试从临时文件或预处理结果中获取
            sample_images: List[Any] = []

            # 如果有预处理后的图像缓存
            tmp_dir = Path(tempfile.gettempdir()) / "writefont_chars"
            if tmp_dir.exists():
                for img_path in sorted(tmp_dir.glob("*.png"))[:50]:
                    sample_images.append(str(img_path))

            if not sample_images:
                logger.warning("未找到可用于风格提取的样本图像")
                return {"style_vector": None, "feature_dim": 0, "source": "local_failed"}

            style_vector = self.style_extractor.extract_features(sample_images)
            logger.info(
                f"[LOCAL] 提取了 {len(style_vector)} 维风格向量"
            )

            return {
                "style_vector": style_vector.tolist(),
                "feature_dim": len(style_vector),
                "source": "local",
            }

        except Exception as e:
            logger.warning(f"本地风格提取失败: {e}")
            return {"style_vector": None, "feature_dim": 0, "source": "local_failed"}

    def _style_api(self, characters_data: List[Dict[str, Any]]) -> Dict[str, Any]:
        """API 模式风格分析。"""
        # 构建分析提示词
        char_list = ", ".join(
            [c.get("char", "?") for c in characters_data[:30]]
        )
        prompt = (
            f"以下是从手写图片中识别出的汉字样本：{char_list}\n\n"
            "请分析这些手写汉字的笔迹风格特征，以 JSON 格式返回以下参数（每项 0.0-1.0）：\n"
            "- stroke_width: 笔画粗细（0=极细，1=极粗）\n"
            "- slant_angle: 倾斜角度（0=正直，1=右倾，-1=左倾）\n"
            "- connection_level: 连笔程度（0=完全独立，1=高度连笔）\n"
            "- curvature: 笔画曲率（0=直线，1=高度弯曲）\n"
            "- pressure_variation: 力度变化（0=均匀，1=变化大）\n"
            "- regularity: 工整度（0=潦草，1=工整）\n"
            "- size_ratio: 字形大小比例（0=小，1=大，0.5=标准）\n\n"
            "只返回 JSON 对象，不要其他文字。"
        )

        response = self._api_chat_completion(prompt)

        style_params: Dict[str, float] = {
            "stroke_width": 0.5,
            "slant_angle": 0.0,
            "connection_level": 0.3,
            "curvature": 0.3,
            "pressure_variation": 0.4,
            "regularity": 0.6,
            "size_ratio": 0.5,
        }

        if response:
            try:
                text = response.strip()
                if text.startswith("```"):
                    text = text.split("\n", 1)[-1]
                if text.endswith("```"):
                    text = text.rsplit("```", 1)[0]
                text = text.strip()

                parsed = json.loads(text)
                if isinstance(parsed, dict):
                    style_params.update(
                        {k: float(v) for k, v in parsed.items() if isinstance(v, (int, float))}
                    )
                    logger.info("[API] 成功解析风格参数")
            except (json.JSONDecodeError, ValueError) as e:
                logger.warning(f"API 风格参数解析失败: {e}")

        # 将风格参数转为 200 维向量
        style_vector = self._style_params_to_vector(style_params)

        return {
            "style_vector": style_vector,
            "feature_dim": len(style_vector),
            "style_params": style_params,
            "source": "api",
        }

    @staticmethod
    def _style_params_to_vector(params: Dict[str, float]) -> List[float]:
        """将结构化风格参数转为 200 维向量。

        使用参数值的确定性扩展，使相似参数产生相似向量。

        Args:
            params: 风格参数字典。

        Returns:
            200 维浮点向量。
        """
        import hashlib

        # 用参数值生成确定性种子
        seed_str = "|".join(f"{k}:{v:.4f}" for k, v in sorted(params.items()))
        seed = int(hashlib.md5(seed_str.encode()).hexdigest()[:8], 16)
        rng = random.Random(seed)

        vector: List[float] = []

        # 前 7 维直接放参数值（归一化到 [-1, 1]）
        param_keys = [
            "stroke_width", "slant_angle", "connection_level",
            "curvature", "pressure_variation", "regularity", "size_ratio",
        ]
        for key in param_keys:
            val = params.get(key, 0.5)
            vector.append(val * 2 - 1)  # [0,1] -> [-1,1]

        # 剩余 193 维用参数值驱动的随机数填充
        for _ in range(193):
            vector.append(rng.gauss(0, 0.15))

        return vector

    # ------------------------------------------------------------------
    #  步骤 3: 字形生成
    # ------------------------------------------------------------------

    def generate_step(
        self,
        style_vector: List[float],
        charset_range: List[str],
    ) -> List[str]:
        """字形生成步骤。

        根据运行模式选择不同的生成策略：
        - LOCAL: 使用 ConditionalDiffusionModel 生成字形
        - API: 使用 StyleTransformer 对基础字形做风格变换
        - HYBRID: 先尝试本地，失败则用 API

        Args:
            style_vector: 200 维风格向量。
            charset_range: 目标字符列表。

        Returns:
            生成的字形图像路径列表。
        """
        if self.mode == EngineMode.LOCAL:
            return self._generate_local(style_vector, charset_range)
        elif self.mode == EngineMode.API:
            return self._generate_api(style_vector, charset_range)
        else:  # HYBRID
            result = self._generate_local(style_vector, charset_range)
            if result:
                return result
            logger.info("本地生成失败，回退到 API/程序化生成模式")
            return self._generate_api(style_vector, charset_range)

    def _generate_local(
        self,
        style_vector: List[float],
        charset_range: List[str],
    ) -> List[str]:
        """本地扩散模型生成字形。"""
        if self.diffusion_model is None:
            logger.warning("ConditionalDiffusionModel 不可用")
            return []

        try:
            import torch
            import numpy as np

            style_tensor = torch.tensor(style_vector, dtype=torch.float32)

            # 获取字符索引映射
            try:
                from writefont.utils.charset import build_char_index
                char_index = build_char_index()
            except ImportError:
                char_index = {ch: i for i, ch in enumerate(charset_range)}

            output_dir = Path(tempfile.mkdtemp(prefix="writefont_glyphs_"))
            paths: List[str] = []

            for ch in charset_range:
                char_id = char_index.get(ch, 0)
                try:
                    glyph_tensor = self.diffusion_model.generate_glyph(
                        style=style_tensor,
                        char_id=char_id,
                        num_steps=self.config.get("generator", {}).get(
                            "num_inference_steps", 50
                        ),
                    )

                    # 渲染后处理
                    if self.glyph_renderer is not None:
                        rendered = self.glyph_renderer.render(glyph_tensor)
                        if hasattr(rendered, "numpy"):
                            img_array = rendered.numpy()
                        else:
                            img_array = np.array(rendered)
                    else:
                        # 简单的 tensor → image 转换
                        img_array = glyph_tensor.squeeze().cpu().numpy()
                        img_array = ((img_array + 1) * 127.5).clip(0, 255).astype(np.uint8)

                    # 保存
                    from PIL import Image

                    img = Image.fromarray(img_array)
                    char_path = output_dir / f"{ord(ch):05d}.png"
                    img.save(str(char_path))
                    paths.append(str(char_path))

                except Exception as e:
                    logger.debug(f"字符 '{ch}' 生成失败: {e}")
                    continue

            logger.info(f"[LOCAL] 生成了 {len(paths)} 个字形")
            return paths

        except Exception as e:
            logger.warning(f"本地字形生成失败: {e}")
            return []

    def _generate_api(
        self,
        style_vector: List[float],
        charset_range: List[str],
    ) -> List[str]:
        """API/程序化字形生成。

        由于目前 API 无法直接生成字形图像，使用 StyleTransformer
        对基础字形（程序化生成）做风格变换来模拟手写效果。
        """
        # 从风格向量中提取风格参数
        style_params = self._vector_to_style_params(style_vector)

        output_dir = Path(tempfile.mkdtemp(prefix="writefont_glyphs_"))
        paths: List[str] = []

        for ch in charset_range:
            try:
                img = self._generate_procedural_glyph(ch, style_params)
                char_path = output_dir / f"{ord(ch):05d}.png"
                img.save(str(char_path))
                paths.append(str(char_path))
            except Exception as e:
                logger.debug(f"字符 '{ch}' 程序化生成失败: {e}")
                continue

        logger.info(f"[API] 程序化生成了 {len(paths)} 个字形")
        return paths

    @staticmethod
    def _vector_to_style_params(style_vector: List[float]) -> Dict[str, float]:
        """从 200 维向量还原风格参数。

        Args:
            style_vector: 200 维风格向量。

        Returns:
            风格参数字典。
        """
        param_keys = [
            "stroke_width", "slant_angle", "connection_level",
            "curvature", "pressure_variation", "regularity", "size_ratio",
        ]
        params: Dict[str, float] = {}
        for i, key in enumerate(param_keys):
            if i < len(style_vector):
                params[key] = max(0.0, min(1.0, (style_vector[i] + 1) / 2))
            else:
                params[key] = 0.5
        return params

    def _generate_procedural_glyph(
        self, char: str, style_params: Dict[str, float]
    ) -> Any:
        """使用基础笔画拼接+风格参数变形生成单个字形。

        这是一种程序化生成方法，用 PIL 绘制基础字形后应用风格变换。
        虽然质量不如扩散模型，但能保证实际输出。

        Args:
            char: 目标汉字。
            style_params: 风格参数字典。

        Returns:
            PIL.Image 对象。
        """
        try:
            from PIL import Image, ImageDraw, ImageFont
        except ImportError:
            raise RuntimeError("PIL 不可用，无法生成字形")

        size = 128
        img = Image.new("L", (size, size), color=0)
        draw = ImageDraw.Draw(img)

        # 尝试加载系统字体
        font = None
        font_size = int(90 * style_params.get("size_ratio", 0.5) * 1.5 + 30)
        for font_path in [
            "/System/Library/Fonts/STHeiti Medium.ttc",
            "/System/Library/Fonts/PingFang.ttc",
            "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        ]:
            try:
                font = ImageFont.truetype(font_path, font_size)
                break
            except (OSError, IOError):
                continue

        if font is None:
            try:
                font = ImageFont.truetype("arial.ttf", font_size)
            except (OSError, IOError):
                font = ImageFont.load_default()

        # 居中绘制白字
        bbox = draw.textbbox((0, 0), char, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        x = (size - tw) // 2 - bbox[0]
        y = (size - th) // 2 - bbox[1]
        draw.text((x, y), char, fill=255, font=font)

        # 应用风格变换
        transformer = StyleTransformer(style_params)
        img = transformer.transform(img)

        return img

    # ------------------------------------------------------------------
    #  步骤 4: 矢量化
    # ------------------------------------------------------------------

    def vectorize_step(self, glyph_paths: List[str]) -> Dict[str, Any]:
        """字形矢量化步骤。

        将字形位图转为矢量轮廓。

        Args:
            glyph_paths: 字形图像路径列表。

        Returns:
            矢量化结果，包含 unicode → contours 映射。
        """
        if self.vectorizer is None:
            logger.warning("GlyphVectorizer 不可用")
            return {"glyphs": {}, "count": 0}

        try:
            import numpy as np

            glyphs: Dict[int, Any] = {}
            for path_str in glyph_paths:
                path = Path(path_str)
                # 从文件名提取 unicode 码点
                stem = path.stem
                try:
                    unicode_val = int(stem)
                except ValueError:
                    continue

                # 读取图像
                try:
                    img = np.array(
                        __import__("PIL.Image", fromlist=["Image"])
                        .open(str(path))
                        .convert("L")
                    )
                except Exception:
                    continue

                # 矢量化
                contours = self.vectorizer.vectorize(img)
                if contours:
                    glyphs[unicode_val] = contours

            logger.info(f"矢量化了 {len(glyphs)} 个字形")
            return {"glyphs": glyphs, "count": len(glyphs)}

        except Exception as e:
            logger.warning(f"矢量化失败: {e}")
            return {"glyphs": {}, "count": 0}

    # ------------------------------------------------------------------
    #  步骤 5: 字体打包
    # ------------------------------------------------------------------

    def package_step(
        self,
        vectorized_glyphs: Dict[str, Any],
        output_path: str,
        formats: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """字体打包步骤。

        将矢量字形打包为字体文件。

        Args:
            vectorized_glyphs: 矢量化字形数据。
            output_path: 输出字体文件路径。
            formats: 输出格式列表，默认从配置读取。

        Returns:
            打包结果。
        """
        if self.font_packager is None:
            logger.warning("FontPackager 不可用")
            return {"font_path": None, "char_count": 0, "formats": []}

        formats = formats or self.config.get("output", {}).get("formats", ["ttf"])
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        glyphs = vectorized_glyphs.get("glyphs", {})
        if not glyphs:
            logger.warning("没有可打包的字形")
            return {"font_path": None, "char_count": 0, "formats": []}

        try:
            exported: List[str] = []

            # 为每个格式重新创建 packager（避免状态污染）
            for fmt in formats:
                try:
                    from writefont.font.packager import FontPackager

                    cfg = self.config.get("packager", {})
                    packager = FontPackager(
                        font_name=cfg.get("font_name", "MyHandwriting"),
                        family_name=cfg.get("family_name", "My Handwriting"),
                        style_name=cfg.get("style_name", "Regular"),
                        units_per_em=cfg.get("units_per_em", 1000),
                        ascent=cfg.get("ascent", 800),
                        descent=cfg.get("descent", -200),
                        img_size=cfg.get("img_size", 128),
                    )

                    for unicode_val, contours in glyphs.items():
                        packager.add_glyph(unicode_val, contours, advance_width=600)

                    # 根据格式调整扩展名
                    ext = f".{fmt}"
                    export_path = output_path.with_suffix(ext)
                    packager.export(str(export_path), format=fmt)
                    exported.append(str(export_path))
                    logger.info(f"已导出 {fmt} 字体: {export_path}")

                except Exception as e:
                    logger.warning(f"导出 {fmt} 格式失败: {e}")
                    continue

            return {
                "font_path": exported[0] if exported else None,
                "char_count": len(glyphs),
                "formats": exported,
            }

        except Exception as e:
            logger.warning(f"字体打包失败: {e}")
            return {"font_path": None, "char_count": 0, "formats": []}

    # ------------------------------------------------------------------
    #  主流程
    # ------------------------------------------------------------------

    def run(
        self,
        input_path: str,
        output_path: str,
        charset: str = "gb2312",
        progress_callback: Optional[Callable[[str, float, str], None]] = None,
    ) -> PipelineResult:
        """一键完成从图片到字体的完整流程。

        Args:
            input_path: 输入手写图片路径。
            output_path: 输出字体文件路径。
            charset: 目标字符集，支持 'gb2312'、'gb2312_level1'、'gb2312_level2'。
            progress_callback: 进度回调函数，签名为
                ``(step_name: str, progress_pct: float, detail: str) -> None``。

        Returns:
            PipelineResult 数据类实例。
        """
        start_time = time.time()
        result = PipelineResult(mode_used=self.mode.value)

        input_path_obj = Path(input_path)
        if not input_path_obj.exists():
            result.success = False
            result.details["error"] = f"输入文件不存在: {input_path}"
            return result

        def _progress(step: str, pct: float, detail: str = "") -> None:
            logger.info(f"[{step}] {pct:.0f}% - {detail}")
            if progress_callback:
                try:
                    progress_callback(step, pct, detail)
                except Exception:
                    pass

        # 检查是否应该使用 Demo 模式
        use_demo = self._should_use_demo()
        if use_demo:
            logger.info("无可用后端，启用 Demo 模式")
            result.demo_mode = True

        try:
            # 步骤 1: OCR 识别
            _progress("OCR", 0, "开始识别...")
            if use_demo:
                characters_data = self.demo_provider.demo_ocr(str(input_path_obj))
            else:
                characters_data = self.ocr_step(str(input_path_obj))

            result.total = len(characters_data)
            result.avg_confidence = (
                sum(c.get("confidence", 0) for c in characters_data) / max(len(characters_data), 1)
            )
            result.details["ocr"] = characters_data
            _progress("OCR", 20, f"识别了 {len(characters_data)} 个字符")

            # 步骤 2: 风格提取
            _progress("风格", 20, "提取风格特征...")
            if use_demo:
                style_vec = self.demo_provider.demo_style_vector()
                style_result = {
                    "style_vector": style_vec,
                    "feature_dim": len(style_vec),
                    "source": "demo",
                }
            else:
                style_result = self.style_step(characters_data)

            style_vector = style_result.get("style_vector") or [0.0] * 200
            result.feature_dim = len(style_vector)
            result.style_vector = style_vector[:10]  # 只存前 10 维作为摘要
            result.details["style"] = style_result
            _progress("风格", 40, f"提取了 {result.feature_dim} 维风格向量")

            # 步骤 3: 字形生成
            _progress("生成", 40, "生成字形...")
            chars_to_generate = self._get_charset_chars(charset)

            if use_demo:
                glyph_paths = self.demo_provider.demo_generate_glyphs(
                    chars_to_generate,
                    Path(tempfile.mkdtemp(prefix="writefont_demo_")),
                )
            else:
                glyph_paths = self.generate_step(style_vector, chars_to_generate)

            result.details["generate"] = {"char_count": len(glyph_paths), "paths": glyph_paths}
            _progress("生成", 60, f"生成了 {len(glyph_paths)} 个字形")

            # 步骤 4: 矢量化
            _progress("矢量化", 60, "矢量化字形...")
            vectorized = self.vectorize_step(glyph_paths)
            _progress("矢量化", 80, f"矢量化了 {vectorized.get('count', 0)} 个字形")

            # 步骤 5: 字体打包
            _progress("打包", 80, "打包字体文件...")
            output_path_obj = Path(output_path)
            output_path_obj.parent.mkdir(parents=True, exist_ok=True)

            package_result = self.package_step(
                vectorized, str(output_path_obj)
            )

            result.font_path = package_result.get("font_path")
            result.char_count = package_result.get("char_count", 0)
            result.formats = package_result.get("formats", [])
            result.output_path = result.font_path
            result.output_dir = str(output_path_obj.parent)
            result.details["package"] = package_result
            _progress("打包", 100, "完成!")

            result.success = True

        except Exception as e:
            logger.error(f"流程执行失败: {e}", exc_info=True)
            result.success = False
            result.details["error"] = str(e)

        result.elapsed_seconds = time.time() - start_time
        logger.info(
            f"流程{'成功' if result.success else '失败'}，"
            f"耗时 {result.elapsed_seconds:.1f}s，"
            f"生成 {result.char_count} 个字形"
        )
        return result

    # ------------------------------------------------------------------
    #  辅助方法
    # ------------------------------------------------------------------

    def _should_use_demo(self) -> bool:
        """判断是否应使用 Demo 模式。"""
        # 检查本地模型是否可用
        local_available = False
        try:
            if self.ocr_engine is not None:
                local_available = True
        except Exception:
            pass

        # 检查 API 是否可用
        api_available = False
        api_cfg = self._get_api_config()
        if api_cfg.get("api_key_env"):
            api_key = _get_env(api_cfg["api_key_env"])
            if api_key:
                api_available = True

        if self.mode == EngineMode.LOCAL:
            return not local_available
        elif self.mode == EngineMode.API:
            return not api_available
        else:  # HYBRID
            return not local_available and not api_available

    def _get_charset_chars(self, charset: str) -> List[str]:
        """获取目标字符集的字符列表。

        Args:
            charset: 字符集名称。

        Returns:
            字符列表。
        """
        try:
            from writefont.utils.charset import get_gb2312_chars

            if charset == "gb2312_level1":
                return get_gb2312_chars(level=1)
            elif charset == "gb2312_level2":
                return get_gb2312_chars(level=2)
            elif charset == "gb2312":
                return get_gb2312_chars()
            else:
                # 自定义字符集：直接当作字符列表
                return list(charset)
        except ImportError:
            logger.warning("charset 工具不可用，使用内置常用字")
            return list("的一是不了人我在有他这中大来上个国"
                        "们到说时要就出会也你对生能子那得于着下自之年过发后作里用道行所然家种事成方多经么去法学如都同现当没动面起看定天分还进好小部其些主样理心她本前开但因只从想实日军者意无力它与长把机十民第公此")


# ---------------------------------------------------------------------------
#  模块级工具函数
# ---------------------------------------------------------------------------


def _deep_copy_dict(d: Dict[str, Any]) -> Dict[str, Any]:
    """深拷贝嵌套字典。"""
    result: Dict[str, Any] = {}
    for k, v in d.items():
        if isinstance(v, dict):
            result[k] = _deep_copy_dict(v)
        elif isinstance(v, list):
            result[k] = list(v)
        else:
            result[k] = v
    return result


def _deep_merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    """深度合并两个字典。

    Args:
        base: 基础字典。
        override: 覆盖字典。

    Returns:
        合并后的字典。
    """
    result = base.copy()
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def _get_env(name: str) -> Optional[str]:
    """安全获取环境变量。"""
    import os

    value = os.environ.get(name)
    if value:
        value = value.strip()
    return value or None
