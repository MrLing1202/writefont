"""Image utility functions for glyph processing.

Provides helpers for resizing, padding, colour conversion, binarisation,
and normalisation commonly needed when preparing handwriting samples for
the diffusion model and when post-processing generated output.
"""

from __future__ import annotations

from typing import Tuple, Union

import cv2
import numpy as np
import torch
import torch.nn.functional as F


# ---------------------------------------------------------------------------
# Colour / type conversion
# ---------------------------------------------------------------------------

def to_grayscale(image: np.ndarray) -> np.ndarray:
    """Convert an image to single-channel grayscale (uint8).

    Parameters
    ----------
    image : ndarray
        Input image, shape ``(H, W)`` or ``(H, W, C)``.

    Returns
    -------
    ndarray
        Grayscale image, shape ``(H, W)``, dtype ``uint8``.
    """
    if image.ndim == 2:
        return image.astype(np.uint8)
    if image.ndim == 3:
        if image.shape[2] == 1:
            return image[:, :, 0].astype(np.uint8)
        if image.shape[2] == 3:
            return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        if image.shape[2] == 4:
            return cv2.cvtColor(image, cv2.COLOR_BGRA2GRAY)
    raise ValueError(f"Unsupported image shape: {image.shape}")


def to_binary(image: np.ndarray, threshold: int = 128) -> np.ndarray:
    """Binarise a grayscale image.

    Parameters
    ----------
    image : ndarray
        Grayscale input.
    threshold : int
        Fixed threshold value.

    Returns
    -------
    ndarray
        Binary image (0 or 255).
    """
    gray = to_grayscale(image) if image.ndim == 3 else image
    _, binary = cv2.threshold(gray, threshold, 255, cv2.THRESH_BINARY)
    return binary


# ---------------------------------------------------------------------------
# Resize / scale
# ---------------------------------------------------------------------------

def resize(
    image: np.ndarray,
    size: Tuple[int, int],
    interpolation: int = cv2.INTER_AREA,
) -> np.ndarray:
    """Resize an image to exact ``(width, height)``.

    Parameters
    ----------
    image : ndarray
        Input image.
    size : (int, int)
        Target ``(width, height)``.
    interpolation : int
        OpenCV interpolation flag.

    Returns
    -------
    ndarray
        Resized image.
    """
    return cv2.resize(image, size, interpolation=interpolation)


def resize_keep_aspect(
    image: np.ndarray,
    max_size: int,
    interpolation: int = cv2.INTER_AREA,
) -> np.ndarray:
    """Resize preserving aspect ratio so the longest side is *max_size*.

    Parameters
    ----------
    image : ndarray
        Input image.
    max_size : int
        Maximum dimension of the longer side.
    interpolation : int
        OpenCV interpolation flag.

    Returns
    -------
    ndarray
        Resized image.
    """
    h, w = image.shape[:2]
    scale = max_size / max(h, w)
    new_w = int(w * scale)
    new_h = int(h * scale)
    return cv2.resize(image, (new_w, new_h), interpolation=interpolation)


# ---------------------------------------------------------------------------
# Padding
# ---------------------------------------------------------------------------

def pad_to_square(
    image: np.ndarray,
    target_size: int = 128,
    pad_value: int = 0,
) -> np.ndarray:
    """Pad an image to a square of ``target_size × target_size``.

    The image is centred on the square canvas.

    Parameters
    ----------
    image : ndarray
        Input image (grayscale or colour).
    target_size : int
        Side length of the output square.
    pad_value : int
        Fill value for padding (0 = black).

    Returns
    -------
    ndarray
        Square image.
    """
    h, w = image.shape[:2]
    scale = min(target_size / h, target_size / w)
    new_h = max(1, int(h * scale))
    new_w = max(1, int(w * scale))
    resized = cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_AREA)

    # Create canvas
    if resized.ndim == 3:
        canvas = np.full((target_size, target_size, resized.shape[2]), pad_value, dtype=resized.dtype)
    else:
        canvas = np.full((target_size, target_size), pad_value, dtype=resized.dtype)

    # Centre paste
    off_y = (target_size - new_h) // 2
    off_x = (target_size - new_w) // 2
    canvas[off_y:off_y + new_h, off_x:off_x + new_w] = resized
    return canvas


def pad_to_multiple(image: np.ndarray, multiple: int = 8, pad_value: int = 0) -> np.ndarray:
    """Pad image dimensions to the next multiple of *multiple*.

    Useful for ensuring spatial dims are divisible by network stride.
    """
    h, w = image.shape[:2]
    new_h = ((h + multiple - 1) // multiple) * multiple
    new_w = ((w + multiple - 1) // multiple) * multiple
    if new_h == h and new_w == w:
        return image

    if image.ndim == 3:
        canvas = np.full((new_h, new_w, image.shape[2]), pad_value, dtype=image.dtype)
    else:
        canvas = np.full((new_h, new_w), pad_value, dtype=image.dtype)

    canvas[:h, :w] = image
    return canvas


# ---------------------------------------------------------------------------
# Tensor ↔ ndarray conversion
# ---------------------------------------------------------------------------

def ndarray_to_tensor(image: np.ndarray, normalise: bool = True) -> torch.Tensor:
    """Convert an ndarray image to a PyTorch tensor.

    Parameters
    ----------
    image : ndarray
        Shape ``(H, W)`` or ``(H, W, C)``.
    normalise : bool
        If True, scale from ``[0, 255]`` to ``[-1, 1]``.

    Returns
    -------
    Tensor
        Shape ``(C, H, W)`` or ``(1, H, W)`` for grayscale.
    """
    arr = image.astype(np.float32)
    if normalise:
        arr = arr / 127.5 - 1.0  # [0,255] → [-1,1]
    if arr.ndim == 2:
        arr = arr[np.newaxis, ...]  # (1, H, W)
    else:
        arr = arr.transpose(2, 0, 1)  # (C, H, W)
    return torch.from_numpy(arr)


def tensor_to_ndarray(tensor: torch.Tensor, denormalise: bool = True) -> np.ndarray:
    """Convert a tensor back to uint8 ndarray.

    Parameters
    ----------
    tensor : Tensor
        Shape ``(C, H, W)``.
    denormalise : bool
        If True, map from ``[-1, 1]`` to ``[0, 255]``.

    Returns
    -------
    ndarray
        Shape ``(H, W, C)`` or ``(H, W)`` for single channel.
    """
    arr = tensor.detach().cpu().float().numpy()
    if arr.ndim == 3 and arr.shape[0] == 1:
        arr = arr[0]  # (H, W)
    elif arr.ndim == 3:
        arr = arr.transpose(1, 2, 0)  # (H, W, C)

    if denormalise:
        arr = (arr + 1) * 127.5
    arr = arr.clip(0, 255).astype(np.uint8)
    return arr


# ---------------------------------------------------------------------------
# Augmentation helpers (for training)
# ---------------------------------------------------------------------------

def random_thicken(image: np.ndarray, kernel_range: Tuple[int, int] = (2, 4)) -> np.ndarray:
    """Randomly thicken strokes (morphological dilation)."""
    import random

    k = random.randint(*kernel_range)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    return cv2.dilate(image, kernel, iterations=1)


def random_thin(image: np.ndarray, kernel_range: Tuple[int, int] = (2, 4)) -> np.ndarray:
    """Randomly thin strokes (morphological erosion)."""
    import random

    k = random.randint(*kernel_range)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    return cv2.erode(image, kernel, iterations=1)


def random_rotate(image: np.ndarray, max_angle: float = 10.0) -> np.ndarray:
    """Apply a small random rotation."""
    import random

    angle = random.uniform(-max_angle, max_angle)
    h, w = image.shape[:2]
    centre = (w / 2, h / 2)
    matrix = cv2.getRotationMatrix2D(centre, angle, 1.0)
    return cv2.warpAffine(image, matrix, (w, h), borderValue=0)
