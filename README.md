# 手迹造字 WriteFont 桌面客户端

> 📝 拍照生成手写字体 — 支持 macOS、Windows、Linux

基于 [Tauri](https://tauri.app/) 构建的桌面客户端，调用 Python 核心引擎进行字体生成。

## 功能特性

- 🖼️ **拖拽上传** — 拖拽或点击上传手写汉字图片
- ⚙️ **参数调节** — 笔画粗细、墨迹浓度、平滑度、字间距、基线偏移
- 👁️ **实时预览** — 多尺寸、多文本实时预览字体效果
- 📦 **导出 TTF** — 一键导出标准 TrueType 字体文件
- 🎨 **水墨风格** — 精美的宣纸水墨 UI 主题
- 🖥️ **跨平台** — 支持 macOS (.app)、Windows (.exe)、Linux

## 技术栈

| 层级 | 技术 |
|------|------|
| 前端 | React 18 + TypeScript + Vite + Tailwind CSS |
| 后端 | Rust (Tauri 1.5) |
| 引擎 | Python 3 (Pillow, fonttools) |
| 样式 | Framer Motion + Lucide Icons |

## 快速开始

### 环境要求

- **Node.js** >= 18
- **Rust** >= 1.70 (安装: https://rustup.rs)
- **Python** >= 3.8
- **系统依赖** (macOS): Xcode Command Line Tools
- **系统依赖** (Linux): `sudo apt install libwebkit2gtk-4.0-dev build-essential libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev`

### 安装依赖

```bash
# 1. 安装前端依赖
npm install

# 2. 安装 Python 依赖
pip install Pillow fonttools

# 3. Cargo 依赖会自动安装
```

### 开发模式

```bash
# 启动开发服务器（带热重载）
npm run tauri:dev
```

### 构建发布版

```bash
npm run tauri:build
```

构建产物位置：

| 平台 | 输出路径 |
|------|---------|
| macOS | `src-tauri/target/release/bundle/dmg/WriteFont_1.0.0_aarch64.dmg` |
| macOS (app) | `src-tauri/target/release/bundle/macos/WriteFont.app` |
| Windows | `src-tauri/target/release/bundle/msi/WriteFont_1.0.0_x64_en-US.msi` |
| Windows (exe) | `src-tauri/target/release/bundle/nsis/WriteFont_1.0.0_x64-setup.exe` |
| Linux (deb) | `src-tauri/target/release/bundle/deb/writefont-desktop_1.0.0_amd64.deb` |
| Linux (AppImage) | `src-tauri/target/release/bundle/appimage/writefont-desktop_1.0.0_amd64.AppImage` |

## 构建指南

### macOS 构建 .app

```bash
# 确保已安装 Xcode Command Line Tools
xcode-select --install

# 安装 Rust 目标（Apple Silicon）
rustup target add aarch64-apple-darwin

# 构建
npm run tauri:build

# 输出: src-tauri/target/release/bundle/macos/WriteFont.app
# DMG:  src-tauri/target/release/bundle/dmg/WriteFont_*.dmg
```

**代码签名（可选）：**

```bash
# 设置环境变量
export APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_CERTIFICATE="path/to/certificate.p12"
export APPLE_CERTIFICATE_PASSWORD="password"

npm run tauri:build
```

### Windows 构建 .exe

```bash
# 前置条件:
# 1. 安装 Visual Studio Build Tools (C++ 工作负载)
# 2. 安装 WebView2 (Windows 10+ 通常已预装)
# 3. 安装 Rust: rustup-init.exe

# 构建
npm run tauri:build

# 输出:
# MSI:  src-tauri/target/release/bundle/msi/WriteFont_*.msi
# EXE:  src-tauri/target/release/bundle/nsis/WriteFont_*-setup.exe
```

**交叉编译（macOS → Windows）：**

```bash
# 安装 Windows 目标
rustup target add x86_64-pc-windows-msvc

# 需要 Windows SDK 和交叉编译工具链
# 推荐在 GitHub Actions 或 Windows 虚拟机中构建
```

### Linux 构建

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y \
  libwebkit2gtk-4.0-dev \
  build-essential \
  libgtk-3-dev \
  libayatana-appindicator3-dev \
  librsvg2-dev

npm run tauri:build

# 输出:
# .deb:       src-tauri/target/release/bundle/deb/*.deb
# AppImage:   src-tauri/target/release/bundle/appimage/*.AppImage
```

## Python 引擎集成

桌面客户端通过 Tauri 的 Command 机制调用本地 Python 引擎：

1. **开发模式**：直接调用项目根目录的 `src/writefont/` Python 模块
2. **发布模式**：使用打包后的 Python 脚本或 sidecar

### Python 依赖

```bash
pip install Pillow fonttools numpy
```

### 引擎接口

```python
# src/writefont/core.py
def process_character(image_data, char, stroke_width, smoothness, ink_density):
    """处理单个字符图片"""
    pass

# src/writefont/font_generator.py
def generate_ttf(characters, params, font_name, author, output_dir):
    """生成 TTF 字体文件"""
    pass
```

## 项目结构

```
writefont-desktop/
├── src/                    # React 前端源码
│   ├── components/         # UI 组件
│   │   ├── TitleBar.tsx    # 自定义标题栏
│   │   ├── StepIndicator.tsx # 步骤指示器
│   │   ├── UploadPanel.tsx # 上传面板
│   │   ├── AdjustPanel.tsx # 参数调整面板
│   │   ├── PreviewPanel.tsx # 预览面板
│   │   └── ExportPanel.tsx # 导出面板
│   ├── hooks/              # 自定义 Hooks
│   │   ├── useWriteFont.ts # 字体生成 API
│   │   └── useAppState.ts  # 应用状态管理
│   ├── types/              # TypeScript 类型
│   ├── styles/             # 全局样式
│   ├── App.tsx             # 根组件
│   └── main.tsx            # 入口文件
├── src-tauri/              # Tauri 后端 (Rust)
│   ├── src/
│   │   └── main.rs         # Rust 主程序
│   ├── Cargo.toml          # Rust 依赖
│   ├── tauri.conf.json     # Tauri 配置
│   └── icons/              # 应用图标
├── package.json
├── vite.config.ts
├── tailwind.config.js
└── README.md
```

## UI 主题

采用中国传统水墨风格设计：

- **宣纸底色** `#fdf9f3` — 模拟宣纸质感
- **墨色系** `#2e211c` ~ `#a88666` — 从浓墨到淡墨
- **米字格背景** — 书法练习格辅助线
- **毛笔字体** — 使用马善政毛笔行书
- **印章元素** — 红色篆刻风格装饰

## 常见问题

### Python 找不到？

```bash
# 检查 Python 路径
which python3

# 确保在 PATH 中
echo $PATH

# 或在 tauri.conf.json 中配置绝对路径
```

### 构建失败？

```bash
# 清理缓存
rm -rf src-tauri/target
rm -rf node_modules
npm install
npm run tauri:build
```

### Windows 上 WebView2 缺失？

Windows 10 1803+ 通常已预装。如果缺失，从 [Microsoft](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) 下载安装。

## License

MIT License

## 致谢

- [Tauri](https://tauri.app/) — 跨平台桌面框架
- [手迹造字](https://github.com/MrLing1202/writefont) — Python 核心引擎
- [Tailwind CSS](https://tailwindcss.com/) — UI 样式框架
