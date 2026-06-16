"""
手迹造字 (WriteFont) - AI字体生成工具

从手写样本生成完整字体库的本地AI应用。
支持本地算力推理 + API云端推理双模式。

核心引擎已迁移到 writefont-core 私有包。
本包仅提供 UI 层（Gradio 前端 + API 配置管理）。
"""

__version__ = "0.2.0"
__author__ = "WriteFont"

try:
    from writefont_core import WriteFontPipeline, EngineMode, PipelineResult
except ImportError:
    WriteFontPipeline = None  # type: ignore[assignment,misc]
    EngineMode = None  # type: ignore[assignment,misc]
    PipelineResult = None  # type: ignore[assignment,misc]

__all__ = [
    "WriteFontPipeline",
    "EngineMode",
    "PipelineResult",
]
