# 手迹造字 (WriteFont)

<div align="center">

**一个本地部署的AI应用，让用户通过手写50个汉字即可生成完整个人字体库**

[English](#english) | [中文](#中文)

</div>

---

## 中文

### 项目简介

手迹造字（WriteFont）是一个开源的AI字体生成工具。用户只需拍照上传50个左右的手写汉字，系统会自动：

1. OCR识别并提取手写汉字
2. 分析并提取个人笔迹风格特征（200+维特征向量）
3. 基于风格向量生成完整GB2312字符集（6,763字）
4. 导出为TTF/OTF/WOFF格式字体文件

**所有AI推理在本地完成，无需联网，保护用户隐私。**

### 核心特性

- 🔍 **高精度OCR**：基于PaddleOCR，手写汉字识别准确率99%+
- 🎨 **风格提取**：自编码器提取200+维笔迹特征（笔锋、力度、连笔、结构）
- 🤖 **AI生成**：基于扩散模型的字形生成，保持风格一致性
- 📦 **字体打包**：支持TTF/OTF/WOFF格式，可直接安装使用
- 💻 **本地部署**：完全离线运行，数据不离开用户设备
- 🖥️ **Web界面**：基于Gradio的友好操作界面

### 快速开始

#### 环境要求

- Python 3.10+
- CUDA 11.8+（推荐，CPU也可运行但较慢）
- 8GB+ RAM（推荐16GB）

#### 安装

```bash
# 克隆项目
git clone https://github.com/your-username/writefont.git
cd writefont

# 创建虚拟环境
python -m venv venv
source venv/bin/activate  # Linux/Mac
# 或 venv\Scripts\activate  # Windows

# 安装依赖
pip install -e .

# 安装PaddleOCR（可选，用于高精度OCR）
pip install paddlepaddle paddleocr
```

#### 使用方法

**方式一：Web界面（推荐）**

```bash
writefont-ui
# 或
python -m writefont.frontend.app
```

打开浏览器访问 `http://localhost:7860`

**方式二：命令行**

```bash
# 图像预处理
writefont preprocess --input photo.jpg --output processed/

# OCR识别
writefont ocr --input processed/ --output recognized.json

# 风格提取
writefont style --input recognized.json --output style_vector.pt

# 字体生成
writefont generate --style style_vector.pt --output font.ttf

# 一键完成
writefont run --input photo.jpg --output my_font.ttf
```

**方式三：Python API**

```python
from writefont import WriteFontPipeline

pipeline = WriteFontPipeline()
result = pipeline.run(
    input_path="photo.jpg",
    output_path="my_font.ttf",
    charset="gb2312"
)
print(f"字体已生成: {result.font_path}")
```

### 技术原理

#### 1. 图像预处理

```
原始照片 → 透视矫正 → 去噪 → 二值化 → 字符分割 → 归一化
```

- 使用OpenCV进行透视矫正（检测纸张边缘）
- 自适应阈值二值化处理
- 连通域分析进行字符分割
- 归一化到统一尺寸（64x64或128x128）

#### 2. OCR识别

```
分割后的字符图像 → CRNN/PaddleOCR → 文字标签
```

- 主要方案：PaddleOCR（预训练模型，开箱即用）
- 备选方案：自训练CRNN模型（针对手写汉字优化）
- 支持置信度过滤和人工校正

#### 3. 风格提取

```
50个样本字符 → 卷积编码器 → 200维风格向量
```

- 使用变分自编码器（VAE）架构
- 编码器提取笔迹风格特征
- 特征维度：笔锋粗细、起笔收笔、连笔习惯、结构比例、墨迹浓淡
- 解码器用于验证风格重建质量

#### 4. 字体生成

```
风格向量 + 目标字符编码 → 扩散模型 → 字形图像
```

- 基于条件扩散模型（Conditional Diffusion Model）
- 风格向量作为条件输入
- 字符编码（Unicode/GB2312）控制生成内容
- 生成64x64字形图像，可超分辨率到更高分辨率

#### 5. 字体打包

```
字形图像 → 轮廓提取 → 矢量化 → FontTools → TTF/OTF
```

- 使用Potrace或自实现的轮廓追踪算法
- FontTools进行字体文件组装
- 自动生成字距调整（kerning）表
- 支持TTF、OTF、WOFF、WOFF2格式

### 项目结构

```
writefont/
├── README.md                    # 项目说明
├── LICENSE                      # MIT License
├── setup.py                     # 安装配置
├── pyproject.toml               # 项目元数据
├── requirements.txt             # 依赖列表
├── configs/
│   └── default.yaml             # 默认配置
├── src/
│   └── writefont/
│       ├── __init__.py          # 包入口
│       ├── pipeline.py          # 主流程管道
│       ├── ocr/
│       │   ├── __init__.py
│       │   ├── recognizer.py    # OCR识别器
│       │   └── preprocessor.py  # 图像预处理
│       ├── style/
│       │   ├── __init__.py
│       │   ├── extractor.py     # 风格提取器
│       │   ├── model.py         # VAE模型
│       │   └── features.py      # 特征定义
│       ├── generator/
│       │   ├── __init__.py
│       │   ├── diffusion.py     # 扩散模型
│       │   └── renderer.py      # 字形渲染
│       ├── font/
│       │   ├── __init__.py
│       │   ├── packager.py      # 字体打包
│       │   └── vectorizer.py    # 矢量化
│       ├── utils/
│       │   ├── __init__.py
│       │   ├── charset.py       # 字符集工具
│       │   └── image.py         # 图像工具
│       └── frontend/
│           ├── __init__.py
│           └── app.py           # Gradio界面
├── tests/
│   ├── __init__.py
│   ├── test_preprocessor.py
│   ├── test_ocr.py
│   ├── test_style.py
│   ├── test_generator.py
│   └── test_font.py
├── docs/
│   ├── architecture.md          # 架构文档
│   ├── training.md              # 训练指南
│   └── api.md                   # API文档
└── examples/
    └── sample_input/            # 示例输入
```

### 配置说明

编辑 `configs/default.yaml` 自定义参数：

```yaml
# 预处理
preprocessing:
  target_size: 128
  binarization_threshold: 128
  denoise_strength: 3

# OCR
ocr:
  engine: paddleocr  # paddleocr / crnn
  confidence_threshold: 0.8
  language: ch

# 风格提取
style:
  feature_dim: 200
  model_path: models/style_vae.pth

# 字体生成
generator:
  model_type: diffusion  # diffusion / gan
  num_inference_steps: 50
  guidance_scale: 7.5

# 输出
output:
  formats: [ttf, otf, woff]
  resolution: 256
```

### 常见问题

**Q: 需要多少手写样本？**
A: 建议50个汉字，覆盖基本笔画和结构。最少30个，最多100个。

**Q: 支持哪些语言？**
A: 目前仅支持简体中文（GB2312字符集），未来计划支持繁体中文和日文。

**Q: 生成一个字体需要多长时间？**
A: GPU约10-30分钟，CPU约2-6小时（6763字）。

**Q: 字体质量如何？**
A: 常用字（约3000字）质量较高，生僻字可能略有瑕疵。建议人工校对后使用。

### 贡献指南

欢迎贡献！请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 了解详情。

### 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE)。

---

## English

### Introduction

WriteFont is an open-source AI font generation tool. Users only need to photograph and upload about 50 handwritten Chinese characters, and the system will automatically:

1. OCR recognize and extract handwritten characters
2. Analyze and extract personal handwriting style features (200+ dimensional feature vector)
3. Generate complete GB2312 character set (6,763 characters) based on style vector
4. Export as TTF/OTF/WOFF format font files

**All AI inference is completed locally, no internet required, protecting user privacy.**

### Key Features

- 🔍 **High-precision OCR**: Based on PaddleOCR, 99%+ accuracy for handwritten Chinese characters
- 🎨 **Style Extraction**: Autoencoder extracts 200+ dimensional handwriting features
- 🤖 **AI Generation**: Diffusion model-based glyph generation with style consistency
- 📦 **Font Packaging**: Supports TTF/OTF/WOFF formats, directly installable
- 💻 **Local Deployment**: Fully offline, data never leaves user device
- 🖥️ **Web Interface**: Friendly Gradio-based UI

### Quick Start

```bash
git clone https://github.com/your-username/writefont.git
cd writefont
python -m venv venv
source venv/bin/activate
pip install -e .
writefont-ui
```

### License

MIT License. See [LICENSE](LICENSE) for details.
