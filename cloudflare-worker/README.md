# WriteFont OCR Proxy

Cloudflare Worker 代理服务，将 OCR 请求转发到 SiliconFlow DeepSeek-OCR API。

前端只需发送 `{ "image": "base64字符串" }`，无需 API Key。

## 部署

```bash
npm install -g wrangler
wrangler login
wrangler deploy
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `SF_API_KEY` | SiliconFlow API Key，已在 `wrangler.toml` 中配置 |

## API

**请求**

```
POST https://writefont-ocr.workers.dev
Content-Type: application/json

{
  "image": "base64编码的图片"
}
```

**成功响应**

```json
{ "text": "识别到的文字" }
```

**错误响应**

```json
{ "error": "错误信息" }
```

## 限频

每 IP 每天 100 次请求（内存计数，Worker 重启会重置）。
