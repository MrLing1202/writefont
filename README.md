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

## 🚀 本地部署

```bash
# 1. 安装 Tesseract OCR
brew install tesseract        # macOS
sudo apt install tesseract-ocr  # Ubuntu

# 2. 克隆项目
git clone https://github.com/MrLing1202/writefont.git
cd writefont
pip install -r requirements.txt

# 3. 启动
python start.py            # Web UI 模式
python start.py --api      # API 模式
```

浏览器打开 `http://localhost:8080` 即可使用。

## ✨ 功能特性

- 📸 **拍照/选图** — 手机拍照或从相册选图，支持多张
- 🔍 **智能识别** — AI 自动检测并分割图片中的字符
- 🎨 **参数调节** — 阈值、腐蚀膨胀、平滑度、对比度可调
- 👀 **实时预览** — 输入任意文字查看字体效果
- 📦 **导出 TTF** — 生成标准 TrueType 字体，全平台通用

## 🛠 使用指南

1. 配置 AI 模型 Key（见下方）
2. 用方格纸写好字符（黑色签字笔，字迹清晰）
3. 打开 App → 拍照或选图 → 调节参数 → 预览 → 导出 TTF

## ⚙️ 技术栈

| 层级 | 技术 |
|------|------|
| 前端 | Flutter 3.x / Dart 3.x |
| 后端 | Python |
| OCR | Tesseract |
| 图像处理 | OpenCV |
| AI 识别 | 支持多模型接入 |
| 字体生成 | 自研 TTF 引擎 |

## 📝 注意事项

- 方格纸网格越清晰，分割越准确
- 拍照保持纸张平整，避免透视变形
- 生成的 TTF 全平台通用

## 📄 License

[AGPL-3.0](LICENSE) — 可以自由使用和修改，但不能闭源商用。

## 🤝 贡献

欢迎提 Issue 和 PR。核心引擎以私有包维护，获取源码请联系作者。

支持自定义 AI 模型接口调用。
