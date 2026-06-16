"""图像预处理模块：透视矫正、去噪、二值化、字符分割、归一化。"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Tuple, Union

import cv2
import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

# 类型别名
ImageLike = Union[str, Path, np.ndarray, Image.Image]


@dataclass
class BBox:
    """字符/区域的边界框。"""
    x: int
    y: int
    w: int
    h: int

    @property
    def center(self) -> Tuple[int, int]:
        return (self.x + self.w // 2, self.y + self.h // 2)

    @property
    def area(self) -> int:
        return self.w * self.h


@dataclass
class CharRegion:
    """分割后的单个字符区域。"""
    image: np.ndarray          # 裁剪出的字符图像
    bbox: BBox                 # 在原图中的位置
    index: int = 0             # 排序后的序号


def _load_image(source: ImageLike) -> np.ndarray:
    """将多种来源统一加载为 BGR numpy 数组。"""
    if isinstance(source, np.ndarray):
        img = source
    elif isinstance(source, Image.Image):
        img = np.array(source)
        if img.ndim == 2:
            img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
        else:
            img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
    elif isinstance(source, (str, Path)):
        img = cv2.imread(str(source))
        if img is None:
            raise FileNotFoundError(f"无法读取图像: {source}")
    else:
        raise TypeError(f"不支持的图像类型: {type(source)}")
    return img


class ImagePreprocessor:
    """图像预处理器，提供从原始扫描图到可识别字符图像的完整流水线。"""

    def __init__(
        self,
        target_size: Tuple[int, int] = (64, 64),
        blur_kernel: Tuple[int, int] = (3, 3),
        median_kernel: int = 3,
        block_size: int = 25,
        c_offset: int = 10,
        min_char_area: int = 50,
        max_char_area_ratio: float = 0.5,
    ) -> None:
        self.target_size = target_size
        self.blur_kernel = blur_kernel
        self.median_kernel = median_kernel
        self.block_size = block_size
        self.c_offset = c_offset
        self.min_char_area = min_char_area
        self.max_char_area_ratio = max_char_area_ratio

    # ------------------------------------------------------------------ #
    #  公开 API
    # ------------------------------------------------------------------ #

    def perspective_correction(self, image: ImageLike) -> np.ndarray:
        """透视矫正：检测纸张边缘并进行四点透视变换。

        Args:
            image: 输入图像。

        Returns:
            矫正后的图像（鸟瞰视角）。
        """
        img = _load_image(image)
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blurred, 50, 150)

        # 膨胀以连接断裂边缘
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
        edges = cv2.dilate(edges, kernel, iterations=2)

        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            logger.warning("未检测到轮廓，跳过透视矫正")
            return img

        # 取最大轮廓作为纸张候选
        largest = max(contours, key=cv2.contourArea)
        peri = cv2.arcLength(largest, True)
        approx = cv2.approxPolyDP(largest, 0.02 * peri, True)

        if len(approx) == 4:
            pts = approx.reshape(4, 2).astype(np.float32)
        else:
            # 回退：使用最小外接矩形
            rect = cv2.minAreaRect(largest)
            pts = cv2.boxPoints(rect).astype(np.float32)

        # 排序：左上、右上、右下、左下
        pts = self._order_points(pts)
        (tl, tr, br, bl) = pts

        width = int(max(
            np.linalg.norm(br - bl),
            np.linalg.norm(tr - tl),
        ))
        height = int(max(
            np.linalg.norm(tr - br),
            np.linalg.norm(tl - bl),
        ))

        dst = np.array([
            [0, 0],
            [width - 1, 0],
            [width - 1, height - 1],
            [0, height - 1],
        ], dtype=np.float32)

        M = cv2.getPerspectiveTransform(pts, dst)
        warped = cv2.warpPerspective(img, M, (width, height))
        return warped

    def denoise(self, image: np.ndarray) -> np.ndarray:
        """去噪：高斯模糊 + 中值滤波。

        Args:
            image: BGR 或灰度图。

        Returns:
            去噪后的图像。
        """
        img = image.copy()
        img = cv2.GaussianBlur(img, self.blur_kernel, 0)
        img = cv2.medianBlur(img, self.median_kernel)
        return img

    def binarize(self, image: np.ndarray) -> np.ndarray:
        """二值化：自适应阈值。

        Args:
            image: 输入图像（灰度或 BGR）。

        Returns:
            二值化后的单通道图像（白字黑底）。
        """
        gray = image if image.ndim == 2 else cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        binary = cv2.adaptiveThreshold(
            gray, 255,
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY_INV,
            self.block_size,
            self.c_offset,
        )
        return binary

    def segment_characters(self, binary: np.ndarray) -> List[CharRegion]:
        """字符分割：连通域分析 + 投影法辅助。

        Args:
            binary: 二值化图像（白字黑底）。

        Returns:
            按从左到右排序的字符区域列表。
        """
        h_img, w_img = binary.shape[:2]
        total_area = h_img * w_img
        max_area = total_area * self.max_char_area_ratio

        # 连通域分析
        num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(
            binary, connectivity=8
        )

        regions: List[CharRegion] = []
        for i in range(1, num_labels):  # 跳过背景 (0)
            x, y, w, h, area = stats[i]
            if area < self.min_char_area or area > max_area:
                continue
            # 过滤过于细长或扁平的噪声
            aspect = w / max(h, 1)
            if aspect > 10 or aspect < 0.02:
                continue

            char_img = binary[y:y + h, x:x + w].copy()
            regions.append(CharRegion(
                image=char_img,
                bbox=BBox(x, y, w, h),
            ))

        # 按 x 坐标排序（左→右）
        regions.sort(key=lambda r: r.bbox.x)
        for idx, r in enumerate(regions):
            r.index = idx

        if not regions:
            logger.info("连通域未找到字符，尝试投影法")
            regions = self._projection_segment(binary)

        return regions

    def normalize(
        self,
        char_image: np.ndarray,
        target_size: Optional[Tuple[int, int]] = None,
        pad_value: int = 0,
    ) -> np.ndarray:
        """归一化到统一尺寸，保持宽高比，不足部分填充。

        Args:
            char_image: 单个字符图像。
            target_size: (宽, 高)，默认使用初始化参数。
            pad_value: 填充值（0=黑）。

        Returns:
            归一化后的图像。
        """
        size = target_size or self.target_size
        tw, th = size
        h, w = char_image.shape[:2]

        scale = min(tw / w, th / h)
        new_w, new_h = int(w * scale), int(h * scale)
        resized = cv2.resize(char_image, (new_w, new_h), interpolation=cv2.INTER_AREA)

        # 居中填充
        canvas = np.full((th, tw), pad_value, dtype=np.uint8)
        dx = (tw - new_w) // 2
        dy = (th - new_h) // 2
        canvas[dy:dy + new_h, dx:dx + new_w] = resized
        return canvas

    def preprocess_pipeline(
        self,
        image: ImageLike,
        do_perspective: bool = True,
        do_denoise: bool = True,
        do_binarize: bool = True,
        do_segment: bool = True,
        do_normalize: bool = True,
    ) -> Union[np.ndarray, List[CharRegion]]:
        """完整预处理流水线。

        Args:
            image: 输入图像。
            do_perspective: 是否透视矫正。
            do_denoise: 是否去噪。
            do_binarize: 是否二值化。
            do_segment: 是否字符分割。
            do_normalize: 是否归一化（仅在分割时有效）。

        Returns:
            若 do_segment=False，返回预处理后的图像；
            若 do_segment=True，返回 CharRegion 列表。
        """
        img = _load_image(image)

        if do_perspective:
            img = self.perspective_correction(img)
        if do_denoise:
            img = self.denoise(img)
        if do_binarize:
            img = self.binarize(img)

        if not do_segment:
            return img

        regions = self.segment_characters(img)
        if do_normalize:
            for r in regions:
                r.image = self.normalize(r.image)

        return regions

    # ------------------------------------------------------------------ #
    #  内部辅助
    # ------------------------------------------------------------------ #

    @staticmethod
    def _order_points(pts: np.ndarray) -> np.ndarray:
        """将四个点排序为 [左上, 右上, 右下, 左下]。"""
        s = pts.sum(axis=1)
        d = np.diff(pts, axis=1).flatten()
        tl = pts[np.argmin(s)]
        br = pts[np.argmax(s)]
        tr = pts[np.argmin(d)]
        bl = pts[np.argmax(d)]
        return np.array([tl, tr, br, bl], dtype=np.float32)

    def _projection_segment(self, binary: np.ndarray) -> List[CharRegion]:
        """基于水平投影的字符分割（连通域失败时的回退方案）。"""
        h_img, w_img = binary.shape
        # 水平投影
        proj = np.sum(binary > 0, axis=0)

        # 寻找字符区间
        threshold = max(1, h_img * 0.05)
        in_char = False
        start = 0
        regions: List[CharRegion] = []

        for x in range(w_img):
            if proj[x] > threshold and not in_char:
                start = x
                in_char = True
            elif proj[x] <= threshold and in_char:
                if x - start > 3:  # 最小宽度过滤
                    char_img = binary[:, start:x]
                    # 找垂直范围
                    row_proj = np.sum(char_img > 0, axis=1)
                    rows = np.where(row_proj > 0)[0]
                    if len(rows) > 0:
                        y0, y1 = rows[0], rows[-1]
                        char_img = binary[y0:y1 + 1, start:x]
                        regions.append(CharRegion(
                            image=char_img,
                            bbox=BBox(start, y0, x - start, y1 - y0 + 1),
                        ))
                in_char = False

        # 处理末尾
        if in_char and w_img - start > 3:
            char_img = binary[:, start:w_img]
            row_proj = np.sum(char_img > 0, axis=1)
            rows = np.where(row_proj > 0)[0]
            if len(rows) > 0:
                y0, y1 = rows[0], rows[-1]
                char_img = binary[y0:y1 + 1, start:w_img]
                regions.append(CharRegion(
                    image=char_img,
                    bbox=BBox(start, y0, w_img - start, y1 - y0 + 1),
                ))

        for idx, r in enumerate(regions):
            r.index = idx
        return regions
