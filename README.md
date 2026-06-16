# 手迹造字 WriteFont iOS

拍照生成手写字体的 Flutter iOS 客户端应用。

## 功能特性

- 📸 **拍照/选图** - 支持相机拍照或从相册选取手写字符图片
- 🔍 **字符识别** - 自动识别图片中的手写字符并分离
- ⚙️ **参数调节** - 调节笔画粗细、平滑度、阈值等参数
- 👀 **字体预览** - 实时预览生成的字体效果
- 📤 **导出分享** - 导出 TTF 字体文件并支持 AirDrop/邮件等方式分享

## 环境要求

- macOS 13.0+
- Xcode 15.0+
- Flutter 3.10+
- CocoaPods 1.15+
- iOS 13.0+ 真机（相机功能需要真机）

## 构建步骤

### 1. 安装 Flutter

```bash
# macOS 使用 Homebrew 安装
brew install flutter

# 或者从官网下载: https://docs.flutter.dev/get-started/install/macos

# 验证安装
flutter doctor
```

### 2. 克隆项目

```bash
git clone <repository-url>
cd writefont-ios
```

### 3. 安装依赖

```bash
flutter pub get
```

### 4. 安装 iOS 依赖

```bash
cd ios
pod install
cd ..
```

### 5. 配置签名

在 Xcode 中打开项目:
```bash
open ios/Runner.xcworkspace
```

在 Xcode 中:
1. 选择 **Runner** 项目
2. 选择 **Runner** target
3. 在 **Signing & Capabilities** 标签页
4. 选择你的 **Team** (Apple Developer 账号)
5. 修改 **Bundle Identifier** 为你的唯一标识符，例如 `com.yourname.writefont`

### 6. 构建 IPA

#### 方式一：命令行构建

```bash
# 构建 Release IPA
flutter build ipa --release

# IPA 文件位置
# build/ios/ipa/writefont.ipa
```

#### 方式二：Xcode 构建

1. 打开 `ios/Runner.xcworkspace`
2. 选择 **Any iOS Device (arm64)** 作为目标设备
3. 菜单栏选择 **Product → Archive**
4. Archive 完成后，在 Organizer 中选择 **Distribute App**
5. 选择分发方式：
   - **Development** - 开发测试
   - **Ad Hoc** - 指定设备测试
   - **App Store Connect** - 上架 App Store
   - **Enterprise** - 企业分发

### 7. 安装到设备

```bash
# 使用 Flutter 直接运行
flutter run --release

# 或者使用 ios-deploy
ios-deploy --bundle build/ios/iphoneos/Runner.app

# 或者使用 Xcode 安装 IPA
# 在 Xcode → Window → Devices and Simulators 中拖入 IPA 文件
```

## 项目结构

```
writefont-ios/
├── lib/
│   ├── main.dart                    # 应用入口
│   ├── models/
│   │   └── font_project.dart        # 字体项目数据模型
│   ├── screens/
│   │   ├── home_screen.dart         # 主页 Tab 导航
│   │   ├── capture_screen.dart      # 拍照/选图界面
│   │   ├── glyph_editor_screen.dart # 字形编辑界面
│   │   └── font_preview_screen.dart # 字体预览与导出
│   ├── services/
│   │   ├── image_processor.dart     # 图像处理服务
│   │   └── ttf_builder.dart         # TTF 字体生成器
│   └── widgets/
│       └── glyph_tile.dart          # 字形缩略图组件
├── ios/
│   └── Runner/
│       └── Info.plist               # iOS 配置（权限声明）
├── pubspec.yaml                     # 项目配置
└── README.md
```

## 使用流程

1. **拍摄/选取** - 使用相机拍摄手写字符照片，或从相册选取
2. **识别字符** - 应用自动识别图片中的字符
3. **编辑调整** - 对每个字符调整阈值、平滑度等参数
4. **预览字体** - 输入自定义文本预览字体效果
5. **导出分享** - 导出 TTF 文件并通过 AirDrop、邮件等方式分享

## 常见问题

### Q: 相机权限被拒绝怎么办？
A: 前往 **设置 → 隐私与安全 → 相机**，找到 WriteFont 并开启权限。

### Q: 构建时 CocoaPods 报错？
A: 尝试以下步骤：
```bash
cd ios
pod deintegrate
pod install
cd ..
flutter clean
flutter pub get
```

### Q: 如何在模拟器上测试？
A: 相机功能需要真机，模拟器只能使用相册功能。

## 许可证

MIT License
