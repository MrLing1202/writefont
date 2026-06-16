"""Conditional diffusion model for handwriting-style glyph generation.

Implements a UNet-based denoising diffusion probabilistic model (DDPM) that
generates glyph images conditioned on a style vector and character encoding.
"""

from __future__ import annotations

import math
from typing import Optional, Tuple

import torch
import torch.nn as nn
import torch.nn.functional as F


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

class SinusoidalPositionEmbedding(nn.Module):
    """Sinusoidal timestep embedding (Vaswani et al., 2017)."""

    def __init__(self, dim: int) -> None:
        super().__init__()
        self.dim = dim

    def forward(self, t: torch.Tensor) -> torch.Tensor:
        half = self.dim // 2
        emb = math.log(10000.0) / (half - 1)
        emb = torch.exp(torch.arange(half, device=t.device, dtype=torch.float32) * -emb)
        emb = t[:, None].float() * emb[None, :]
        return torch.cat([emb.sin(), emb.cos()], dim=-1)


class ResBlock(nn.Module):
    """Residual block with timestep and condition injection."""

    def __init__(self, in_ch: int, out_ch: int, cond_dim: int, *, dropout: float = 0.1) -> None:
        super().__init__()
        self.norm1 = nn.GroupNorm(8, in_ch)
        self.conv1 = nn.Conv2d(in_ch, out_ch, 3, padding=1)
        self.norm2 = nn.GroupNorm(8, out_ch)
        self.conv2 = nn.Conv2d(out_ch, out_ch, 3, padding=1)
        self.dropout = nn.Dropout(dropout)
        self.cond_proj = nn.Linear(cond_dim, out_ch)
        self.skip = nn.Conv2d(in_ch, out_ch, 1) if in_ch != out_ch else nn.Identity()

    def forward(self, x: torch.Tensor, cond: torch.Tensor) -> torch.Tensor:
        h = self.conv1(F.silu(self.norm1(x)))
        h = h + self.cond_proj(F.silu(cond))[:, :, None, None]
        h = self.conv2(self.dropout(F.silu(self.norm2(h))))
        return h + self.skip(x)


class SelfAttention(nn.Module):
    """Simple self-attention for feature maps."""

    def __init__(self, channels: int, num_heads: int = 4) -> None:
        super().__init__()
        self.norm = nn.GroupNorm(8, channels)
        self.attn = nn.MultiheadAttention(channels, num_heads, batch_first=True)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        b, c, h, w = x.shape
        residual = x
        x_flat = self.norm(x).reshape(b, c, h * w).permute(0, 2, 1)
        out, _ = self.attn(x_flat, x_flat, x_flat)
        return residual + out.permute(0, 2, 1).reshape(b, c, h, w)


# ---------------------------------------------------------------------------
# UNet
# ---------------------------------------------------------------------------

class UNetNoisePredictor(nn.Module):
    """UNet architecture for noise prediction in diffusion process.

    The network takes a noisy image, timestep embedding, style vector, and
    character encoding as inputs, and predicts the noise added at that step.

    Parameters
    ----------
    img_channels : int
        Number of input image channels (1 for grayscale).
    style_dim : int
        Dimension of the style embedding vector.
    char_dim : int
        Dimension of the character encoding vector.
    base_channels : int
        Base channel count, doubled at each downsampling stage.
    channel_mults : tuple[int, ...]
        Channel multipliers for each resolution level.
    num_res_blocks : int
        Number of residual blocks per level.
    """

    def __init__(
        self,
        img_channels: int = 1,
        style_dim: int = 128,
        char_dim: int = 256,
        base_channels: int = 64,
        channel_mults: Tuple[int, ...] = (1, 2, 4, 8),
        num_res_blocks: int = 2,
    ) -> None:
        super().__init__()
        cond_dim = style_dim + char_dim
        time_dim = base_channels * 4

        # Timestep MLP
        self.time_mlp = nn.Sequential(
            SinusoidalPositionEmbedding(time_dim),
            nn.Linear(time_dim, time_dim),
            nn.SiLU(),
            nn.Linear(time_dim, time_dim),
        )

        # Combined condition dim = timestep + style + char
        full_cond_dim = time_dim + cond_dim

        # Initial convolution
        self.input_conv = nn.Conv2d(img_channels, base_channels, 3, padding=1)

        # Encoder
        self.down_blocks = nn.ModuleList()
        self.down_samples = nn.ModuleList()
        ch = base_channels
        channels_list = [ch]
        for mult in channel_mults:
            out_ch = base_channels * mult
            blocks = nn.ModuleList([ResBlock(ch, out_ch, full_cond_dim) for _ in range(num_res_blocks)])
            self.down_blocks.append(blocks)
            ch = out_ch
            channels_list.append(ch)
            self.down_samples.append(nn.Conv2d(ch, ch, 3, stride=2, padding=1))

        # Bottleneck
        self.mid_block1 = ResBlock(ch, ch, full_cond_dim)
        self.mid_attn = SelfAttention(ch)
        self.mid_block2 = ResBlock(ch, ch, full_cond_dim)

        # Decoder
        self.up_blocks = nn.ModuleList()
        self.up_samples = nn.ModuleList()
        for i, mult in reversed(list(enumerate(channel_mults))):
            out_ch = base_channels * mult
            skip_ch = channels_list.pop()
            blocks = nn.ModuleList()
            for j in range(num_res_blocks + 1):
                in_c = ch + skip_ch if j == 0 else out_ch
                blocks.append(ResBlock(in_c, out_ch, full_cond_dim))
            self.up_blocks.append(blocks)
            ch = out_ch
            self.up_samples.append(nn.ConvTranspose2d(ch, ch, 4, stride=2, padding=1))

        # Output
        self.output_conv = nn.Sequential(
            nn.GroupNorm(8, ch),
            nn.SiLU(),
            nn.Conv2d(ch, img_channels, 3, padding=1),
        )

        self._time_dim = time_dim
        self._cond_dim = cond_dim

    def forward(
        self,
        x: torch.Tensor,
        t: torch.Tensor,
        style: torch.Tensor,
        char_enc: torch.Tensor,
    ) -> torch.Tensor:
        """Predict noise for *x* at timestep *t*.

        Parameters
        ----------
        x : Tensor [B, C, H, W]
            Noisy image.
        t : Tensor [B]
            Timestep indices.
        style : Tensor [B, style_dim]
            Style embedding.
        char_enc : Tensor [B, char_dim]
            Character encoding.

        Returns
        -------
        Tensor [B, C, H, W]
            Predicted noise.
        """
        # Build conditioning vector
        t_emb = self.time_mlp(t)
        cond = torch.cat([t_emb, style, char_enc], dim=-1)

        h = self.input_conv(x)
        skips = [h]

        # Encoder path
        for blocks, down in zip(self.down_blocks, self.down_samples):
            for block in blocks:
                h = block(h, cond)
            skips.append(h)
            h = down(h)

        # Bottleneck
        h = self.mid_block1(h, cond)
        h = self.mid_attn(h)
        h = self.mid_block2(h, cond)

        # Decoder path
        for blocks, up in zip(self.up_blocks, self.up_samples):
            h = up(h)
            skip = skips.pop()
            # Handle size mismatch from stride-2 rounding
            if h.shape[-2:] != skip.shape[-2:]:
                h = F.interpolate(h, size=skip.shape[-2:], mode="bilinear", align_corners=False)
            for i, block in enumerate(blocks):
                if i == 0:
                    h = torch.cat([h, skip], dim=1)
                h = block(h, cond)

        return self.output_conv(h)


# ---------------------------------------------------------------------------
# Diffusion schedule helpers
# ---------------------------------------------------------------------------

def _make_beta_schedule(
    num_steps: int,
    beta_start: float = 1e-4,
    beta_end: float = 0.02,
) -> torch.Tensor:
    """Linear beta schedule."""
    return torch.linspace(beta_start, beta_end, num_steps)


# ---------------------------------------------------------------------------
# Conditional Diffusion Model
# ---------------------------------------------------------------------------

class ConditionalDiffusionModel(nn.Module):
    """Conditional diffusion model for glyph generation.

    Given a *style vector* (extracted from reference handwriting images) and
    a *character encoding* (embedding of the target character), the model
    generates a glyph image through iterative denoising.

    Parameters
    ----------
    img_size : int
        Generated image spatial size (assumed square).
    img_channels : int
        Number of image channels.
    style_dim : int
        Dimensionality of the style embedding.
    char_vocab_size : int
        Size of character vocabulary.
    char_emb_dim : int
        Character embedding dimension.
    num_diffusion_steps : int
        Number of diffusion timesteps.
    """

    def __init__(
        self,
        img_size: int = 64,
        img_channels: int = 1,
        style_dim: int = 128,
        char_vocab_size: int = 8000,
        char_emb_dim: int = 256,
        num_diffusion_steps: int = 1000,
    ) -> None:
        super().__init__()
        self.img_size = img_size
        self.img_channels = img_channels
        self.num_steps = num_diffusion_steps

        # Character embedding table
        self.char_embedding = nn.Embedding(char_vocab_size, char_emb_dim)

        # UNet noise predictor
        self.noise_predictor = UNetNoisePredictor(
            img_channels=img_channels,
            style_dim=style_dim,
            char_dim=char_emb_dim,
        )

        # Noise schedule
        betas = _make_beta_schedule(num_diffusion_steps)
        alphas = 1.0 - betas
        alphas_cumprod = torch.cumprod(alphas, dim=0)

        self.register_buffer("betas", betas)
        self.register_buffer("alphas", alphas)
        self.register_buffer("alphas_cumprod", alphas_cumprod)
        self.register_buffer("sqrt_alphas_cumprod", torch.sqrt(alphas_cumprod))
        self.register_buffer("sqrt_one_minus_alphas_cumprod", torch.sqrt(1.0 - alphas_cumprod))
        self.register_buffer(
            "sqrt_recip_alphas_cumprod",
            torch.sqrt(1.0 / alphas_cumprod),
        )
        self.register_buffer(
            "posterior_mean_coeff1",
            betas * torch.sqrt(alphas_cumprod) / (1.0 - alphas_cumprod + 1e-8),
        )
        self.register_buffer(
            "posterior_mean_coeff2",
            alphas * torch.sqrt(1.0 - alphas_cumprod) / (1.0 - alphas_cumprod + 1e-8),
        )

    # ---- forward / reverse diffusion ----

    def q_sample(
        self,
        x0: torch.Tensor,
        t: torch.Tensor,
        noise: Optional[torch.Tensor] = None,
    ) -> torch.Tensor:
        """Forward diffusion: add noise to clean image *x0* at timestep *t*.

        Parameters
        ----------
        x0 : Tensor [B, C, H, W]
            Clean images.
        t : Tensor [B]
            Timestep indices.
        noise : Tensor or None
            Optional pre-sampled noise.

        Returns
        -------
        Tensor [B, C, H, W]
            Noisy images.
        """
        if noise is None:
            noise = torch.randn_like(x0)
        sqrt_alpha = self.sqrt_alphas_cumprod[t][:, None, None, None]
        sqrt_one_minus = self.sqrt_one_minus_alphas_cumprod[t][:, None, None, None]
        return sqrt_alpha * x0 + sqrt_one_minus * noise

    def predict_noise(
        self,
        x: torch.Tensor,
        t: torch.Tensor,
        style: torch.Tensor,
        char_ids: torch.Tensor,
    ) -> torch.Tensor:
        """Predict noise component for *x* at timestep *t*."""
        char_emb = self.char_embedding(char_ids)
        return self.noise_predictor(x, t, style, char_emb)

    @torch.no_grad()
    def p_sample(
        self,
        x: torch.Tensor,
        t: int,
        style: torch.Tensor,
        char_ids: torch.Tensor,
    ) -> torch.Tensor:
        """Reverse diffusion single step: denoise *x* from step *t* to *t-1*."""
        b = x.shape[0]
        t_tensor = torch.full((b,), t, device=x.device, dtype=torch.long)
        pred_noise = self.predict_noise(x, t_tensor, style, char_ids)

        alpha = self.alphas[t]
        alpha_cumprod = self.alphas_cumprod[t]
        beta = self.betas[t]

        # Predict x0
        pred_x0 = (
            self.sqrt_recip_alphas_cumprod[t] * x
            - torch.sqrt(1.0 / alpha_cumprod - 1.0) * pred_noise
        )
        pred_x0 = pred_x0.clamp(-1, 1)

        # Compute posterior mean
        mean = self.posterior_mean_coeff1[t] * pred_x0 + self.posterior_mean_coeff2[t] * x

        if t > 0:
            noise = torch.randn_like(x)
            sigma = torch.sqrt(beta)
            return mean + sigma * noise
        return mean

    @torch.no_grad()
    def generate_glyph(
        self,
        style: torch.Tensor,
        char_id: int | torch.Tensor,
        device: Optional[torch.device] = None,
        num_steps: Optional[int] = None,
    ) -> torch.Tensor:
        """Generate a single glyph image.

        Parameters
        ----------
        style : Tensor [style_dim] or [1, style_dim]
            Style embedding vector.
        char_id : int or Tensor
            Character index into the embedding table.
        device : torch.device, optional
            Target device.
        num_steps : int, optional
            Override number of denoising steps (fewer = faster, lower quality).

        Returns
        -------
        Tensor [1, C, H, W]
            Generated glyph in [-1, 1].
        """
        if device is None:
            device = next(self.parameters()).device

        style = style.to(device)
        if style.dim() == 1:
            style = style.unsqueeze(0)

        if isinstance(char_id, int):
            char_ids = torch.tensor([char_id], device=device, dtype=torch.long)
        else:
            char_ids = char_id.to(device)
            if char_ids.dim() == 0:
                char_ids = char_ids.unsqueeze(0)

        steps = num_steps or self.num_steps
        img = torch.randn(1, self.img_channels, self.img_size, self.img_size, device=device)

        for t in reversed(range(steps)):
            img = self.p_sample(img, t, style, char_ids)

        return img

    def training_loss(
        self,
        x0: torch.Tensor,
        style: torch.Tensor,
        char_ids: torch.Tensor,
    ) -> torch.Tensor:
        """Compute simplified ELBO loss for training.

        Parameters
        ----------
        x0 : Tensor [B, C, H, W]
            Clean glyph images.
        style : Tensor [B, style_dim]
            Style vectors.
        char_ids : Tensor [B]
            Character indices.

        Returns
        -------
        Tensor
            Scalar MSE loss.
        """
        b = x0.shape[0]
        t = torch.randint(0, self.num_steps, (b,), device=x0.device)
        noise = torch.randn_like(x0)
        x_t = self.q_sample(x0, t, noise)
        pred = self.predict_noise(x_t, t, style, char_ids)
        return F.mse_loss(pred, noise)
