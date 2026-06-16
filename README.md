# 🖌️ 手迹造字 WriteFont

<p align="center">
  <strong>拍一张手写照片，生成你的专属字体</strong><br>
  个人手写字体生成器 · 全平台支持 · 一键生成 TTF
</p>

<p align="center">
  <a href="#功能特性">功能特性</a> •
  <a href="#快速开始">快速开始</a> •
  <a href="#使用指南">使用指南</a> •
  <a href="#开发计划">开发计划</a> •
  <a href="#参与贡献">参与贡献</a>
</p>

---

## 📖 这是什么？

手迹造字（WriteFont）让你**用自己的笔迹创建专属字体**。

在纸上写几十个字 → 拍照上传 → 自动识别、提取风格、生成字体文件 → 安装到电脑/手机。

从此你的文档、PPT、设计稿都可以用**你自己的手写字体**。

> 🎯 不需要设计基础，不需要专业知识，拍张照就行。

## ✨ 功能特性

### 📸 拍照即生成
- 手机拍照或上传图片，自动识别手写汉字
- 支持 6,763 个常用汉字 + 英文字母 + 数字
- 自动矫正倾斜、去噪、增强对比度

### 🎨 个性化定制
- 笔画粗细、墨迹浓淡可调
- 多种风格预设：钢笔、毛笔、铅笔、马克笔
- 适配白纸、方格纸、横线纸等不同纸张

### 📦 标准字体输出
- 生成标准 TTF / OpenType 字体文件
- 自动预览效果，满意再导出
- Windows / macOS / Linux / 手机 全平台可用

### 🖥️ 多端使用
- **网页版**：浏览器直接用，无需安装
- **桌面版**：macOS / Windows / Linux 原生应用
- **手机版**：Android / iOS，手机拍照直接生成

## 🚀 快速开始

```bash
# 1. 克隆项目
git clone https://github.com/MrLing1202/writefont.git
cd writefont

# 2. 安装核心引擎（私有包，需要 GitHub 访问权限）
pip install git+https://github.com/MrLing1202/writefont-core.git

# 3. 安装 UI 依赖
pip install -r requirements.txt

# 4. 一键启动
python start.py
```

浏览器自动打开 `http://localhost:7860`，上传手写照片即可开始。

> 💡 首次启动会自动检测环境并安装所需组件，无需手动配置。
> ⚠️ `writefont-core` 是私有仓库，安装需要 GitHub 访问权限。

## 📁 项目结构

```
writefont/          ← 本仓库（公开，MIT）
├── src/writefont/
│   ├── __main__.py     # CLI 入口
│   ├── api/            # API 配置与 Provider 管理
│   └── frontend/       # Gradio Web 前端
├── configs/            # 默认配置文件
└── tests/

writefont-core/     ← 私有仓库（核心引擎）
├── src/writefont_core/
│   ├── pipeline.py     # 主流程管道
│   ├── ocr/            # OCR 识别与预处理
│   ├── style/          # 风格提取与迁移
│   ├── generator/      # 扩散模型与渲染器
│   ├── font/           # 字体打包与矢量化
│   └── utils/          # 通用工具
```

## 📚 使用指南

### 五步生成你的专属字体

| 步骤 | 操作 | 说明 |
|:----:|------|------|
| ① | 准备纸笔 | 白纸 + 黑色中性笔（0.5mm 最佳） |
| ② | 书写汉字 | 建议写 20-100 个常用字，每字约 1.5cm |
| ③ | 拍照上传 | 自然光、平整纸张、俯拍 |
| ④ | 调整参数 | 预览效果，调节粗细和风格 |
| ⑤ | 导出安装 | 下载 TTF 文件，双击安装即可使用 |

### 💡 最佳实践

- 手写越清晰，生成效果越好
- 建议包含你的**签名**，让字体更有个人特色
- 光线均匀、避免阴影和反光
- 每张纸不要写太满，留出间距

## 🗺️ 开发计划

- [x] 核心字体生成引擎
- [x] Web 应用（浏览器端）
- [x] 多 AI 模型支持
- [ ] 批量生成与字库扩充
- [ ] 桌面原生应用
- [ ] Android / iOS 手机应用
- [ ] 字体在线预览与编辑
- [ ] 社区字体分享

## 🤝 参与贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建功能分支：`git checkout -b feature/your-feature`
3. 提交更改并推送
4. 提交 Pull Request

## 📄 开源协议

本项目 UI 层基于 **[MIT](LICENSE)** 开源。

核心引擎 (`writefont-core`) 为私有组件，采用独立许可协议。

> 如果你需要商业授权或核心引擎访问，请联系作者。

---

<p align="center">
  ⭐ 觉得有用？给个 Star 支持一下！
</p>
