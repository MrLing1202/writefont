"""Setup script for writefont – mirrors pyproject.toml for editable installs."""

from setuptools import setup, find_packages

try:
    with open("README.md", encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = ""

setup(
    name="writefont",
    version="0.2.0",
    description="手迹造字 - AI字体生成工具，从手写样本生成完整字体库",
    long_description=long_description,
    long_description_content_type="text/markdown",
    license="MIT",
    python_requires=">=3.9",
    author="WriteFont",
    keywords=["font", "handwriting", "ai", "chinese", "generation"],
    classifiers=[
        "Development Status :: 3 - Alpha",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Multimedia :: Graphics",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    package_dir={"": "src"},
    packages=find_packages(where="src"),
    install_requires=[
        "numpy>=1.24.0",
        "scipy>=1.10.0",
        "Pillow>=10.0.0",
        "opencv-python-headless>=4.8.0",
        "pytesseract>=0.3.10",
        "fonttools>=4.40.0",
        "brotli>=1.0.9",
        "gradio>=4.0.0",
        "pyyaml>=6.0",
        "tqdm>=4.65.0",
        "httpx>=0.25.0",
    ],
    extras_require={
        "torch": [
            "torch>=2.0.0",
            "torchvision>=0.15.0",
            "scikit-learn>=1.3.0",
            "matplotlib>=3.7.0",
        ],
        "ocr": [
            "paddlepaddle>=2.5.0",
            "paddleocr>=2.7.0",
        ],
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "isort>=5.12.0",
            "mypy>=1.5.0",
        ],
        "all": ["writefont[torch,ocr,dev]"],
    },
    entry_points={
        "console_scripts": [
            "writefont=writefont.__main__:main",
            "writefont-ui=writefont.frontend.app:main",
        ],
    },
)
