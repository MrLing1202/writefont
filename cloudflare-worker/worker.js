/**
 * WriteFont OCR Proxy Worker
 *
 * 代理 SiliconFlow DeepSeek-OCR API，前端只需发 base64 图片即可识别。
 * - 限频：每 IP 每天 100 次
 * - CORS：允许所有来源
 * - API Key 通过环境变量 SF_API_KEY 注入
 */

// 每 IP 每天请求计数（内存 Map，Worker 重启会重置，够用）
const rateLimitMap = new Map();
const RATE_LIMIT = 100;

function getClientIP(request) {
  return request.headers.get('cf-connecting-ip') || request.headers.get('x-forwarded-for') || 'unknown';
}

function checkRateLimit(ip) {
  const now = new Date();
  const dayKey = `${ip}:${now.getUTCFullYear()}-${now.getUTCMonth() + 1}-${now.getUTCDate()}`;
  const count = rateLimitMap.get(dayKey) || 0;
  if (count >= RATE_LIMIT) {
    return false;
  }
  rateLimitMap.set(dayKey, count + 1);
  return true;
}

// 定期清理过期记录（每次请求有小概率触发清理）
function cleanupExpiredEntries() {
  if (rateLimitMap.size < 10000) return;
  const now = new Date();
  const todayPrefix = `${now.getUTCFullYear()}-${now.getUTCMonth() + 1}-${now.getUTCDate()}`;
  for (const key of rateLimitMap.keys()) {
    if (!key.endsWith(todayPrefix)) {
      rateLimitMap.delete(key);
    }
  }
}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

export default {
  async fetch(request, env) {
    // CORS 预检
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    // 只接受 POST
    if (request.method !== 'POST') {
      return jsonResponse({ error: 'Method not allowed, use POST' }, 405);
    }

    // 限频检查
    const clientIP = getClientIP(request);
    if (!checkRateLimit(clientIP)) {
      return jsonResponse({ error: '请求频率超限，每天最多 100 次' }, 429);
    }

    // 偶尔清理过期记录
    cleanupExpiredEntries();

    // 解析请求体
    let body;
    try {
      body = await request.json();
    } catch {
      return jsonResponse({ error: '请求体不是合法 JSON' }, 400);
    }

    const image = body.image;
    if (!image || typeof image !== 'string') {
      return jsonResponse({ error: '缺少 image 字段（base64 字符串）' }, 400);
    }

    // 转发到 SiliconFlow DeepSeek-OCR
    const apiKey = env.SF_API_KEY;
    if (!apiKey) {
      return jsonResponse({ error: '服务端未配置 API Key' }, 500);
    }

    try {
      const upstreamResponse = await fetch('https://api.siliconflow.cn/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'deepseek-ai/DeepSeek-OCR',
          messages: [
            {
              role: 'user',
              content: [
                {
                  type: 'image_url',
                  image_url: { url: `data:image/png;base64,${image}` },
                },
                {
                  type: 'text',
                  text: 'Free OCR.',
                },
              ],
            },
          ],
          max_tokens: 1024,
        }),
      });

      if (!upstreamResponse.ok) {
        const errorText = await upstreamResponse.text();
        return jsonResponse(
          { error: `上游 API 返回 ${upstreamResponse.status}: ${errorText}` },
          upstreamResponse.status
        );
      }

      const data = await upstreamResponse.json();

      // 从 OpenAI 格式中提取文本
      const text = data?.choices?.[0]?.message?.content || '';
      return jsonResponse({ text });
    } catch (e) {
      return jsonResponse({ error: `请求上游失败: ${e.message}` }, 502);
    }
  },
};
