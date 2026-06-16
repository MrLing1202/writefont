"""WriteFont 基本单元测试。

验证核心模块能正确导入和基本功能可用。
运行: python -m pytest tests/test_pipeline.py -v
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List
from unittest.mock import MagicMock, patch

import pytest


# ---------------------------------------------------------------------------
# 测试包导入
# ---------------------------------------------------------------------------


class TestImports:
    """验证所有核心模块能正确导入。"""

    def test_import_writefont(self) -> None:
        """writefont 包可以导入。"""
        import writefont
        assert hasattr(writefont, "__version__")

    def test_import_pipeline(self) -> None:
        """pipeline 模块可以导入。"""
        from writefont_core.pipeline import WriteFontPipeline, EngineMode, PipelineResult
        assert WriteFontPipeline is not None
        assert EngineMode is not None
        assert PipelineResult is not None

    def test_import_engine_mode(self) -> None:
        """EngineMode 枚举值正确。"""
        from writefont_core.pipeline import EngineMode
        assert EngineMode.LOCAL.value == "local"
        assert EngineMode.API.value == "api"
        assert EngineMode.HYBRID.value == "hybrid"

    def test_import_pipeline_result(self) -> None:
        """PipelineResult 数据类默认值正确。"""
        from writefont_core.pipeline import PipelineResult
        result = PipelineResult()
        assert result.success is True
        assert result.char_count == 0
        assert result.elapsed_seconds == 0.0

    def test_import_ocr(self) -> None:
        """OCR 模块可以导入。"""
        from writefont_core.ocr import OCREngine, OCRResult, RecognizedChar
        assert OCREngine is not None
        assert OCRResult is not None
        assert RecognizedChar is not None

    def test_import_style(self) -> None:
        """Style 模块可以导入。"""
        from writefont_core.style import HandwritingFeatures
        assert HandwritingFeatures is not None

    def test_import_font(self) -> None:
        """Font 模块可以导入。"""
        from writefont_core.font import GlyphVectorizer, FontPackager
        assert GlyphVectorizer is not None
        assert FontPackager is not None

    def test_import_utils(self) -> None:
        """Utils 模块可以导入。"""
        from writefont_core.utils import get_gb2312_chars
        assert callable(get_gb2312_chars)


# ---------------------------------------------------------------------------
# 测试字符集工具
# ---------------------------------------------------------------------------


class TestCharset:
    """验证 GB2312 字符集工具。"""

    def test_get_gb2312_chars(self) -> None:
        """GB2312 全集约 6763 字。"""
        from writefont_core.utils.charset import get_gb2312_chars
        chars = get_gb2312_chars()
        assert len(chars) > 6000
        assert "的" in chars
        assert "人" in chars

    def test_get_gb2312_level1(self) -> None:
        """GB2312 一级字约 3755 字。"""
        from writefont_core.utils.charset import get_gb2312_chars
        chars = get_gb2312_chars(level=1)
        assert 3700 < len(chars) < 3800

    def test_get_gb2312_level2(self) -> None:
        """GB2312 二级字约 3008 字。"""
        from writefont_core.utils.charset import get_gb2312_chars
        chars = get_gb2312_chars(level=2)
        assert 2900 < len(chars) < 3100

    def test_build_char_index(self) -> None:
        """字符索引映射正确。"""
        from writefont_core.utils.charset import build_char_index
        index = build_char_index()
        assert isinstance(index, dict)
        assert "的" in index
        assert index["的"] == 0

    def test_get_ascii_chars(self) -> None:
        """ASCII 字符集包含 95 个字符。"""
        from writefont_core.utils.charset import get_ascii_chars
        chars = get_ascii_chars()
        assert len(chars) == 95
        assert "A" in chars


# ---------------------------------------------------------------------------
# 测试 Pipeline 初始化
# ---------------------------------------------------------------------------


class TestPipeline:
    """验证 Pipeline 的初始化和基本功能。"""

    def test_pipeline_init_default(self) -> None:
        """默认配置初始化成功。"""
        from writefont_core.pipeline import WriteFontPipeline, EngineMode
        pipe = WriteFontPipeline()
        assert pipe.mode == EngineMode.HYBRID
        assert pipe.config is not None
        assert "preprocessing" in pipe.config
        assert "ocr" in pipe.config

    def test_pipeline_init_with_mode(self) -> None:
        """指定模式初始化成功。"""
        from writefont_core.pipeline import WriteFontPipeline, EngineMode
        pipe = WriteFontPipeline(mode=EngineMode.LOCAL)
        assert pipe.mode == EngineMode.LOCAL

    def test_pipeline_config_merge(self) -> None:
        """配置文件正确合并。"""
        from writefont_core.pipeline import WriteFontPipeline
        pipe = WriteFontPipeline()
        # 默认配置应包含所有必要字段
        assert "generator" in pipe.config
        assert "packager" in pipe.config
        assert "output" in pipe.config

    def test_pipeline_run_nonexistent_file(self) -> None:
        """输入文件不存在时返回失败结果。"""
        from writefont_core.pipeline import WriteFontPipeline
        pipe = WriteFontPipeline()
        result = pipe.run("/nonexistent/image.jpg", "/tmp/test.ttf")
        assert result.success is False
        assert "不存在" in result.details.get("error", "")

    def test_pipeline_demo_mode(self) -> None:
        """Demo 模式能生成结果。"""
        from writefont_core.pipeline import WriteFontPipeline, EngineMode
        # 创建一个临时图片
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            # 创建一个简单的 PNG 图片
            from PIL import Image
            img = Image.new("L", (128, 128), color=0)
            img.save(f.name)
            tmp_path = f.name

        try:
            pipe = WriteFontPipeline(mode=EngineMode.HYBRID)
            # 使用 demo provider 测试
            from writefont_core.pipeline import DemoProvider
            demo = DemoProvider()

            # 测试 demo OCR
            ocr_result = demo.demo_ocr(tmp_path)
            assert len(ocr_result) > 0
            assert "char" in ocr_result[0]
            assert "confidence" in ocr_result[0]

            # 测试 demo 风格向量
            style_vec = demo.demo_style_vector()
            assert len(style_vec) == 200

            # 测试 demo 字形生成
            with tempfile.TemporaryDirectory() as tmpdir:
                paths = demo.demo_generate_glyphs(
                    list("永和九年"),
                    Path(tmpdir),
                )
                assert len(paths) == 4
                for p in paths:
                    assert os.path.exists(p)
        finally:
            os.unlink(tmp_path)


# ---------------------------------------------------------------------------
# 测试 StyleTransformer
# ---------------------------------------------------------------------------


class TestStyleTransformer:
    """验证风格变换器。"""

    def test_style_transformer_init(self) -> None:
        """StyleTransformer 初始化成功。"""
        from writefont_core.pipeline import StyleTransformer
        params = {"stroke_width": 1.0, "slant_angle": 0.0}
        transformer = StyleTransformer(params)
        assert transformer.params == params

    def test_style_params_to_vector(self) -> None:
        """风格参数转向量维度正确。"""
        from writefont_core.pipeline import WriteFontPipeline
        params = {
            "stroke_width": 0.5,
            "slant_angle": 0.0,
            "connection_level": 0.3,
            "curvature": 0.3,
            "pressure_variation": 0.4,
            "regularity": 0.6,
            "size_ratio": 0.5,
        }
        vector = WriteFontPipeline._style_params_to_vector(params)
        assert len(vector) == 200
        assert all(isinstance(v, float) for v in vector)

    def test_vector_to_style_params(self) -> None:
        """向量还原风格参数。"""
        from writefont_core.pipeline import WriteFontPipeline
        vector = [0.0] * 200  # 中性向量
        params = WriteFontPipeline._vector_to_style_params(vector)
        assert "stroke_width" in params
        assert "slant_angle" in params
        assert all(0.0 <= v <= 1.0 for v in params.values())


# ---------------------------------------------------------------------------
# 测试 HandwritingFeatures
# ---------------------------------------------------------------------------


class TestHandwritingFeatures:
    """验证笔迹特征模块。"""

    def test_total_dim(self) -> None:
        """总维度为 200。"""
        from writefont_core.style.features import HandwritingFeatures
        assert HandwritingFeatures.total_dim() == 200

    def test_to_vector(self) -> None:
        """特征对象转为 200 维向量。"""
        from writefont_core.style.features import HandwritingFeatures
        feat = HandwritingFeatures()
        vec = feat.to_vector()
        assert len(vec) == 200

    def test_from_vector(self) -> None:
        """从向量重建特征对象。"""
        from writefont_core.style.features import HandwritingFeatures
        import numpy as np
        vec = np.random.randn(200).astype(np.float32)
        feat = HandwritingFeatures.from_vector(vec)
        vec2 = feat.to_vector()
        np.testing.assert_array_almost_equal(vec, vec2, decimal=5)

    def test_feature_ranges(self) -> None:
        """特征范围不重叠且覆盖全部 200 维。"""
        from writefont_core.style.features import HandwritingFeatures
        ranges = HandwritingFeatures.feature_ranges()
        assert len(ranges) == 7
        total = sum(end - start for start, end in ranges.values())
        assert total == 200


# ---------------------------------------------------------------------------
# 测试 Vectorizer
# ---------------------------------------------------------------------------


class TestVectorizer:
    """验证字形矢量化器。"""

    def test_vectorize_empty_image(self) -> None:
        """空图像矢量化返回空轮廓。"""
        from writefont_core.font.vectorizer import GlyphVectorizer
        import numpy as np
        vectorizer = GlyphVectorizer()
        empty = np.zeros((64, 64), dtype=np.uint8)
        contours = vectorizer.vectorize(empty)
        assert isinstance(contours, list)

    def test_vectorize_with_content(self) -> None:
        """有内容的图像矢量化返回非空轮廓。"""
        from writefont_core.font.vectorizer import GlyphVectorizer
        import numpy as np
        vectorizer = GlyphVectorizer()
        # 创建一个简单的白色方块
        img = np.zeros((64, 64), dtype=np.uint8)
        img[16:48, 16:48] = 255
        contours = vectorizer.vectorize(img)
        assert len(contours) > 0


# ---------------------------------------------------------------------------
# 测试 FontPackager
# ---------------------------------------------------------------------------


class TestFontPackager:
    """验证字体打包器。"""

    def test_packager_init(self) -> None:
        """FontPackager 初始化成功。"""
        from writefont_core.font.packager import FontPackager
        packager = FontPackager(font_name="TestFont")
        assert packager.font_name == "TestFont"
        assert packager.units_per_em == 1000

    def test_export_ttf(self) -> None:
        """能导出 TTF 文件。"""
        from writefont_core.font.packager import FontPackager
        from writefont_core.font.vectorizer import Contour, ContourPoint
        import numpy as np

        packager = FontPackager(font_name="TestFont")

        # 添加一个简单字形（方框）
        contours = [
            Contour(points=[
                ContourPoint(x=100, y=0, on_curve=True),
                ContourPoint(x=400, y=0, on_curve=True),
                ContourPoint(x=400, y=700, on_curve=True),
                ContourPoint(x=100, y=700, on_curve=True),
            ])
        ]
        packager.add_glyph(ord("A"), contours, advance_width=500)

        with tempfile.NamedTemporaryFile(suffix=".ttf", delete=False) as f:
            tmp_path = f.name

        try:
            result_path = packager.export(tmp_path, format="ttf")
            assert os.path.exists(str(result_path))
            assert os.path.getsize(str(result_path)) > 0
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)


# ---------------------------------------------------------------------------
# 测试配置加载
# ---------------------------------------------------------------------------


class TestConfig:
    """验证配置文件加载。"""

    def test_default_yaml_exists(self) -> None:
        """默认配置文件存在。"""
        project_root = Path(__file__).parent.parent
        yaml_path = project_root / "configs" / "default.yaml"
        assert yaml_path.exists()

    def test_load_default_yaml(self) -> None:
        """默认 YAML 配置可以正确加载。"""
        import yaml
        project_root = Path(__file__).parent.parent
        yaml_path = project_root / "configs" / "default.yaml"
        with open(yaml_path, "r", encoding="utf-8") as f:
            config = yaml.safe_load(f)
        assert isinstance(config, dict)
        assert "ocr" in config
        assert "style" in config
        assert "generator" in config
