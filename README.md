# 手迹造字 WriteFont

从手写样本到可安装字体，全链路自动化。

## 📥 下载安装

**下载地址：** [GitHub Releases](https://github.com/MrLing1202/writefont/releases/tag/v1.0.0-android)

| 文件名 | 适用设备 |
|--------|----------|
| `app-arm64-v8a-release.apk` | **主流手机选这个** |
| `app-armeabi-v7a-release.apk` | 老款 32 位手机 |
| `app-x86_64-release.apk` | 安卓模拟器 |

> 下载 → 允许安装未知来源 → 完成

## 🚀 本地部署

```bash
git clone https://github.com/MrLing1202/writefont.git
cd writefont
pip install -r requirements.txt
python start.py
```

## ✨ 核心能力

- **端到端字体生成** — 拍照到 TTF 一条龙，无需人工描字
- **多模型 AI 识别** — 接入主流视觉语言模型，识别精度自适应
- **智能字符分割** — 自动检测、分离、校正手写字符
- **参数自适应引擎** — 阈值/腐蚀/膨胀/平滑度实时可调，所见即所得
- **跨平台字体输出** — 生成标准 TrueType 字体，Windows/macOS/Linux/Android/iOS 通用

## 🛠 使用流程

1. 配置 AI 模型（见下方）
2. 方格纸手写字符 → 拍照
3. 调参 → 预览 → 导出

## ⚙️ 技术架构

```
┌─────────────┐    ┌──────────────┐    ┌──────────────┐
│  Flutter App │───▶│  Python 后端  │───▶│  AI 模型 API  │
│  (前端交互)   │    │  (图像处理)   │    │  (视觉识别)   │
└─────────────┘    └──────┬───────┘    └──────────────┘
                          │
                   ┌──────▼───────┐
                   │  字体生成引擎  │
                   │  (TTF 输出)   │
                   └──────────────┘
```

## 📝 注意事项

- 方格纸网格越清晰，识别越准
- 拍照保持纸张平整
- 生成的 TTF 全平台通用

## 📄 License

[AGPL-3.0](LICENSE) — 可自由使用和修改，禁止闭源商用。

## 🤝 贡献

欢迎提 Issue 和 PR。核心引擎不开源，获取源码请联系作者。

支持自定义 AI 模型接口调用。
