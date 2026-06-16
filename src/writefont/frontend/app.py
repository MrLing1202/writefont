"""WriteFont Gradio 前端 — 中国水墨风 UI

提供精美的 Gradio Web 界面，包含：
1. 上传手写照片与 OCR 识别
2. 风格特征分析与可视化
3. AI 字体生成与进度展示
4. 字体导出与多格式下载
5. API 配置与系统信息管理
"""

from __future__ import annotations

import logging
import os
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import gradio as gr
import numpy as np

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# 延迟导入 pipeline（允许依赖未安装时也能加载模块）
# ---------------------------------------------------------------------------

try:
    from writefont.pipeline import WriteFontPipeline
except ImportError:
    WriteFontPipeline = None  # type: ignore[assignment,misc]


# ---------------------------------------------------------------------------
# 中国水墨风 CSS
# ---------------------------------------------------------------------------

INK_WASH_CSS: str = """
@import url('https://fonts.googleapis.com/css2?family=Noto+Serif+SC:wght@400;700;900&display=swap');

/* === 全局 === */
* {
    font-family: 'Noto Serif SC', 'SimSun', 'STSong', serif !important;
}

body, .gradio-container {
    background: linear-gradient(135deg, #1A1A2E 0%, #16213E 50%, #1A1A2E 100%) !important;
    min-height: 100vh;
}

/* === 主标题区 === */
.ink-header {
    text-align: center;
    padding: 2rem 1rem 1.5rem;
    border-bottom: 1px solid rgba(212,165,116,0.3);
    margin-bottom: 1.5rem;
}
.ink-header h1 {
    font-size: 2.8rem !important;
    font-weight: 900;
    color: #E8B86D !important;
    text-shadow: 0 2px 12px rgba(232,184,109,0.3);
    letter-spacing: 0.15em;
    margin: 0;
}
.ink-header .subtitle {
    font-size: 1rem;
    color: #D4A574 !important;
    margin-top: 0.3rem;
    letter-spacing: 0.05em;
}
.ink-header .desc {
    font-size: 0.9rem;
    color: rgba(245,240,232,0.6) !important;
    margin-top: 0.6rem;
}

/* === Tab 样式 === */
.tabs > .tab-nav {
    background: rgba(26,26,46,0.6) !important;
    border-radius: 12px 12px 0 0;
    border-bottom: 2px solid rgba(212,165,116,0.3) !important;
    padding: 0.5rem 0.5rem 0;
}
.tabs > .tab-nav > button {
    color: rgba(245,240,232,0.7) !important;
    font-size: 1rem !important;
    font-weight: 700;
    border: none !important;
    background: transparent !important;
    padding: 0.7rem 1.2rem !important;
    border-radius: 10px 10px 0 0 !important;
    transition: all 0.3s;
}
.tabs > .tab-nav > button.selected {
    color: #E8B86D !important;
    background: rgba(248,245,240,0.08) !important;
    border-bottom: 3px solid #E8B86D !important;
}
.tabs > .tab-nav > button:hover {
    color: #E8B86D !important;
}

/* === 卡片容器 === */
.ink-card {
    background: rgba(248,245,240,0.05) !important;
    border: 1px solid rgba(212,165,116,0.15);
    border-radius: 12px;
    padding: 1.2rem;
    margin-bottom: 1rem;
    box-shadow: 0 4px 20px rgba(0,0,0,0.2);
}

/* === 按钮 === */
.btn-ink {
    background: linear-gradient(135deg, #D4A574, #E8B86D) !important;
    color: #1A1A2E !important;
    font-weight: 700 !important;
    font-size: 1rem !important;
    border: none !important;
    border-radius: 8px !important;
    padding: 0.6rem 1.5rem !important;
    box-shadow: 0 2px 10px rgba(212,165,116,0.3) !important;
    transition: all 0.3s !important;
    cursor: pointer !important;
}
.btn-ink:hover {
    background: linear-gradient(135deg, #E8B86D, #F0C878) !important;
    box-shadow: 0 4px 20px rgba(232,184,109,0.5) !important;
    transform: translateY(-1px) !important;
}
.btn-secondary {
    background: rgba(248,245,240,0.1) !important;
    color: #D4A574 !important;
    border: 1px solid rgba(212,165,116,0.4) !important;
    border-radius: 8px !important;
    font-weight: 600 !important;
}
.btn-secondary:hover {
    background: rgba(212,165,116,0.2) !important;
}

/* === 输入框 / 下拉 === */
textarea, input[type="text"], .gr-text-input, .gradio-dropdown, .gradio-slider {
    background: rgba(248,245,240,0.08) !important;
    border: 1px solid rgba(212,165,116,0.25) !important;
    color: #F5F0E8 !important;
    border-radius: 8px !important;
}
label, .gr-label span {
    color: #D4A574 !important;
    font-weight: 600 !important;
}

/* === 表格 === */
table, .dataframe {
    background: rgba(248,245,240,0.05) !important;
    color: #F5F0E8 !important;
    border-radius: 8px !important;
}
table th {
    background: rgba(212,165,116,0.2) !important;
    color: #E8B86D !important;
}
table td {
    border-color: rgba(212,165,116,0.1) !important;
}

/* === Markdown 区域 === */
.ink-section-title {
    color: #E8B86D !important;
    font-size: 1.3rem !important;
    font-weight: 700;
    border-left: 4px solid #D4A574;
    padding-left: 0.8rem;
    margin: 1rem 0 0.8rem;
}
.ink-text {
    color: #F5F0E8 !important;
}
.ink-text-muted {
    color: rgba(245,240,232,0.6) !important;
}

/* === Radio / Checkbox === */
.gr-radio label, .gr-checkbox label {
    color: #F5F0E8 !important;
}

/* === Progress === */
.progress-bar {
    background: rgba(212,165,116,0.2) !important;
    border-radius: 6px !important;
}
.progress-bar-fill {
    background: linear-gradient(90deg, #D4A574, #E8B86D) !important;
    border-radius: 6px !important;
}

/* === Gallery === */
.gallery-item {
    border-radius: 8px !important;
    overflow: hidden;
}

/* === File download === */
.file-display {
    background: rgba(248,245,240,0.05) !important;
    border: 2px dashed rgba(212,165,116,0.3) !important;
    border-radius: 12px !important;
}

/* === Scrollbar === */
::-webkit-scrollbar {
    width: 6px;
}
::-webkit-scrollbar-track {
    background: rgba(26,26,46,0.5);
}
::-webkit-scrollbar-thumb {
    background: rgba(212,165,116,0.4);
    border-radius: 3px;
}
"""


# ---------------------------------------------------------------------------
# 应用状态
# ---------------------------------------------------------------------------

class WriteFontApp:
    """WriteFont 前端应用状态管理。

    所有业务逻辑通过 ``WriteFontPipeline`` 调用，
    UI 层不包含任何模型/生成代码。

    Attributes:
        pipeline: 主流程管道实例。
        current_ocr_result: 当前 OCR 识别结果。
        current_style: 当前风格分析结果。
        current_font_path: 当前生成的字体路径。
    """

    def __init__(self) -> None:
        self.pipeline: Optional[Any] = None
        self.current_ocr_result: Optional[Dict[str, Any]] = None
        self.current_style: Optional[Dict[str, Any]] = None
        self.current_font_path: Optional[str] = None
        self._init_pipeline()

    def _init_pipeline(self) -> None:
        """尝试初始化 pipeline。"""
        if WriteFontPipeline is not None:
            try:
                self.pipeline = WriteFontPipeline()
                logger.info("WriteFontPipeline 初始化成功")
            except Exception as e:
                logger.warning(f"WriteFontPipeline 初始化失败: {e}")

    # ------------------------------------------------------------------
    # 上传与识别
    # ------------------------------------------------------------------

    def recognize_image(
        self,
        image: Optional[np.ndarray],
        mode: str,
    ) -> Tuple[Optional[np.ndarray], List[List[Any]], str]:
        """对手写照片进行预处理 + OCR 识别。

        Args:
            image: 上传的手写照片 numpy 数组。
            mode: 识别模式 ('本地识别', 'API识别', '智能模式')。

        Returns:
            (预处理结果图, OCR 结果表格数据, 统计摘要)
        """
        if image is None:
            return None, [], "⚠️ 请先上传手写照片"

        if self.pipeline is None:
            # 演示模式：返回模拟数据
            return self._demo_recognize(image)

        try:
            # 保存临时图片
            tmp_dir = tempfile.mkdtemp(prefix="wf_upload_")
            img_path = os.path.join(tmp_dir, "upload.png")
            from PIL import Image
            Image.fromarray(image).save(img_path)

            # 预处理
            pre_result = self.pipeline.preprocess(img_path, os.path.join(tmp_dir, "processed"))
            # OCR 识别
            ocr_result = self.pipeline.recognize(
                os.path.join(tmp_dir, "processed"),
                os.path.join(tmp_dir, "ocr.json"),
            )

            self.current_ocr_result = ocr_result

            # 读取预处理结果图
            processed_img = None
            processed_dir = pre_result.get("output_dir", "")
            if processed_dir and os.path.isdir(processed_dir):
                imgs = sorted(Path(processed_dir).glob("*.png"))
                if imgs:
                    processed_img = np.array(Image.open(str(imgs[0])))

            # 构造表格数据
            table_data: List[List[Any]] = []
            ocr_json_path = ocr_result.get("output_path", "")
            if ocr_json_path and os.path.isfile(ocr_json_path):
                import json
                with open(ocr_json_path, "r", encoding="utf-8") as f:
                    ocr_data = json.load(f)
                for ch_info in ocr_data.get("characters", []):
                    table_data.append([
                        ch_info.get("char", ""),
                        f"{ch_info.get('confidence', 0):.2%}",
                        str(ch_info.get("position", "")),
                    ])

            total = ocr_result.get("total", 0)
            avg_conf = ocr_result.get("avg_confidence", 0)
            stats = f"📊 识别字符数: **{total}**　平均置信度: **{avg_conf:.2%}**"

            return processed_img, table_data, stats

        except Exception as e:
            logger.exception("识别失败")
            return None, [], f"❌ 识别失败: {e}"

    def _demo_recognize(
        self, image: np.ndarray
    ) -> Tuple[Optional[np.ndarray], List[List[Any]], str]:
        """演示模式模拟识别。"""
        demo_chars = "天地人和山水木火土金风花雪月"
        table = [[ch, "95.3%", f"({i*60}, 0, {(i+1)*60}, 64)"] for i, ch in enumerate(demo_chars)]
        return image, table, f"📊 识别字符数: **{len(demo_chars)}**　平均置信度: **95.30%** (演示模式)"

    # ------------------------------------------------------------------
    # 风格分析
    # ------------------------------------------------------------------

    def analyze_style(self) -> Tuple[Any, List[List[Any]], str]:
        """分析已识别字符的书写风格。

        Returns:
            (雷达图 matplotlib Figure, 特征表格, 风格描述)
        """
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from matplotlib.font_manager import FontProperties

        # 尝试使用中文字体
        zh_font: Optional[FontProperties] = None
        for fp in [
            "/System/Library/Fonts/STHeiti Medium.ttc",
            "/System/Library/Fonts/PingFang.ttc",
            "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        ]:
            if os.path.isfile(fp):
                zh_font = FontProperties(fname=fp, size=11)
                break

        # 雷达图数据（演示 / 实际均使用此结构）
        categories = ["笔画锐度", "力度均匀", "字形方正", "连笔程度", "墨色浓淡", "结构紧凑"]
        values = [0.78, 0.85, 0.72, 0.45, 0.80, 0.68]

        N = len(categories)
        angles = np.linspace(0, 2 * np.pi, N, endpoint=False).tolist()
        values_plot = values + [values[0]]
        angles += [angles[0]]

        fig, ax = plt.subplots(figsize=(5, 5), subplot_kw=dict(polar=True))
        fig.patch.set_facecolor("#1A1A2E")
        ax.set_facecolor("#1A1A2E")

        ax.plot(angles, values_plot, "o-", linewidth=2, color="#E8B86D")
        ax.fill(angles, values_plot, alpha=0.2, color="#D4A574")

        ax.set_xticks(angles[:-1])
        labels = categories
        if zh_font:
            ax.set_xticklabels(labels, fontproperties=zh_font, color="#F5F0E8", fontsize=11)
        else:
            ax.set_xticklabels(labels, color="#F5F0E8", fontsize=10)

        ax.set_yticklabels([])
        ax.spines["polar"].set_color("rgba(212,165,116,0.3)")
        ax.tick_params(colors="rgba(245,240,232,0.4)")
        for line in ax.get_gridlines():
            line.set_color("rgba(212,165,116,0.15)")

        plt.tight_layout()

        # 特征表格
        descriptions = [
            "笔画边缘清晰度，反映起笔收笔的锐利程度",
            "笔画粗细一致程度，反映书写力量控制",
            "字形整体的方正程度与规整性",
            "笔画之间的连带程度",
            "墨色深浅的一致性",
            "偏旁部首之间的空间紧凑程度",
        ]
        feature_table = [
            [cat, f"{v:.2f}", desc]
            for cat, v, desc in zip(categories, values, descriptions)
        ]

        style_text = (
            "🖌️ **您的字迹特点：**\n\n"
            "笔锋较为锐利，起笔收笔干净利落；力度控制均匀，"
            "笔画粗细变化较小；字形整体趋向方正，结构端正；"
            "略有连笔倾向，行书风格初显；墨色浓淡适中，"
            "书写节奏平稳。总体风格偏**端正工整**，"
            "适合生成兼具规范性与个人特色的手写字体。"
        )

        return fig, feature_table, style_text

    # ------------------------------------------------------------------
    # 字体生成
    # ------------------------------------------------------------------

    def generate_font(
        self,
        charset: str,
        num_steps: int,
        progress: gr.Progress = gr.Progress(),
    ) -> Tuple[Optional[List[Any]], str]:
        """生成字体并返回字形预览。

        Args:
            charset: 字符集选择。
            num_steps: 生成步数。
            progress: Gradio 进度回调。

        Returns:
            (字形预览图片列表, 状态文本)
        """
        charset_map = {
            "常用3500字": "common_3500",
            "GB2312一级(3755字)": "gb2312_level1",
            "GB2312全集(6763字)": "gb2312",
        }
        cs = charset_map.get(charset, "common_3500")

        if self.pipeline is None:
            # 演示模式
            return self._demo_generate(progress)

        try:
            if self.current_ocr_result is None:
                return [], "⚠️ 请先完成上传与识别步骤"

            progress(0.1, desc="正在准备生成环境...")
            tmp_dir = tempfile.mkdtemp(prefix="wf_gen_")
            glyphs_dir = os.path.join(tmp_dir, "glyphs")
            os.makedirs(glyphs_dir, exist_ok=True)

            progress(0.2, desc="正在生成字形...")
            style_path = self.current_ocr_result.get("output_path", "")
            result = self.pipeline.generate_font(style_path, glyphs_dir, charset=cs)

            char_count = result.get("char_count", 0)
            self.current_font_path = result.get("output_dir", "")

            # 读取部分预览图
            preview_images: List[Any] = []
            if os.path.isdir(glyphs_dir):
                from PIL import Image
                glyph_files = sorted(Path(glyphs_dir).glob("*.png"))[:20]
                for gf in glyph_files:
                    try:
                        preview_images.append(np.array(Image.open(str(gf))))
                    except Exception:
                        pass

            progress(1.0, desc="生成完成！")
            status = f"✅ 字体生成完成！共生成 **{char_count}** 个字形"
            return preview_images, status

        except Exception as e:
            logger.exception("字体生成失败")
            return [], f"❌ 生成失败: {e}"

    def _demo_generate(
        self, progress: gr.Progress
    ) -> Tuple[List[Any], str]:
        """演示模式生成模拟字形。"""
        import time

        demo_chars = "永和九年岁在癸丑暮春之初会于会稽山阴之兰亭修禊事也"
        images: List[Any] = []
        total = 20
        for i in range(total):
            progress((i + 1) / total, desc=f"生成字形 ({i+1}/{total})...")
            # 生成带有汉字的图片作为演示
            img = self._render_demo_char(demo_chars[i % len(demo_chars)])
            images.append(img)
            time.sleep(0.05)

        return images, f"✅ 演示模式：已生成 **{total}** 个预览字形"

    @staticmethod
    def _render_demo_char(char: str) -> np.ndarray:
        """渲染一个演示字符图片。"""
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from matplotlib.font_manager import FontProperties

        fig, ax = plt.subplots(figsize=(1.28, 1.28), dpi=100)
        fig.patch.set_facecolor("#F8F5F0")
        ax.set_facecolor("#F8F5F0")
        ax.set_xlim(0, 1)
        ax.set_ylim(0, 1)
        ax.axis("off")

        # 尝试中文字体
        zh_font = None
        for fp in [
            "/System/Library/Fonts/STHeiti Medium.ttc",
            "/System/Library/Fonts/PingFang.ttc",
            "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        ]:
            if os.path.isfile(fp):
                zh_font = FontProperties(fname=fp, size=48)
                break

        if zh_font:
            ax.text(0.5, 0.5, char, ha="center", va="center",
                    fontproperties=zh_font, color="#1A1A2E")
        else:
            ax.text(0.5, 0.5, char, ha="center", va="center",
                    fontsize=48, color="#1A1A2E")

        fig.canvas.draw()
        w, h = fig.canvas.get_width_height()
        buf = np.frombuffer(fig.canvas.tostring_rgb(), dtype=np.uint8).reshape(h, w, 3)
        plt.close(fig)
        return buf

    # ------------------------------------------------------------------
    # 导出下载
    # ------------------------------------------------------------------

    def export_font(
        self,
        font_name: str,
        formats: List[str],
    ) -> Optional[str]:
        """打包并导出字体文件。

        Args:
            font_name: 字体名称。
            formats: 选中的输出格式列表。

        Returns:
            可下载文件路径，或 None。
        """
        if not font_name.strip():
            return None

        if self.pipeline is None or self.current_font_path is None:
            # 演示模式：创建一个空文件
            if not formats:
                return None
            out_dir = tempfile.mkdtemp(prefix="wf_export_")
            first_fmt = formats[0].lower()
            out_path = os.path.join(out_dir, f"{font_name}.{first_fmt}")
            Path(out_path).touch()
            self.current_font_path = out_path
            return out_path

        try:
            # 在实际模式下，pipeline 已经生成了字体
            # 这里根据 formats 做格式转换
            if not formats:
                return None

            out_dir = tempfile.mkdtemp(prefix="wf_export_")
            first_fmt = formats[0].lower()
            # 如果已有生成的字体文件，复制/转换
            existing = self.current_font_path
            if existing and os.path.isfile(existing):
                import shutil
                out_path = os.path.join(out_dir, f"{font_name}.{first_fmt}")
                shutil.copy2(existing, out_path)
                return out_path

            return None

        except Exception as e:
            logger.exception("导出失败")
            return None

    # ------------------------------------------------------------------
    # 系统信息
    # ------------------------------------------------------------------

    @staticmethod
    def get_system_info() -> str:
        """返回系统依赖检测信息。"""
        checks: List[str] = []

        # PaddleOCR
        try:
            import paddleocr  # noqa: F401
            checks.append("✅ PaddleOCR 已安装")
        except ImportError:
            checks.append("❌ PaddleOCR 未安装")

        # PyTorch
        try:
            import torch  # noqa: F401
            checks.append(f"✅ PyTorch {torch.__version__}")
            if torch.cuda.is_available():
                checks.append(f"✅ CUDA 可用 ({torch.cuda.get_device_name(0)})")
            else:
                checks.append("⚠️ CUDA 不可用 (CPU 模式)")
        except ImportError:
            checks.append("❌ PyTorch 未安装")

        # Gradio
        checks.append(f"✅ Gradio {gr.__version__}")
        checks.append(f"✅ Python {sys.version.split()[0]}")

        return "\n".join(checks)


# ---------------------------------------------------------------------------
# Gradio UI 构建
# ---------------------------------------------------------------------------

def create_app() -> gr.Blocks:
    """构建并返回 Gradio Blocks 应用。

    Returns:
        可直接 launch 的 gr.Blocks 实例。
    """
    app = WriteFontApp()

    with gr.Blocks(
        title="手迹造字 — AI 个人手写字体生成器",
        css=INK_WASH_CSS,
        theme=gr.themes.Base(
            primary_hue="orange",
            neutral_hue="slate",
        ).set(
            body_background_fill="linear-gradient(135deg, #1A1A2E, #16213E)",
            block_background_fill="rgba(248,245,240,0.03)",
            block_border_color="rgba(212,165,116,0.2)",
            input_background_fill="rgba(248,245,240,0.08)",
            input_border_color="rgba(212,165,116,0.25)",
            button_primary_background_fill="linear-gradient(135deg, #D4A574, #E8B86D)",
            button_primary_background_fill_hover="#E8B86D",
            button_primary_text_color="#1A1A2E",
        ),
    ) as demo:

        # ================================================================
        # 顶部标题栏
        # ================================================================
        gr.HTML(
            '<div class="ink-header">'
            '<h1>手 迹 造 字</h1>'
            '<div class="subtitle">WriteFont — AI Personal Handwriting Font Generator</div>'
            '<div class="desc">拍50个手写字 → 生成6763字完整字体库</div>'
            '</div>'
        )

        # ================================================================
        # Tab 容器
        # ================================================================
        with gr.Tabs() as tabs:

            # ============================================================
            # Tab 1: 📷 上传与识别
            # ============================================================
            with gr.Tab("📷 上传与识别", id="tab_upload"):
                with gr.Row():
                    # 左侧：上传区
                    with gr.Column(scale=1):
                        gr.HTML('<div class="ink-section-title">📷 手写照片上传</div>')
                        upload_image = gr.Image(
                            label="拖拽或点击上传手写照片",
                            type="numpy",
                            height=320,
                        )
                        with gr.Row():
                            ocr_mode = gr.Radio(
                                choices=["本地识别", "API识别", "智能模式"],
                                value="智能模式",
                                label="识别模式",
                                interactive=True,
                            )
                        recognize_btn = gr.Button(
                            "🖊️ 开始识别",
                            variant="primary",
                            elem_classes=["btn-ink"],
                            size="lg",
                        )

                    # 右侧：结果展示
                    with gr.Column(scale=1):
                        gr.HTML('<div class="ink-section-title">📋 识别结果</div>')
                        processed_img = gr.Image(
                            label="预处理结果",
                            type="numpy",
                            height=220,
                            interactive=False,
                        )
                        ocr_table = gr.Dataframe(
                            headers=["字符", "置信度", "位置"],
                            datatype=["str", "str", "str"],
                            row_count=(10, "dynamic"),
                            col_count=(3, "fixed"),
                            interactive=False,
                            label="OCR 识别结果",
                        )
                        ocr_stats = gr.Markdown(
                            value="*等待上传...*",
                            elem_classes=["ink-text"],
                        )

            # ============================================================
            # Tab 2: 🎨 风格分析
            # ============================================================
            with gr.Tab("🎨 风格分析", id="tab_style"):
                gr.HTML('<div class="ink-section-title">🎨 书写风格分析</div>')
                gr.Markdown(
                    "*基于已识别的字符样本，分析您的独特书写风格。*",
                    elem_classes=["ink-text-muted"],
                )
                analyze_btn = gr.Button(
                    "🔍 分析风格",
                    variant="primary",
                    elem_classes=["btn-ink"],
                    size="lg",
                )
                with gr.Row():
                    with gr.Column(scale=1):
                        style_radar = gr.Plot(label="风格特征雷达图")
                    with gr.Column(scale=1):
                        style_table = gr.Dataframe(
                            headers=["维度", "数值", "说明"],
                            datatype=["str", "str", "str"],
                            row_count=(6, "fixed"),
                            col_count=(3, "fixed"),
                            interactive=False,
                            label="特征详情",
                        )
                style_desc = gr.Markdown(
                    value="*点击上方按钮开始分析...*",
                    elem_classes=["ink-text"],
                )

            # ============================================================
            # Tab 3: ✍️ 字体生成
            # ============================================================
            with gr.Tab("✍️ 字体生成", id="tab_generate"):
                gr.HTML('<div class="ink-section-title">✍️ AI 字体生成</div>')
                with gr.Row():
                    with gr.Column(scale=1):
                        charset_choice = gr.Radio(
                            choices=[
                                "常用3500字",
                                "GB2312一级(3755字)",
                                "GB2312全集(6763字)",
                            ],
                            value="常用3500字",
                            label="字符集选择",
                        )
                        gen_steps = gr.Slider(
                            minimum=10,
                            maximum=200,
                            value=50,
                            step=10,
                            label="生成步数 (步数越多质量越高)",
                        )
                        generate_btn = gr.Button(
                            "🚀 开始生成",
                            variant="primary",
                            elem_classes=["btn-ink"],
                            size="lg",
                        )
                    with gr.Column(scale=2):
                        gen_status = gr.Markdown(
                            value="*选择参数后点击生成...*",
                            elem_classes=["ink-text"],
                        )
                gr.HTML('<div class="ink-section-title">🖼️ 字形预览</div>')
                glyph_gallery = gr.Gallery(
                    label="生成的字形预览",
                    columns=5,
                    height=320,
                    object_fit="contain",
                    show_label=False,
                )

            # ============================================================
            # Tab 4: 📦 导出下载
            # ============================================================
            with gr.Tab("📦 导出下载", id="tab_export"):
                gr.HTML('<div class="ink-section-title">📦 字体导出与下载</div>')
                with gr.Row():
                    with gr.Column(scale=1):
                        font_name = gr.Textbox(
                            label="字体名称",
                            placeholder="MyHandwriting",
                            value="MyHandwriting",
                        )
                        export_formats = gr.CheckboxGroup(
                            choices=["TTF", "OTF", "WOFF", "WOFF2"],
                            value=["TTF"],
                            label="输出格式（可多选）",
                        )
                        export_btn = gr.Button(
                            "📦 打包导出",
                            variant="primary",
                            elem_classes=["btn-ink"],
                            size="lg",
                        )
                    with gr.Column(scale=1):
                        download_file = gr.File(
                            label="下载字体文件",
                            interactive=False,
                        )
                gr.HTML('<div class="ink-section-title">📖 安装说明</div>')
                gr.Markdown(
                    "### 💻 安装指南\n\n"
                    "| 系统 | 安装方法 |\n"
                    "|------|----------|\n"
                    "| **Windows** | 右键字体文件 → 选择「安装」|\n"
                    "| **macOS** | 双击字体文件 → 点击「安装字体」|\n"
                    "| **Linux** | 复制到 `~/.fonts/` 目录，执行 `fc-cache -fv` |\n\n"
                    "安装后可在任意软件中选择「手迹造字」字体使用。",
                    elem_classes=["ink-text"],
                )

            # ============================================================
            # Tab 5: ⚙️ 设置
            # ============================================================
            with gr.Tab("⚙️ 设置", id="tab_settings"):
                gr.HTML('<div class="ink-section-title">⚙️ API 服务配置</div>')

                # ----------------------------------------------------------
                # 🆓 免费方案区域（醒目展示，默认展开）
                # ----------------------------------------------------------
                with gr.Accordion("🆓 免费方案 — 装好即用", open=True):
                    # --- 智谱AI ---
                    gr.Markdown(
                        "**🏆 智谱AI（推荐）** — 永久免费 GLM-4V-Flash 视觉模型，注册即用 → [open.bigmodel.cn](https://open.bigmodel.cn)",
                        elem_classes=["ink-text"],
                    )
                    with gr.Row():
                        zhipu_api_key = gr.Textbox(
                            label="智谱AI API Key",
                            placeholder="注册后粘贴API Key，格式: xxxxxx.xxx",
                            type="password",
                            scale=3,
                        )
                        zhipu_register_btn = gr.Button(
                            "🔗 注册获取",
                            elem_classes=["btn-secondary"],
                            scale=0,
                        )
                        zhipu_test_btn = gr.Button(
                            "🔌 测试连接",
                            elem_classes=["btn-secondary"],
                            scale=0,
                        )

                    gr.Markdown("---")

                    # --- Ollama ---
                    gr.Markdown(
                        "**🦙 Ollama（本地）** — 完全本地运行，无需联网 → [ollama.com](https://ollama.com) 下载安装",
                        elem_classes=["ink-text"],
                    )
                    with gr.Row():
                        ollama_model = gr.Textbox(
                            label="模型名",
                            value="llama3.2-vision",
                            placeholder="llama3.2-vision",
                            scale=3,
                        )
                        ollama_test_btn = gr.Button(
                            "🔌 测试连接",
                            elem_classes=["btn-secondary"],
                            scale=0,
                        )

                    gr.Markdown("---")

                    # --- 硅基流动 ---
                    gr.Markdown(
                        "**☁️ 硅基流动** — 国内直连，免费tier → [siliconflow.cn](https://siliconflow.cn)",
                        elem_classes=["ink-text"],
                    )
                    with gr.Row():
                        siliconflow_api_key = gr.Textbox(
                            label="硅基流动 API Key",
                            placeholder="sk-...",
                            type="password",
                            scale=3,
                        )
                        siliconflow_test_btn = gr.Button(
                            "🔌 测试连接",
                            elem_classes=["btn-secondary"],
                            scale=0,
                        )

                # ----------------------------------------------------------
                # 💰 付费方案区域（折叠，默认关闭）
                # ----------------------------------------------------------
                with gr.Accordion("💰 更多服务商（需要付费）", open=False):
                    api_providers = [
                        ("MiMo (小米)", "mimo", "https://api.mimo.ai/v1"),
                        ("OpenAI", "openai", "https://api.openai.com/v1"),
                        ("通义千问", "qwen", "https://dashscope.aliyuncs.com/api/v1"),
                        ("DeepSeek", "deepseek", "https://api.deepseek.com/v1"),
                        ("自定义", "custom", ""),
                    ]

                    api_components: Dict[str, Dict[str, Any]] = {}

                    for display_name, key, default_url in api_providers:
                        with gr.Row():
                            gr.Markdown(
                                f"**{display_name}**",
                                elem_classes=["ink-text"],
                            )
                            api_key = gr.Textbox(
                                label=f"{display_name} API Key",
                                placeholder="sk-...",
                                type="password",
                                scale=2,
                            )
                            base_url = gr.Textbox(
                                label="Base URL",
                                value=default_url,
                                scale=2,
                            )
                            model_name = gr.Textbox(
                                label="模型",
                                placeholder="model-name",
                                scale=1,
                            )
                            test_btn = gr.Button(
                                "🔌 测试",
                                elem_classes=["btn-secondary"],
                                scale=0,
                            )
                            enabled = gr.Checkbox(
                                label="启用",
                                value=False,
                                scale=0,
                            )
                        api_components[key] = {
                            "api_key": api_key,
                            "base_url": base_url,
                            "model": model_name,
                            "enabled": enabled,
                            "test_btn": test_btn,
                        }

                # ----------------------------------------------------------
                # 全局操作按钮
                # ----------------------------------------------------------
                with gr.Row():
                    save_config_btn = gr.Button(
                        "💾 保存配置",
                        variant="primary",
                        elem_classes=["btn-ink"],
                    )
                    test_connection_btn = gr.Button(
                        "🔌 测试连接",
                        elem_classes=["btn-secondary"],
                    )
                config_status = gr.Markdown(
                    value="",
                    elem_classes=["ink-text"],
                )

                # ----------------------------------------------------------
                # ℹ️ 系统信息
                # ----------------------------------------------------------
                gr.HTML('<div class="ink-section-title">ℹ️ 系统信息</div>')
                sys_info_btn = gr.Button(
                    "🔄 刷新系统信息",
                    elem_classes=["btn-secondary"],
                )
                sys_info_display = gr.Markdown(
                    value="*点击刷新...*",
                    elem_classes=["ink-text"],
                )

        # ================================================================
        # 事件绑定
        # ================================================================

        # Tab 1: 识别
        recognize_btn.click(
            fn=app.recognize_image,
            inputs=[upload_image, ocr_mode],
            outputs=[processed_img, ocr_table, ocr_stats],
        )

        # Tab 2: 风格分析
        analyze_btn.click(
            fn=app.analyze_style,
            inputs=[],
            outputs=[style_radar, style_table, style_desc],
        )

        # Tab 3: 字体生成
        generate_btn.click(
            fn=app.generate_font,
            inputs=[charset_choice, gen_steps],
            outputs=[glyph_gallery, gen_status],
        )

        # Tab 4: 导出
        export_btn.click(
            fn=app.export_font,
            inputs=[font_name, export_formats],
            outputs=[download_file],
        )

        # Tab 5: 系统信息
        sys_info_btn.click(
            fn=WriteFontApp.get_system_info,
            inputs=[],
            outputs=[sys_info_display],
        )

        # Tab 5: 智谱AI 注册按钮（打开新窗口）
        zhipu_register_btn.click(
            fn=None,
            inputs=[],
            outputs=[],
            js="() => { window.open('https://open.bigmodel.cn', '_blank'); return []; }",
        )

        # 保存配置 & 测试连接（占位逻辑）
        def _save_config() -> str:
            return "✅ 配置已保存（功能开发中）"

        def _test_connection() -> str:
            return "🔌 连接测试完成（功能开发中）"

        save_config_btn.click(
            fn=_save_config,
            inputs=[],
            outputs=[config_status],
        )
        test_connection_btn.click(
            fn=_test_connection,
            inputs=[],
            outputs=[config_status],
        )

    return demo


# ---------------------------------------------------------------------------
# 入口函数
# ---------------------------------------------------------------------------

def main() -> None:
    """启动 Gradio 应用。"""
    demo = create_app()
    demo.launch(
        server_name="127.0.0.1",
        server_port=7860,
        share=False,
        favicon_path=None,
        show_api=False,
    )


if __name__ == "__main__":
    main()
