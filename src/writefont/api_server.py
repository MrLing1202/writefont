"""
手迹造字 WriteFont — REST API 服务器

基于 FastAPI 提供 HTTP 接口，支持：
- POST /api/v1/recognize  上传手写图片，返回 OCR 识别文字
- POST /api/v1/generate   上传手写图片，生成 TTF 字体文件
- GET  /api/v1/health     健康检查
- GET  /                  使用说明页面

所有 API Key 通过环境变量或配置文件读取，不在代码中硬编码。
"""

from __future__ import annotations

import io
import json
import logging
import os
import re
import shutil
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# 安全常量
# ---------------------------------------------------------------------------

MAX_UPLOAD_SIZE = 10 * 1024 * 1024  # 10 MB
ALLOWED_MIME_PREFIX = "image/"
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp", ".tiff"}

# ---------------------------------------------------------------------------
# 延迟导入 pipeline（允许依赖未安装时也能加载模块）
# ---------------------------------------------------------------------------

try:
    from writefont_core.pipeline import WriteFontPipeline
except ImportError:
    WriteFontPipeline = None  # type: ignore[assignment,misc]


# ---------------------------------------------------------------------------
# FastAPI 应用实例
# ---------------------------------------------------------------------------

app = FastAPI(
    title="手迹造字 WriteFont API",
    description="从手写样本生成完整字体库的 REST API",
    version="0.2.0",
)

# ---------------------------------------------------------------------------
# CORS 中间件
# ---------------------------------------------------------------------------

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# 全局 pipeline 实例（惰性初始化，线程安全）
# ---------------------------------------------------------------------------

_pipeline: Optional[Any] = None
_pipeline_lock = threading.Lock()


def _get_pipeline() -> Any:
    """获取或初始化 WriteFontPipeline 实例（线程安全）。

    首次调用时初始化，后续复用同一实例。
    API Key 等敏感信息通过环境变量或配置文件读取。

    Returns:
        WriteFontPipeline 实例

    Raises:
        RuntimeError: 如果 writefont_core 未安装或初始化失败
    """
    global _pipeline
    if _pipeline is not None:
        return _pipeline

    with _pipeline_lock:
        # 双重检查：获锁后再次判断，避免重复初始化
        if _pipeline is not None:
            return _pipeline

        if WriteFontPipeline is None:
            raise RuntimeError(
                "writefont_core 未安装，请先执行: pip install writefont-core"
            )

        try:
            config_path = os.environ.get("WRITEFONT_CONFIG")
            _pipeline = WriteFontPipeline(config_path=config_path)
            logger.info("WriteFontPipeline 初始化成功")
            return _pipeline
        except Exception:
            logger.exception("WriteFontPipeline 初始化失败")
            raise RuntimeError("服务初始化失败，请检查配置")


# ---------------------------------------------------------------------------
# 首页 — 使用说明
# ---------------------------------------------------------------------------

@app.get("/", response_class=HTMLResponse)
async def index() -> str:
    """返回简单的 API 使用说明页面。"""
    return """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>手迹造字 WriteFont API</title>
    <style>
        * { font-family: 'Noto Serif SC', 'SimSun', 'STSong', serif; }
        body {
            background: linear-gradient(135deg, #1A1A2E 0%, #16213E 50%, #1A1A2E 100%);
            color: #F5F0E8;
            min-height: 100vh;
            padding: 2rem;
            max-width: 800px;
            margin: 0 auto;
        }
        h1 {
            color: #E8B86D;
            font-size: 2.2rem;
            text-align: center;
            margin-bottom: 0.5rem;
        }
        .subtitle {
            text-align: center;
            color: #D4A574;
            margin-bottom: 2rem;
        }
        h2 { color: #E8B86D; border-left: 4px solid #D4A574; padding-left: 0.8rem; }
        .endpoint {
            background: rgba(248,245,240,0.05);
            border: 1px solid rgba(212,165,116,0.2);
            border-radius: 8px;
            padding: 1rem;
            margin: 1rem 0;
        }
        .method { color: #E8B86D; font-weight: bold; }
        .path { color: #F5F0E8; font-family: monospace; }
        code {
            background: rgba(248,245,240,0.1);
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 0.9em;
        }
        pre {
            background: rgba(0,0,0,0.3);
            padding: 1rem;
            border-radius: 8px;
            overflow-x: auto;
            font-size: 0.85em;
        }
        a { color: #D4A574; }
        footer {
            text-align: center;
            margin-top: 3rem;
            color: rgba(245,240,232,0.4);
            font-size: 0.85rem;
        }
    </style>
</head>
<body>
    <h1>手 迹 造 字</h1>
    <p class="subtitle">WriteFont REST API — 从手写样本生成完整字体库</p>

    <h2>接口列表</h2>

    <div class="endpoint">
        <p><span class="method">GET</span> <span class="path">/api/v1/health</span></p>
        <p>健康检查，返回服务状态。</p>
    </div>

    <div class="endpoint">
        <p><span class="method">POST</span> <span class="path">/api/v1/recognize</span></p>
        <p>上传手写图片，返回 OCR 识别结果。</p>
        <p>参数：<code>file</code> — 手写图片文件（multipart/form-data）</p>
<pre>
curl -X POST http://localhost:8000/api/v1/recognize \\
     -F "file=@handwriting.jpg"
</pre>
    </div>

    <div class="endpoint">
        <p><span class="method">POST</span> <span class="path">/api/v1/generate</span></p>
        <p>上传手写图片，生成 TTF 字体文件并返回下载流。</p>
        <p>参数：</p>
        <ul>
            <li><code>file</code> — 手写图片文件</li>
            <li><code>charset</code> — 字符集（可选，默认 <code>common_3500</code>）</li>
            <li><code>font_name</code> — 字体名称（可选，默认 <code>MyHandwriting</code>）</li>
        </ul>
<pre>
curl -X POST http://localhost:8000/api/v1/generate \\
     -F "file=@handwriting.jpg" \\
     -F "charset=common_3500" \\
     -F "font_name=MyFont" \\
     --output font.ttf
</pre>
    </div>

    <h2>配置说明</h2>
    <p>API Key 等敏感信息通过以下方式配置（不在代码中硬编码）：</p>
    <ul>
        <li><strong>环境变量</strong>：设置 <code>WRITEFONT_CONFIG</code> 指向配置文件路径</li>
        <li><strong>默认路径</strong>：<code>~/.writefont/api_config.json</code></li>
    </ul>

    <h2>交互式文档</h2>
    <p>访问 <a href="/docs">/docs</a> 查看 Swagger UI 交互式文档。</p>
    <p>访问 <a href="/redoc">/redoc</a> 查看 ReDoc 文档。</p>

    <footer>手迹造字 WriteFont v0.2.0</footer>
</body>
</html>"""


# ---------------------------------------------------------------------------
# 健康检查
# ---------------------------------------------------------------------------

@app.get("/api/v1/health")
async def health() -> Dict[str, Any]:
    """健康检查接口（含实际 pipeline 可用性验证）。

    Returns:
        包含状态、版本、pipeline 状态的字典
    """
    pipeline_ok = WriteFontPipeline is not None
    pipeline_initialized = _pipeline is not None

    # 尝试实际获取 pipeline 来验证服务可用性
    pipeline_healthy = False
    try:
        _get_pipeline()
        pipeline_healthy = True
    except Exception:
        pass

    status = "ok" if pipeline_healthy else "degraded"
    return {
        "status": status,
        "version": "0.2.0",
        "pipeline_available": pipeline_ok,
        "pipeline_initialized": pipeline_initialized,
        "pipeline_healthy": pipeline_healthy,
    }


# ---------------------------------------------------------------------------
# OCR 识别
# ---------------------------------------------------------------------------

@app.post("/api/v1/recognize")
async def recognize(
    file: UploadFile = File(..., description="手写图片文件"),
) -> JSONResponse:
    """上传手写图片，返回 OCR 识别文字。

    Args:
        file: 上传的手写图片（支持 jpg/png/bmp 等格式）

    Returns:
        JSON 响应，包含识别字符列表、数量、平均置信度等信息

    Raises:
        400: 文件格式不支持
        500: 识别过程出错
    """
    # 验证文件类型
    if not file.content_type or not file.content_type.startswith(ALLOWED_MIME_PREFIX):
        raise HTTPException(status_code=400, detail="请上传图片文件（jpg/png/bmp）")

    tmp_dir = tempfile.mkdtemp(prefix="wf_api_recognize_")
    try:
        # 读取上传内容（限制大小）
        content = await file.read()
        if len(content) == 0:
            raise HTTPException(status_code=400, detail="上传的文件为空")
        if len(content) > MAX_UPLOAD_SIZE:
            raise HTTPException(status_code=413, detail="文件大小超过 10MB 限制")

        # 安全处理文件名
        safe_filename = _sanitize_filename(file.filename)
        ext = _guess_image_ext(safe_filename, file.content_type)
        img_path = os.path.join(tmp_dir, f"upload{ext}")
        with open(img_path, "wb") as f:
            f.write(content)

        # 调用 pipeline 进行识别
        pipeline = _get_pipeline()

        # 预处理
        processed_dir = os.path.join(tmp_dir, "processed")
        pre_result = pipeline.preprocess(img_path, processed_dir)

        # OCR 识别
        ocr_output = os.path.join(tmp_dir, "ocr.json")
        ocr_result = pipeline.recognize(processed_dir, ocr_output)

        # 读取识别结果
        characters: List[Dict[str, Any]] = []
        if os.path.isfile(ocr_output):
            with open(ocr_output, "r", encoding="utf-8") as f:
                ocr_data = json.load(f)
            for ch_info in ocr_data.get("characters", []):
                characters.append({
                    "char": ch_info.get("char", ""),
                    "confidence": ch_info.get("confidence", 0),
                    "position": ch_info.get("position", ""),
                })

        return JSONResponse(content={
            "success": True,
            "total": ocr_result.get("total", len(characters)),
            "avg_confidence": ocr_result.get("avg_confidence", 0),
            "characters": characters,
        })

    except HTTPException:
        raise
    except RuntimeError:
        raise HTTPException(status_code=500, detail="服务暂不可用，请稍后重试")
    except Exception:
        logger.exception("识别接口异常")
        raise HTTPException(status_code=500, detail="识别处理失败，请稍后重试")
    finally:
        try:
            shutil.rmtree(tmp_dir, ignore_errors=True)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# 字体生成
# ---------------------------------------------------------------------------

@app.post("/api/v1/generate")
async def generate(
    file: UploadFile = File(..., description="手写图片文件"),
    charset: str = Form("common_3500", description="字符集: common_3500 / gb2312_level1 / gb2312"),
    font_name: str = Form("MyHandwriting", description="字体名称"),
) -> StreamingResponse:
    """上传手写图片，生成 TTF 字体文件。

    完整流程：预处理 → OCR 识别 → 风格提取 → 字体生成。

    Args:
        file: 上传的手写图片
        charset: 字符集选择（common_3500 / gb2312_level1 / gb2312）
        font_name: 输出字体名称

    Returns:
        StreamingResponse 返回 TTF 字体文件流

    Raises:
        400: 参数错误
        500: 生成过程出错
    """
    # 验证文件类型
    if not file.content_type or not file.content_type.startswith(ALLOWED_MIME_PREFIX):
        raise HTTPException(status_code=400, detail="请上传图片文件（jpg/png/bmp）")

    # 验证字符集参数
    valid_charsets = {"common_3500", "gb2312_level1", "gb2312"}
    if charset not in valid_charsets:
        raise HTTPException(
            status_code=400,
            detail=f"不支持的字符集，可选值: {', '.join(valid_charsets)}",
        )

    tmp_dir = tempfile.mkdtemp(prefix="wf_api_generate_")
    try:
        # 读取上传内容（限制大小）
        content = await file.read()
        if len(content) == 0:
            raise HTTPException(status_code=400, detail="上传的文件为空")
        if len(content) > MAX_UPLOAD_SIZE:
            raise HTTPException(status_code=413, detail="文件大小超过 10MB 限制")

        # 安全处理文件名
        safe_filename = _sanitize_filename(file.filename)
        ext = _guess_image_ext(safe_filename, file.content_type)
        img_path = os.path.join(tmp_dir, f"upload{ext}")
        with open(img_path, "wb") as f:
            f.write(content)

        # 获取 pipeline
        pipeline = _get_pipeline()

        # 第一步：预处理
        processed_dir = os.path.join(tmp_dir, "processed")
        pipeline.preprocess(img_path, processed_dir)

        # 第二步：OCR 识别
        ocr_output = os.path.join(tmp_dir, "ocr.json")
        pipeline.recognize(processed_dir, ocr_output)

        # 第三步：字体生成
        output_dir = os.path.join(tmp_dir, "output")
        os.makedirs(output_dir, exist_ok=True)
        result = pipeline.generate_font(ocr_output, output_dir, charset=charset)

        # 查找生成的字体文件
        font_path = result.get("font_path", "")
        if not font_path or not os.path.isfile(font_path):
            # 尝试在输出目录中查找 ttf 文件
            ttf_files = list(Path(output_dir).glob("*.ttf"))
            if ttf_files:
                font_path = str(ttf_files[0])
            else:
                raise HTTPException(status_code=500, detail="字体文件生成失败，未找到输出文件")

        # 读取字体文件到内存
        font_bytes = Path(font_path).read_bytes()

        # 构建安全的文件名
        safe_name = "".join(c for c in font_name if c.isalnum() or c in "-_ ").strip()
        if not safe_name:
            safe_name = "MyHandwriting"
        download_name = f"{safe_name}.ttf"

        # 返回文件流
        return StreamingResponse(
            io.BytesIO(font_bytes),
            media_type="font/sfnt",
            headers={
                "Content-Disposition": f'attachment; filename="{download_name}"',
                "Content-Length": str(len(font_bytes)),
            },
        )

    except HTTPException:
        raise
    except RuntimeError:
        raise HTTPException(status_code=500, detail="服务暂不可用，请稍后重试")
    except Exception:
        logger.exception("生成接口异常")
        raise HTTPException(status_code=500, detail="字体生成失败，请稍后重试")
    finally:
        try:
            shutil.rmtree(tmp_dir, ignore_errors=True)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------

def _sanitize_filename(filename: Optional[str]) -> Optional[str]:
    """消毒文件名，防止路径穿越和非法字符。

    仅保留字母、数字、连字符、下划线和点号，
    丢弃目录路径部分。

    Args:
        filename: 原始上传文件名

    Returns:
        消毒后的文件名，仅含安全字符
    """
    if not filename:
        return None
    # 取最后的文件名部分（防路径穿越）
    name = Path(filename).name
    # 只保留安全字符
    name = re.sub(r"[^a-zA-Z0-9._\-]", "_", name)
    # 去掉前导点号（防隐藏文件）
    name = name.lstrip(".")
    return name or None


def _guess_image_ext(filename: Optional[str], content_type: str) -> str:
    """根据文件名和 content_type 推断图片扩展名。

    Args:
        filename: 原始文件名
        content_type: MIME 类型

    Returns:
        带点号的扩展名，如 ".jpg"
    """
    # 先从文件名提取
    if filename:
        suffix = Path(filename).suffix.lower()
        if suffix in ALLOWED_EXTENSIONS:
            return suffix

    # 从 content_type 推断
    mime_map = {
        "image/jpeg": ".jpg",
        "image/png": ".png",
        "image/bmp": ".bmp",
        "image/gif": ".gif",
        "image/webp": ".webp",
        "image/tiff": ".tiff",
    }
    return mime_map.get(content_type, ".png")


# ---------------------------------------------------------------------------
# 启动入口
# ---------------------------------------------------------------------------

def start_server(
    host: str = "0.0.0.0",
    port: int = 8000,
    reload: bool = False,
) -> None:
    """启动 FastAPI 服务器。

    Args:
        host: 监听地址
        port: 监听端口
        reload: 是否开启热重载（开发模式）
    """
    import uvicorn

    print("\n" + "=" * 50)
    print("  🖌️  手迹造字 WriteFont API 服务器")
    print(f"  监听地址: http://{host}:{port}")
    print(f"  API 文档: http://{host}:{port}/docs")
    print("=" * 50 + "\n")

    uvicorn.run(
        "writefont.api_server:app",
        host=host,
        port=port,
        reload=reload,
        log_level="info",
    )


if __name__ == "__main__":
    # 支持直接运行: python -m writefont.api_server
    host = os.environ.get("WRITEFONT_HOST", "0.0.0.0")
    port = int(os.environ.get("WRITEFONT_PORT", "8000"))
    start_server(host=host, port=port)
