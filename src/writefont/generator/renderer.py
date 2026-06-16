"""Glyph renderer: convert raw diffusion output to clean binary glyphs."""

from __future__ import annotations

from typing import Optional, Tuple

import cv2
import numpy as np


class GlyphRenderer:
    """Post-process generated glyph images into clean, binary, font-ready bitmaps.

    The pipeline:
    1. Denormalise from [-1, 1] → [0, 255] uint8.
    2. (Optional) resize to target size.
    3. Adaptive / Otsu thresholding to produce a binary image.
    4. Morphological clean-up (open/close) to remove speckles.
    5. Crop to content bounding-box and centre-pad.

    Parameters
    ----------
    target_size : tuple[int, int]
        Desired output size (width, height) in pixels.
    threshold_method : str
        ``"otsu"`` or ``"adaptive"``.
    morph_kernel_size : int
        Kernel size for morphological operations.
    """

    def __init__(
        self,
        target_size: Tuple[int, int] = (128, 128),
        threshold_method: str = "otsu",
        morph_kernel_size: int = 3,
    ) -> None:
        self.target_size = target_size
        self.threshold_method = threshold_method
        self.morph_kernel = cv2.getStructuringElement(
            cv2.MORPH_ELLIPSE, (morph_kernel_size, morph_kernel_size)
        )

    # ------------------------------------------------------------------
    # public API
    # ------------------------------------------------------------------

    def render(
        self,
        image: torch.Tensor | np.ndarray,
    ) -> np.ndarray:
        """Render a single glyph image to a clean binary bitmap.

        Parameters
        ----------
        image : Tensor or ndarray
            - If Tensor: expected shape ``[C, H, W]`` or ``[B, C, H, W]`` with values in [-1, 1].
            - If ndarray: expected shape ``(H, W)`` or ``(H, W, C)`` with values 0-255.

        Returns
        -------
        ndarray of uint8, shape ``(H, W)``
            Binary glyph (0 = background, 255 = foreground ink).
        """
        gray = self._to_grayscale(image)
        binary = self._binarise(gray)
        cleaned = self._morph_clean(binary)
        cropped = self._crop_and_centre(cleaned)
        return cropped

    def render_batch(
        self,
        images: torch.Tensor,
    ) -> list[np.ndarray]:
        """Render a batch of glyph images.

        Parameters
        ----------
        images : Tensor [B, C, H, W]
            Batch of generated glyphs in [-1, 1].

        Returns
        -------
        list[ndarray]
            List of cleaned binary bitmaps.
        """
        results = []
        for i in range(images.shape[0]):
            results.append(self.render(images[i]))
        return results

    # ------------------------------------------------------------------
    # internal helpers
    # ------------------------------------------------------------------

    def _to_grayscale(self, image):
        """Convert input to a single-channel uint8 numpy array in [0, 255]."""
        import torch

        if isinstance(image, torch.Tensor):
            img = image.detach().cpu().float()
            if img.dim() == 3:
                img = img[0] if img.shape[0] <= 4 else img.mean(dim=-1)  # C,H,W → H,W
            elif img.dim() == 2:
                pass
            else:
                raise ValueError(f"Unsupported tensor dims: {img.dim()}")
            # Denormalise [-1,1] → [0,255]
            img = ((img + 1) * 127.5).clamp(0, 255).byte().numpy()
        else:
            img = np.asarray(image)
            if img.ndim == 3:
                img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            img = img.astype(np.uint8)
        return img

    def _binarise(self, gray: np.ndarray) -> np.ndarray:
        """Threshold a grayscale image to binary."""
        if self.threshold_method == "otsu":
            _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        elif self.threshold_method == "adaptive":
            binary = cv2.adaptiveThreshold(
                gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
            )
        else:
            raise ValueError(f"Unknown threshold method: {self.threshold_method}")
        return binary

    def _morph_clean(self, binary: np.ndarray) -> np.ndarray:
        """Morphological opening + closing to remove noise."""
        opened = cv2.morphologyEx(binary, cv2.MORPH_OPEN, self.morph_kernel)
        closed = cv2.morphologyEx(opened, cv2.MORPH_CLOSE, self.morph_kernel)
        return closed

    def _crop_and_centre(
        self,
        binary: np.ndarray,
        pad_ratio: float = 0.1,
    ) -> np.ndarray:
        """Crop to the ink bounding-box and centre in ``target_size``."""
        # Find content bounding box
        coords = cv2.findNonZero(binary)
        if coords is None:
            # Blank image → return black canvas
            return np.zeros(self.target_size, dtype=np.uint8)

        x, y, w, h = cv2.boundingRect(coords)

        # Add padding
        pad_x = max(1, int(w * pad_ratio))
        pad_y = max(1, int(h * pad_ratio))
        x0 = max(0, x - pad_x)
        y0 = max(0, y - pad_y)
        x1 = min(binary.shape[1], x + w + pad_x)
        y1 = min(binary.shape[0], y + h + pad_y)
        cropped = binary[y0:y1, x0:x1]

        # Resize preserving aspect ratio, then centre-pad to target_size
        tw, th = self.target_size
        ch, cw = cropped.shape[:2]
        scale = min(tw / cw, th / ch)
        new_w = max(1, int(cw * scale))
        new_h = max(1, int(ch * scale))
        resized = cv2.resize(cropped, (new_w, new_h), interpolation=cv2.INTER_AREA)

        # Centre onto canvas
        canvas = np.zeros((th, tw), dtype=np.uint8)
        off_x = (tw - new_w) // 2
        off_y = (th - new_h) // 2
        canvas[off_y:off_y + new_h, off_x:off_x + new_w] = resized
        return canvas
