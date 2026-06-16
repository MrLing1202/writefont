"""
风格VAE模型定义模块。

定义StyleEncoder、StyleDecoder和StyleVAE，用于从字符图像中提取和生成200维风格向量。
输入: 128x128灰度字符图像
输出: 200维风格向量
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
from typing import Tuple, Optional


class StyleEncoder(nn.Module):
    """
    卷积编码器，将128x128灰度字符图像编码为200维风格向量的分布参数(mu和logvar)。

    网络结构:
        Conv2d(1,32) -> Conv2d(32,64) -> Conv2d(64,128) -> Conv2d(128,256)
        -> Flatten -> FC -> (mu, logvar)
    """

    def __init__(self, latent_dim: int = 200):
        """
        初始化编码器。

        Args:
            latent_dim: 潜在空间维度，默认200
        """
        super().__init__()
        self.latent_dim = latent_dim

        # 卷积层: 128x128 -> 64x64 -> 32x32 -> 16x16 -> 8x8
        self.conv_layers = nn.Sequential(
            # 1x128x128 -> 32x64x64
            nn.Conv2d(1, 32, kernel_size=4, stride=2, padding=1),
            nn.BatchNorm2d(32),
            nn.LeakyReLU(0.2, inplace=True),

            # 32x64x64 -> 64x32x32
            nn.Conv2d(32, 64, kernel_size=4, stride=2, padding=1),
            nn.BatchNorm2d(64),
            nn.LeakyReLU(0.2, inplace=True),

            # 64x32x32 -> 128x16x16
            nn.Conv2d(64, 128, kernel_size=4, stride=2, padding=1),
            nn.BatchNorm2d(128),
            nn.LeakyReLU(0.2, inplace=True),

            # 128x16x16 -> 256x8x8
            nn.Conv2d(128, 256, kernel_size=4, stride=2, padding=1),
            nn.BatchNorm2d(256),
            nn.LeakyReLU(0.2, inplace=True),
        )

        # 全连接层: 256*8*8=16384 -> latent_dim (mu) + latent_dim (logvar)
        self.fc_mu = nn.Linear(256 * 8 * 8, latent_dim)
        self.fc_logvar = nn.Linear(256 * 8 * 8, latent_dim)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        """
        前向传播。

        Args:
            x: 输入图像张量，形状 (batch_size, 1, 128, 128)

        Returns:
            Tuple[mu, logvar]: 均值和对数方差，形状均为 (batch_size, latent_dim)
        """
        h = self.conv_layers(x)
        h = h.view(h.size(0), -1)  # Flatten
        mu = self.fc_mu(h)
        logvar = self.fc_logvar(h)
        return mu, logvar


class StyleDecoder(nn.Module):
    """
    反卷积解码器，将200维风格向量解码为128x128灰度字符图像。

    网络结构:
        FC -> Reshape -> ConvTranspose2d(256,128) -> ConvTranspose2d(128,64)
        -> ConvTranspose2d(64,32) -> ConvTranspose2d(32,1) -> Sigmoid
    """

    def __init__(self, latent_dim: int = 200):
        """
        初始化解码器。

        Args:
            latent_dim: 潜在空间维度，默认200
        """
        super().__init__()
        self.latent_dim = latent_dim

        # 全连接层: latent_dim -> 256*8*8
        self.fc = nn.Linear(latent_dim, 256 * 8 * 8)

        # 反卷积层: 8x8 -> 16x16 -> 32x32 -> 64x64 -> 128x128
        self.deconv_layers = nn.Sequential(
            # 256x8x8 -> 128x16x16
            nn.ConvTranspose2d(256, 128, kernel_size=4, stride=2, padding=1),
            nn.BatchNorm2d(128),
            nn.ReLU(inplace=True),

            # 128x16x16 -> 64x32x32
            nn.ConvTranspose2d(128, 64, kernel_size=4, stride=2, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),

            # 64x32x32 -> 32x64x64
            nn.ConvTranspose2d(64, 32, kernel_size=4, stride=2, padding=1),
            nn.BatchNorm2d(32),
            nn.ReLU(inplace=True),

            # 32x64x64 -> 1x128x128
            nn.ConvTranspose2d(32, 1, kernel_size=4, stride=2, padding=1),
            nn.Sigmoid(),
        )

    def forward(self, z: torch.Tensor) -> torch.Tensor:
        """
        前向传播。

        Args:
            z: 风格向量，形状 (batch_size, latent_dim)

        Returns:
            重建图像，形状 (batch_size, 1, 128, 128)
        """
        h = self.fc(z)
        h = h.view(h.size(0), 256, 8, 8)  # Reshape
        return self.deconv_layers(h)


class StyleVAE(nn.Module):
    """
    完整的变分自编码器(VAE)模型。

    将128x128灰度字符图像编码为200维风格向量，并能从风格向量重建图像。

    使用方法:
        model = StyleVAE(latent_dim=200)
        recon, mu, logvar = model(images)  # forward
        z = model.encode(images)           # 仅编码
        img = model.decode(z)              # 仅解码
    """

    def __init__(self, latent_dim: int = 200):
        """
        初始化VAE。

        Args:
            latent_dim: 潜在空间维度，默认200
        """
        super().__init__()
        self.latent_dim = latent_dim
        self.encoder = StyleEncoder(latent_dim)
        self.decoder = StyleDecoder(latent_dim)

    def encode(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        """
        编码图像为分布参数。

        Args:
            x: 输入图像，形状 (batch_size, 1, 128, 128)

        Returns:
            Tuple[mu, logvar]: 均值和对数方差
        """
        return self.encoder(x)

    def reparameterize(self, mu: torch.Tensor, logvar: torch.Tensor) -> torch.Tensor:
        """
        重参数化技巧。

        Args:
            mu: 均值
            logvar: 对数方差

        Returns:
            采样的潜在向量z
        """
        if self.training:
            std = torch.exp(0.5 * logvar)
            eps = torch.randn_like(std)
            return mu + eps * std
        else:
            return mu

    def decode(self, z: torch.Tensor) -> torch.Tensor:
        """
        从潜在向量解码为图像。

        Args:
            z: 潜在向量，形状 (batch_size, latent_dim)

        Returns:
            重建图像，形状 (batch_size, 1, 128, 128)
        """
        return self.decoder(z)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        """
        完整前向传播。

        Args:
            x: 输入图像，形状 (batch_size, 1, 128, 128)

        Returns:
            Tuple[recon, mu, logvar]:
                - 重建图像 (batch_size, 1, 128, 128)
                - 均值 (batch_size, latent_dim)
                - 对数方差 (batch_size, latent_dim)
        """
        mu, logvar = self.encode(x)
        z = self.reparameterize(mu, logvar)
        recon = self.decode(z)
        return recon, mu, logvar

    def get_style_vector(self, x: torch.Tensor) -> torch.Tensor:
        """
        从图像获取风格向量（评估模式，直接返回mu）。

        Args:
            x: 输入图像，形状 (batch_size, 1, 128, 128)

        Returns:
            风格向量，形状 (batch_size, latent_dim)
        """
        self.eval()
        with torch.no_grad():
            mu, _ = self.encode(x)
        return mu


def vae_loss(
    recon_x: torch.Tensor,
    x: torch.Tensor,
    mu: torch.Tensor,
    logvar: torch.Tensor,
    beta: float = 1.0,
) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """
    VAE损失函数 = 重建损失 + beta * KL散度。

    Args:
        recon_x: 重建图像
        x: 原始图像
        mu: 均值
        logvar: 对数方差
        beta: KL散度权重系数

    Returns:
        Tuple[total_loss, recon_loss, kl_loss]
    """
    # 重建损失 (MSE)
    recon_loss = F.mse_loss(recon_x, x, reduction='sum')

    # KL散度
    kl_loss = -0.5 * torch.sum(1 + logvar - mu.pow(2) - logvar.exp())

    total_loss = recon_loss + beta * kl_loss
    return total_loss, recon_loss, kl_loss
