# 🖌️ 手迹造字 WriteFont

<p align="center">
  <strong>基于深度学习的个人手写字体生成器</strong><br>
  拍一张手写样本，即可生成专属 TTF/OpenType 字体
</p>

<p align="center">
  <a href="#功能特性">功能特性</a> •
  <a href="#快速开始">快速开始</a> •
  <a href="#技术架构">技术架构</a> •
  <a href="#安装部署">安装部署</a> •
  <a href="#使用指南">使用指南</a> •
  <a href="#开发计划">开发计划</a> •
  <a href="#参与贡献">参与贡献</a>
</p>

---

## 📖 项目简介

手迹造字（WriteFont）是一款开源的个人字体生成工具。只需提供一张手写汉字的照片，系统会自动识别字符、提取笔迹风格，并生成可用于设计、排版的 TTF/OpenType 字体文件。

**核心理念**：让每个人都能拥有独一无二的手写字体，无需专业知识，零门槛上手。

## ✨ 功能特性

### 🔤 智能字符识别
- 基于 Tesseract OCR 引擎的汉字识别
- 支持 6,763 个常用汉字 + 26 个英文字母 + 10 个数字
- 自动矫正倾斜、去噪、二值化等预处理
- 双引擎校验，确保识别准确率 ≥ 95%

### 🎨 个性化风格生成
- **笔画粗细**：细笔、中笔、粗笔三档可调
- **墨迹风格**：钢笔、毛笔、铅笔、马克笔仿真
- **纸张适配**：白纸、方格纸、横线纸自动检测
- **风格迁移**：基于 ReNe 书法风格迁移算法

### 📦 字体文件输出
- 生成标准 TTF / OpenType 字体文件
- 自动生成字体预览图（PNG）
- 支持 GB2312 / Unicode 编码
- 可直接安装到 Windows / macOS / Linux

### 🖥️ 多平台支持
- **Web App**（main 分支）：Gradio 界面，浏览器即开即用
- **桌面应用**（desktop 分支）：Tauri 原生应用，支持 macOS / Windows / Linux
- **Android App**（android 分支）：Flutter 应用，手机拍照直接生成
- **iOS App**（ios 分支）：Flutter 应用，iPhone / iPad 适配

## 🚀 快速开始

### 环境要求

| 依赖 | 版本 | 说明 |
|------|------|------|
| Python | ≥ 3.9 | 主运行环境 |
| Tesseract | ≥ 5.0 | OCR 引擎 |
| Gradio | ≥ 4.0 | Web UI 框架 |
| OpenCV | ≥ 4.5 | 图像处理 |

### 三步上手

```bash
# 1. 克隆项目
git clone https://github.com/MrLing1202/writefont.git
cd writefont

# 2. 安装依赖
pip install -r requirements.txt

# 3. 启动应用
python frontend/app.py
```

打开浏览器访问 `http://localhost:7860`，上传手写照片，即可生成字体。

## 🏗️ 技术架构

```
┌──────────────────────────────────────────────────┐
│                 用户界面层                          │
│  Gradio Web UI │ Tauri Desktop │ Flutter Mobile   │
└──────────────┬───────────────────────────────────┘
               │
┌──────────────▼───────────────────────────────────┐
│                 核心引擎层                          │
│  ┌─────────┐  ┌──────────┐  ┌───────────────┐    │
│  │ OCR     │  │ 风格     │  │ 字体          │    │
│  │ 识别引擎 │→│ 提取引擎  │→│ 生成引擎      │    │
│  └─────────┘  └──────────┘  └───────────────┘    │
│       Tesseract    ReNE        fontTools/TTF     │
└──────────────┬───────────────────────────────────┘
               │
┌──────────────▼───────────────────────────────────┐
│                 AI 模型层                          │
│  本地模式（Ollama）│ API 模式 │ 混合模式            │
│  DeepSeek/Qwen   │ 智谱AI   │ 本地+API           │
└──────────────────────────────────────────────────┘
```

### 核心模块

| 模块 | 文件 | 说明 |
|------|------|------|
| OCR 识别 | `engine/recognizer.py` | Tesseract + 预处理管线 |
| 风格提取 | `engine/style_extractor.py` | 笔迹特征分析与迁移 |
| 字体生成 | `engine/font_generator.py` | TTF 文件组装与编码 |
| 图像处理 | `engine/image_processor.py` | 矫正、去噪、二值化 |
| 配置管理 | `api/config.py` | API 密钥与运行配置 |
| 模型接口 | `api/providers.py` | 多模型 Provider 管理 |
| Web 界面 | `frontend/app.py` | 水墨风格 Gradio UI |

## 📋 安装部署

### 方式一：本地快速部署（推荐）

```bash
# macOS
brew install tesseract
pip install -r requirements.txt
python frontend/app.py

# Ubuntu/Debian
sudo apt install tesseract-ocr
pip install -r requirements.txt
python frontend/app.py
```

### 方式二：API 模式（免费）

无需本地 GPU，使用免费云端 AI：

1. 注册 [智谱AI](https://open.bigmodel.cn/) 获取 API Key（GLM-4V-Flash 永久免费）
2. 在应用设置中填入 API Key
3. 选择「API 模式」运行

### 方式三：桌面应用（开发中）

```bash
cd desktop/
npm install
npm run tauri dev
```

## 📚 使用指南

### 基础流程

1. **准备手写样本**：在白纸上用黑色笔书写汉字（建议 20+ 字）
2. **拍照上传**：光线均匀，避免阴影和反光
3. **字符识别**：系统自动识别并标注每个字符
4. **调整参数**：选择笔迹粗细、墨迹风格
5. **生成字体**：下载 TTF 文件，双击安装即可使用

### 最佳实践

- 📝 手写样本建议包含：常用 100 字 + 你的签名
- 📸 拍照建议：自然光、平整纸张、45° 角俯拍
- ✏️ 笔迹建议：使用 0.5mm 黑色中性笔，书写清晰
- 📐 纸张建议：A4 白纸，每字约 1.5cm × 1.5cm

## 🗺️ 开发计划

- [x] 核心字体生成管线
- [x] Gradio Web UI
- [x] 多 AI 模型支持（本地/API/混合）
- [ ] 批量生成与字库扩充
- [ ] Tauri 桌面应用（macOS / Windows / Linux）
- [ ] Flutter 移动端（Android / iOS）
- [ ] 在线预览与字体编辑器
- [ ] 字体质量评估与优化
- [ ] 社区字体分享平台

## 🤝 参与贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建功能分支：`git checkout -b feature/amazing-feature`
3. 提交更改：`git commit -m 'feat: add amazing feature'`
4. 推送分支：`git push origin feature/amazing-feature`
5. 提交 Pull Request

### 分支规范

| 分支 | 用途 | 状态 |
|------|------|------|
| `main` | Web App 主线 | ✅ 稳定 |
| `desktop` | Tauri 桌面应用 | 🔨 开发中 |
| `android` | Flutter Android | 📋 计划中 |
| `ios` | Flutter iOS | 📋 计划中 |

## 📄 开源协议

本项目基于 [MIT License](LICENSE) 开源。

## 🙏 致谢

- [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) — 开源 OCR 引擎
- [fontTools](https://github.com/fonttools/fonttools) — 字体文件处理库
- [Gradio](https://github.com/gradio-app/gradio) — ML 应用 UI 框架
- [Tauri](https://github.com/tauri-apps/tauri) — 跨平台桌面应用框架
- [Flutter](https://flutter.dev/) — 跨平台移动应用框架
- [ReNe](https://arxiv.org/abs/2303.13443) — 书法风格迁移算法

---

<p align="center">
  如果觉得有用，请给个 ⭐ Star 支持一下！
</p>
