# 手迹造字 WriteFont

拍张手写照片，几分钟生成一套自己的 TTF 字体。

## 📥 下载安装

直接下载 APK 安装到手机，不需要装任何开发工具。

**下载地址：** [GitHub Releases](https://github.com/MrLing1202/writefont/releases/tag/v1.0.0-android)

| 文件名 | 适用设备 |
|--------|----------|
| `app-arm64-v8a-release.apk` | **主流手机选这个**（近 5 年的安卓机基本都是） |
| `app-armeabi-v7a-release.apk` | 老款 32 位手机 |
| `app-x86_64-release.apk` | 安卓模拟器 |

> 下载后打开 → 系统提示"允许安装未知来源"→ 安装完成

## 🤖 配置 AI 模型

App 需要一个 AI 模型来识别手写字。打开 App 后进入「设置」，填入你自己的 API Key 即可。

**支持的模型：**

| 模型 | 免费额度 | 获取地址 |
|------|----------|----------|
| 智谱 AI (GLM-4V-Flash) | ✅ 永久免费 | [open.bigmodel.cn](https://open.bigmodel.cn) |
| MiMo (小米) | 注册赠送 | [mimo.xiaomi.com](https://mimo.xiaomi.com) |
| 硅基流动 | 注册赠送 | [siliconflow.cn](https://siliconflow.cn) |
| Ollama (本地) | ✅ 完全免费 | [ollama.ai](https://ollama.ai) — 需要电脑运行 |

> 💡 推荐先用**智谱 AI**，永久免费，注册就能拿 Key。

**设置步骤：**
1. 去上面的网站注册账号，拿到 API Key
2. 打开 App → 设置 → 选择模型 → 粘贴 Key → 保存
3. 回到首页，开始造字

## 🚀 从源码运行

```bash
git clone https://github.com/MrLing1202/writefont.git
cd writefont
pip install -r requirements.txt
python start.py
```

浏览器打开 `http://localhost:8080` 即可使用。

## ✨ 功能特性

- 📸 **拍照/选图** — 手机拍照或从相册选图，支持多张
- 🔍 **智能识别** — AI 自动检测并分割图片中的字符
- 🎨 **参数调节** — 阈值、腐蚀膨胀、平滑度、对比度可调
- 👀 **实时预览** — 输入任意文字查看字体效果
- 📦 **导出 TTF** — 生成标准 TrueType 字体，Windows/macOS/Linux/手机通用

## 🛠 使用指南

1. 配置 AI 模型 Key（见上方）
2. 用方格纸（田字格/米字格）写好字符，黑色签字笔，字迹清晰
3. 打开 App → 拍照或选图
4. 调节参数（阈值、腐蚀、膨胀、平滑度等）
5. 预览满意后导出 TTF，可分享到微信/QQ/邮件

## ⚙️ 技术栈

| 层级 | 技术 |
|------|------|
| 前端 | Flutter 3.x / Dart 3.x |
| 后端 | Python |
| 图像处理 | OpenCV |
| AI 识别 | 支持智谱/MiMo/OpenAI/Ollama 等多模型 |
| 字体生成 | 自研 TTF 引擎 |

## 📁 项目结构

```
writefont/
├── lib/
│   ├── main.dart                  # App 入口
│   ├── models/                    # 数据模型
│   ├── services/                  # 图像处理、字体生成、存储
│   └── screens/                   # 页面（首页、拍照、调参、预览）
├── src/writefont/
│   ├── api/                       # AI 模型接口（智谱/MiMo/OpenAI...）
│   ├── api_server.py              # REST API 服务端
│   ├── ocr/                       # 文字识别
│   ├── generator/                 # 字体生成
│   └── frontend/                  # Web UI (Gradio)
├── start.py                       # 启动脚本
└── requirements.txt
```

## 📝 注意事项

- 方格纸网格越清晰，分割越准确
- 拍照保持纸张平整，避免透视变形
- 每个字写在格子中央，别出格
- 生成的 TTF 全平台通用
- API Key 只存在你手机/电脑本地，不会上传到任何服务器

## 📄 License

[AGPL-3.0](LICENSE) — 可以自由使用和修改，但不能闭源商用。

## 🤝 贡献

欢迎提 Issue 和 PR。核心引擎以私有包维护，公开仓库只含 UI 层代码，获取引擎源码请联系作者。
