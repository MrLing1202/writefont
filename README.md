# 手迹造字 WriteFont

> 📱 Flutter Android 客户端 — 拍照生成手写字体的工具

## ✨ 功能特性

- 📸 **拍照/选图** - 支持手机拍照或从相册选择手写字符图片
- 🔍 **智能识别** - 自动检测和分割图片中的字符
- 🎨 **参数调节** - 阈值、腐蚀膨胀、平滑度、对比度等精细调节
- 👀 **字体预览** - 实时预览生成的字体效果，支持自定义文字
- 📦 **导出 TTF** - 生成标准 TrueType 字体文件，可直接安装使用

## 📋 环境要求

- **Flutter SDK**: 3.10.0 或更高版本
- **Dart SDK**: 3.0.0 或更高版本
- **Android SDK**: API 21+ (Android 5.0+)
- **JDK**: 11 或更高版本

## 🚀 快速开始

### 1. 安装 Flutter

```bash
# macOS (使用 Homebrew)
brew install flutter

# 或者参考官方文档
# https://flutter.dev/docs/get-started/install
```

验证安装：
```bash
flutter doctor
```

### 2. 克隆项目

```bash
git clone <your-repo-url>
cd writefont
```

### 3. 安装依赖

```bash
flutter pub get
```

### 4. 运行调试版

```bash
# 连接 Android 设备或启动模拟器后运行
flutter run
```

### 5. 构建 APK

```bash
# 构建 Debug APK
flutter build apk --debug

# 构建 Release APK（推荐）
flutter build apk --release

# 构建拆分 APK（按 ABI 拆分，文件更小）
flutter build apk --split-per-abi
```

构建完成后，APK 文件位于：
```
build/app/outputs/flutter-apk/
├── app-debug.apk          # Debug 版本
├── app-release.apk        # Release 版本
├── app-arm64-v8a-release.apk   # ARM64 专用
├── app armeabi-v7a-release.apk # ARM 32位专用
└── app-x86_64-release.apk      # x86_64 专用
```

### 6. 安装到手机

```bash
# 直接安装到已连接的设备
flutter install

# 或者使用 adb
adb install build/app/outputs/flutter-apk/app-release.apk
```

## 📁 项目结构

```
writefont/
├── lib/
│   ├── main.dart                    # 应用入口
│   ├── models/
│   │   └── project.dart             # 数据模型（字体项目、字形、参数）
│   ├── services/
│   │   ├── image_processor.dart     # 图像处理服务
│   │   ├── ttf_builder.dart         # TTF 字体生成器
│   │   └── storage_service.dart     # 文件存储服务
│   └── screens/
│       ├── home_screen.dart         # 首页
│       ├── capture_screen.dart      # 拍照/选图页
│       ├── processing_screen.dart   # 参数调节页
│       └── preview_screen.dart      # 预览与导出页
├── pubspec.yaml                     # 项目配置
├── analysis_options.yaml            # 代码分析配置
└── README.md                        # 项目说明
```

## 🛠 使用指南

### 步骤 1：准备手写字符

1. 使用方格纸（田字格/米字格）书写字符
2. 每个格子写一个字符，保持间距
3. 建议使用黑色签字笔，字迹清晰

### 步骤 2：拍照或选图

1. 点击「开始造字」按钮
2. 选择「拍照」直接拍摄手写纸，或「相册选图」选择已有图片
3. 可以选择多张图片

### 步骤 3：调节参数

1. **阈值**：控制黑白分界线，值越小检测越宽松
2. **腐蚀**：减小笔画粗细，去除噪点
3. **膨胀**：增加笔画粗细，填补空隙
4. **平滑度**：平滑边缘锯齿
5. **对比度**：增强黑白对比
6. **反转颜色**：适用于白底黑字/黑底白字切换

### 步骤 4：预览字体

1. 在预览页面输入任意文字查看效果
2. 支持大中小三种字号预览
3. 可查看已收录的所有字符

### 步骤 5：导出字体

1. 点击「导出 TTF」按钮
2. 字体文件保存到应用目录
3. 可通过分享功能发送到其他应用

## ⚙️ 技术栈

| 技术 | 版本 | 用途 |
|------|------|------|
| Flutter | 3.x | UI 框架 |
| Dart | 3.x | 编程语言 |
| image_picker | ^1.0.7 | 拍照/选图 |
| image | ^4.1.7 | 图像处理 |
| path_provider | ^2.1.2 | 文件路径 |
| share_plus | ^7.2.2 | 文件分享 |
| permission_handler | ^11.3.0 | 权限管理 |

## 🔧 TTF 字体生成原理

本应用在纯 Dart 中实现了完整的 TrueType 字体文件生成：

1. **图像二值化** - 将灰度图像转换为黑白二值图
2. **形态学处理** - 腐蚀/膨胀操作清理噪点
3. **连通域分析** - 提取每个字符的边界点
4. **轮廓简化** - Ramer-Douglas-Peucker 算法简化轮廓
5. **TTF 编码** - 生成完整的 TrueType 文件，包含所有必需表：
   - `head` - 字体头信息
   - `cmap` - 字符映射表
   - `glyf` - 字形轮廓数据
   - `hhea` / `hmtx` - 水平度量
   - `loca` - 字形位置索引
   - `maxp` - 最大配置
   - `name` - 命名表
   - `OS/2` - 系统兼容性
   - `post` - PostScript 信息

## 📝 注意事项

1. 建议使用方格纸书写，网格越清晰，字符分割越准确
2. 拍照时保持纸张平整，避免透视变形
3. 每个字符应写在格子中央，不要超出格子边界
4. 生成的 TTF 文件可以在 Windows、macOS、Linux、Android、iOS 上使用

## 📄 License

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 🔗 相关链接

- [Flutter 官方文档](https://flutter.dev/docs)
- [TrueType 字体规范](https://developer.apple.com/fonts/TrueType-Reference-Manual/)
- [Material Design 3](https://m3.material.io/)

## 🔧 开发者说明

本项目的核心引擎以私有包形式维护。如需获取核心引擎源码进行开发，请联系作者。

**公开仓库仅包含 UI 层代码。** 核心引擎（字体生成、OCR识别、风格迁移）由独立的私有包提供。
