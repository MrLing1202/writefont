# 手迹造字 WriteFont — REST API 使用说明

## 快速开始

### 1. 启动 API 服务器

```bash
# 方式一：通过 start.py 启动（推荐）
python start.py --api

# 方式二：指定端口
python start.py --api --port 9000

# 方式三：仅监听本地
python start.py --api --host 127.0.0.1 --port 8000

# 方式四：直接运行模块
python -m writefont.api_server
```

启动后访问：
- 首页说明：http://localhost:8000/
- Swagger 文档：http://localhost:8000/docs
- ReDoc 文档：http://localhost:8000/redoc

### 2. 安装依赖

```bash
pip install -r requirements.txt
```

确保已安装 `fastapi` 和 `uvicorn`：

```bash
pip install fastapi uvicorn
```

---

## API 接口

### 健康检查

```
GET /api/v1/health
```

检查服务状态和 pipeline 可用性。

**示例：**

```bash
curl http://localhost:8000/api/v1/health
```

**响应：**

```json
{
  "status": "ok",
  "version": "0.2.0",
  "pipeline_available": true,
  "pipeline_initialized": true
}
```

---

### OCR 识别

```
POST /api/v1/recognize
```

上传手写图片，返回 OCR 识别结果。

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file` | 文件 | 是 | 手写图片文件（jpg/png/bmp） |

**示例：**

```bash
curl -X POST http://localhost:8000/api/v1/recognize \
     -F "file=@handwriting.jpg"
```

**响应：**

```json
{
  "success": true,
  "total": 16,
  "avg_confidence": 0.953,
  "characters": [
    {"char": "天", "confidence": 0.98, "position": "(0, 0, 60, 64)"},
    {"char": "地", "confidence": 0.96, "position": "(60, 0, 120, 64)"},
    ...
  ]
}
```

---

### 字体生成

```
POST /api/v1/generate
```

上传手写图片，执行完整流程（预处理 → OCR → 风格提取 → 字体生成），返回 TTF 字体文件。

**参数：**

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `file` | 文件 | 是 | - | 手写图片文件 |
| `charset` | 字符串 | 否 | `common_3500` | 字符集：`common_3500` / `gb2312_level1` / `gb2312` |
| `font_name` | 字符串 | 否 | `MyHandwriting` | 字体名称 |

**示例：**

```bash
# 生成常用 3500 字字体
curl -X POST http://localhost:8000/api/v1/generate \
     -F "file=@handwriting.jpg" \
     -F "charset=common_3500" \
     -F "font_name=MyFont" \
     --output my_font.ttf

# 生成 GB2312 全集字体
curl -X POST http://localhost:8000/api/v1/generate \
     -F "file=@handwriting.jpg" \
     -F "charset=gb2312" \
     --output full_font.ttf
```

**响应：** 直接返回 TTF 字体文件流（`Content-Type: font/sfnt`）。

---

## 配置说明

### API Key 配置

API Key 等敏感信息**不在代码中硬编码**，通过以下方式配置：

1. **环境变量**：设置 `WRITEFONT_CONFIG` 指向配置文件路径
   ```bash
   export WRITEFONT_CONFIG=/path/to/api_config.json
   ```

2. **默认路径**：`~/.writefont/api_config.json`

3. **配置文件格式**：
   ```json
   {
     "providers": {
       "zhipuai": {
         "base_url": "https://open.bigmodel.cn/api/paas/v4",
         "api_key": "your-api-key-here",
         "model": "glm-4v-flash",
         "enabled": true
       }
     }
   }
   ```

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `WRITEFONT_CONFIG` | 配置文件路径 | `~/.writefont/api_config.json` |
| `WRITEFONT_HOST` | 服务器监听地址 | `0.0.0.0` |
| `WRITEFONT_PORT` | 服务器监听端口 | `8000` |

---

## Python 调用示例

### 使用 requests 库

```python
import requests

# OCR 识别
with open("handwriting.jpg", "rb") as f:
    resp = requests.post(
        "http://localhost:8000/api/v1/recognize",
        files={"file": ("handwriting.jpg", f, "image/jpeg")},
    )
    result = resp.json()
    print(f"识别到 {result['total']} 个字符")

# 字体生成
with open("handwriting.jpg", "rb") as f:
    resp = requests.post(
        "http://localhost:8000/api/v1/generate",
        files={"file": ("handwriting.jpg", f, "image/jpeg")},
        data={"charset": "common_3500", "font_name": "MyFont"},
    )
    with open("output.ttf", "wb") as out:
        out.write(resp.content)
    print("字体已保存到 output.ttf")
```

### 使用 httpx 库（异步）

```python
import asyncio
import httpx

async def main():
    async with httpx.AsyncClient() as client:
        # OCR 识别
        with open("handwriting.jpg", "rb") as f:
            resp = await client.post(
                "http://localhost:8000/api/v1/recognize",
                files={"file": ("handwriting.jpg", f, "image/jpeg")},
            )
            result = resp.json()
            print(f"识别到 {result['total']} 个字符")

        # 字体生成
        with open("handwriting.jpg", "rb") as f:
            resp = await client.post(
                "http://localhost:8000/api/v1/generate",
                files={"file": ("handwriting.jpg", f, "image/jpeg")},
                data={"charset": "common_3500"},
            )
            with open("output.ttf", "wb") as out:
                out.write(resp.content)

asyncio.run(main())
```

---

## 错误处理

所有接口在出错时返回 JSON 格式的错误信息：

```json
{
  "detail": "错误描述信息"
}
```

常见 HTTP 状态码：

| 状态码 | 说明 |
|--------|------|
| 200 | 请求成功 |
| 400 | 参数错误（如文件类型不支持、字符集无效） |
| 500 | 服务器内部错误（如 pipeline 初始化失败、生成异常） |

---

## 部署建议

### 生产环境

```bash
# 使用 gunicorn + uvicorn worker
pip install gunicorn
gunicorn writefont.api_server:app -w 4 -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000
```

### Docker

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
EXPOSE 8000
CMD ["python", "start.py", "--api", "--host", "0.0.0.0", "--port", "8000"]
```

### 反向代理（Nginx）

```nginx
server {
    listen 80;
    server_name font.example.com;

    client_max_body_size 20M;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## 与 Web UI 的区别

| 特性 | REST API (`--api`) | Web UI（默认） |
|------|-------------------|---------------|
| 界面 | 无（纯 HTTP 接口） | Gradio 浏览器界面 |
| 适用场景 | 程序集成、自动化 | 人工操作、演示 |
| 端口 | 8000 | 7860 |
| 交互式文档 | /docs (Swagger) | 无 |

---

## 常见问题

**Q: 启动报错 `ModuleNotFoundError: No module named 'writefont_core'`**

A: 核心引擎是私有包，需要单独安装：
```bash
pip install writefont-core
```

**Q: 如何在已有 Web UI 的同时运行 API？**

A: 使用不同端口分别启动：
```bash
# 终端 1：Web UI
python start.py

# 终端 2：API（指定不同端口）
python start.py --api --port 8000
```

**Q: 上传图片大小有限制吗？**

A: 默认无限制，但建议在反向代理中设置 `client_max_body_size`（推荐 20MB）。
