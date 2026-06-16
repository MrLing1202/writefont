"""
风格提取器模块。

提供从手写样本图像中提取风格向量的功能，并支持保存和加载风格向量。
"""

import os
import json
import logging
from pathlib import Path
from typing import List, Optional, Union

import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image

from .model import StyleVAE
from .features import HandwritingFeatures

logger = logging.getLogger(__name__)


class StyleExtractor:
    """
    笔迹风格提取器。

    使用训练好的StyleVAE模型从手写样本图像中提取200维风格向量。

    使用方法:
        extractor = StyleExtractor(model_path="model.pth")
        style_vector = extractor.extract_features(sample_images)
        extractor.save_style_vector(style_vector, "style.json")
    """

    def __init__(
        self,
        model_path: Optional[str] = None,
        latent_dim: int = 200,
        device: Optional[str] = None,
        image_size: int = 128,
    ):
        """
        初始化风格提取器。

        Args:
            model_path: 预训练模型路径，为None时使用随机初始化的模型
            latent_dim: 潜在空间维度，默认200
            device: 计算设备，为None时自动选择
            image_size: 输入图像尺寸，默认128
        """
        self.latent_dim = latent_dim
        self.image_size = image_size

        # 设备选择
        if device is None:
            self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        else:
            self.device = torch.device(device)

        # 初始化模型
        self.model = StyleVAE(latent_dim=latent_dim).to(self.device)

        # 加载预训练权重
        if model_path is not None and os.path.exists(model_path):
            self._load_model(model_path)
            logger.info(f"Loaded model from {model_path}")
        else:
            logger.warning("No pre-trained model loaded; using random initialization")

        self.model.eval()

    def _load_model(self, model_path: str) -> None:
        """加载模型权重。"""
        checkpoint = torch.load(model_path, map_location=self.device)
        if isinstance(checkpoint, dict) and "model_state_dict" in checkpoint:
            self.model.load_state_dict(checkpoint["model_state_dict"])
        else:
            self.model.load_state_dict(checkpoint)

    def preprocess_image(self, image: Union[str, np.ndarray, Image.Image]) -> torch.Tensor:
        """
        预处理单张图像为模型输入格式。

        Args:
            image: 图像路径(str)、numpy数组或PIL图像

        Returns:
            torch.Tensor: 形状 (1, 1, image_size, image_size)
        """
        if isinstance(image, str):
            img = Image.open(image).convert("L")
        elif isinstance(image, np.ndarray):
            img = Image.fromarray(image).convert("L")
        elif isinstance(image, Image.Image):
            img = image.convert("L")
        else:
            raise ValueError(f"Unsupported image type: {type(image)}")

        img = img.resize((self.image_size, self.image_size), Image.LANCZOS)
        img_array = np.array(img, dtype=np.float32) / 255.0
        tensor = torch.from_numpy(img_array).unsqueeze(0).unsqueeze(0)  # (1,1,H,W)
        return tensor

    def preprocess_images(self, images: List[Union[str, np.ndarray, Image.Image]]) -> torch.Tensor:
        """
        批量预处理图像。

        Args:
            images: 图像列表

        Returns:
            torch.Tensor: 形状 (N, 1, image_size, image_size)
        """
        tensors = [self.preprocess_image(img) for img in images]
        return torch.cat(tensors, dim=0)

    def extract_features(
        self, samples: List[Union[str, np.ndarray, Image.Image]]
    ) -> np.ndarray:
        """
        从样本图像列表中提取风格向量。

        将所有样本通过编码器得到mu向量，然后取平均作为最终风格向量。

        Args:
            samples: 样本图像列表，可以是文件路径、numpy数组或PIL图像

        Returns:
            np.ndarray: 200维风格向量
        """
        if not samples:
            raise ValueError("At least one sample image is required")

        batch = self.preprocess_images(samples).to(self.device)

        with torch.no_grad():
            mu, logvar = self.model.encode(batch)
            # 对所有样本的mu取平均
            style_vector = mu.mean(dim=0).cpu().numpy()

        return style_vector

    def extract_features_batch(
        self, samples: List[Union[str, np.ndarray, Image.Image]], batch_size: int = 32
    ) -> np.ndarray:
        """
        批量提取风格向量（适用于大量样本）。

        Args:
            samples: 样本图像列表
            batch_size: 每批处理数量

        Returns:
            np.ndarray: 200维风格向量
        """
        if not samples:
            raise ValueError("At least one sample image is required")

        all_mus = []
        for i in range(0, len(samples), batch_size):
            batch = self.preprocess_images(samples[i:i + batch_size]).to(self.device)
            with torch.no_grad():
                mu, _ = self.model.encode(batch)
                all_mus.append(mu.cpu())

        all_mus = torch.cat(all_mus, dim=0)
        style_vector = all_mus.mean(dim=0).numpy()
        return style_vector

    def extract_with_features(
        self, samples: List[Union[str, np.ndarray, Image.Image]]
    ) -> HandwritingFeatures:
        """
        提取风格并转换为结构化特征对象。

        Args:
            samples: 样本图像列表

        Returns:
            HandwritingFeatures: 结构化特征对象
        """
        vector = self.extract_features(samples)
        return HandwritingFeatures.from_vector(vector)

    def compare_styles(
        self, style_a: np.ndarray, style_b: np.ndarray
    ) -> dict:
        """
        比较两个风格向量的相似度。

        Args:
            style_a: 风格向量A
            style_b: 风格向量B

        Returns:
            dict: 包含多种相似度指标
        """
        cos_sim = F.cosine_similarity(
            torch.from_numpy(style_a).unsqueeze(0),
            torch.from_numpy(style_b).unsqueeze(0),
        ).item()

        l2_dist = np.linalg.norm(style_a - style_b)
        l1_dist = np.sum(np.abs(style_a - style_b))

        return {
            "cosine_similarity": cos_sim,
            "l2_distance": float(l2_dist),
            "l1_distance": float(l1_dist),
        }

    @staticmethod
    def save_style_vector(
        style_vector: np.ndarray,
        save_path: str,
        metadata: Optional[dict] = None,
    ) -> None:
        """
        保存风格向量到JSON文件。

        Args:
            style_vector: 200维风格向量
            save_path: 保存路径
            metadata: 可选的元数据
        """
        data = {
            "version": "1.0",
            "latent_dim": len(style_vector),
            "style_vector": style_vector.tolist(),
        }
        if metadata:
            data["metadata"] = metadata

        os.makedirs(os.path.dirname(save_path) or ".", exist_ok=True)
        with open(save_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        logger.info(f"Saved style vector to {save_path}")

    @staticmethod
    def load_style_vector(load_path: str) -> np.ndarray:
        """
        从JSON文件加载风格向量。

        Args:
            load_path: 文件路径

        Returns:
            np.ndarray: 风格向量

        Raises:
            FileNotFoundError: 文件不存在
            ValueError: 文件格式错误
        """
        if not os.path.exists(load_path):
            raise FileNotFoundError(f"Style vector file not found: {load_path}")

        with open(load_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        if "style_vector" not in data:
            raise ValueError("Invalid style vector file: missing 'style_vector' key")

        vector = np.array(data["style_vector"], dtype=np.float32)
        logger.info(f"Loaded style vector (dim={len(vector)}) from {load_path}")
        return vector

    @staticmethod
    def load_style_vector_with_metadata(load_path: str) -> tuple:
        """
        加载风格向量及其元数据。

        Args:
            load_path: 文件路径

        Returns:
            tuple: (style_vector, metadata)
        """
        if not os.path.exists(load_path):
            raise FileNotFoundError(f"Style vector file not found: {load_path}")

        with open(load_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        vector = np.array(data["style_vector"], dtype=np.float32)
        metadata = data.get("metadata", {})
        return vector, metadata
