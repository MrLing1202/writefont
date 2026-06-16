"""
笔迹风格特征定义模块。

定义200维笔迹特征向量的结构，涵盖笔锋、力度、连笔、结构、起收笔、墨迹和全局特征。
"""

from dataclasses import dataclass, field
from typing import Dict, List, Tuple
import numpy as np


@dataclass
class StrokeFeatures:
    """笔锋特征 (30维)"""
    stroke_width: float = 0.0           # 笔画宽度
    stroke_pressure: float = 0.0        # 笔画压力
    taper_ratio: float = 0.0            # 收笔尖锐度
    stroke_curvature: float = 0.0       # 笔画弯曲度
    stroke_length: float = 0.0          # 笔画长度
    stroke_orientation: float = 0.0     # 笔画方向
    stroke_smoothness: float = 0.0      # 笔画平滑度
    stroke_regularity: float = 0.0      # 笔画规律性
    stroke_thickness_var: float = 0.0   # 笔画粗细变化
    pen_lift_freq: float = 0.0          # 抬笔频率
    brush_style: float = 0.0            # 毛笔风格指数
    ink_flow: float = 0.0               # 墨水流动度
    nib_angle: float = 0.0              # 笔尖角度
    stroke_symmetry: float = 0.0        # 笔画对称性
    stroke_sharpness: float = 0.0       # 笔画锐利度
    stroke_roundness: float = 0.0       # 笔画圆润度
    stroke_elongation: float = 0.0      # 笔画伸展度
    stroke_flexibility: float = 0.0     # 笔画柔韧度
    cross_section: float = 0.0          # 横截面形状
    stroke_energy: float = 0.0          # 笔画能量
    stroke_jitter: float = 0.0          # 笔画抖动
    stroke_confidence: float = 0.0      # 笔画自信度
    stroke_speed: float = 0.0           # 笔画速度
    stroke_acceleration: float = 0.0    # 笔画加速度
    pressure_gradient: float = 0.0      # 压力梯度
    width_consistency: float = 0.0      # 宽度一致性
    stroke_harmony: float = 0.0         # 笔画和谐度
    tip_shape: float = 0.0             # 笔尖形状
    brush_load: float = 0.0            # 载墨量
    stroke_dominance: float = 0.0       # 主笔画占比

    @classmethod
    def dim(cls) -> int:
        return 30


@dataclass
class PressureFeatures:
    """力度特征 (25维)"""
    pressure_variation: float = 0.0     # 压力变化幅度
    speed_profile: float = 0.0          # 速度分布
    pressure_mean: float = 0.0          # 平均压力
    pressure_max: float = 0.0           # 最大压力
    pressure_min: float = 0.0           # 最小压力
    pressure_std: float = 0.0           # 压力标准差
    acceleration_mean: float = 0.0      # 平均加速度
    deceleration_ratio: float = 0.0     # 减速比例
    force_consistency: float = 0.0      # 力度一致性
    grip_pressure: float = 0.0          # 握笔压力
    finger_pressure: float = 0.0        # 手指压力
    wrist_tension: float = 0.0          # 手腕张力
    arm_movement: float = 0.0           # 手臂运动
    pressure_symmetry: float = 0.0      # 压力对称性
    pressure_rhythm: float = 0.0        # 压力节奏
    energy_distribution: float = 0.0    # 能量分布
    pressure_recovery: float = 0.0      # 压力恢复
    impact_force: float = 0.0           # 冲击力
    sustained_pressure: float = 0.0     # 持续压力
    pressure_transition: float = 0.0    # 压力过渡
    dynamic_range: float = 0.0          # 动态范围
    pressure_stability: float = 0.0     # 压力稳定性
    writing_effort: float = 0.0         # 书写用力
    pressure_harmony: float = 0.0       # 压力和谐度
    force_pattern: float = 0.0          # 力度模式

    @classmethod
    def dim(cls) -> int:
        return 25


@dataclass
class ConnectionFeatures:
    """连笔特征 (35维)"""
    connection_type: float = 0.0        # 连笔类型
    connection_angle: float = 0.0       # 连笔角度
    ligature_ratio: float = 0.0         # 连笔比例
    connection_length: float = 0.0      # 连笔长度
    connection_strength: float = 0.0    # 连笔强度
    connection_smoothness: float = 0.0  # 连笔平滑度
    ligature_frequency: float = 0.0     # 连笔频率
    connection_consistency: float = 0.0 # 连笔一致性
    transition_speed: float = 0.0       # 过渡速度
    connection_style: float = 0.0       # 连笔风格
    overlap_ratio: float = 0.0          # 重叠比例
    gap_ratio: float = 0.0             # 间隔比例
    connection_pattern: float = 0.0     # 连笔模式
    curviness: float = 0.0             # 弯曲度
    flow_quality: float = 0.0          # 流畅度
    connection_density: float = 0.0     # 连笔密度
    linking_stroke_width: float = 0.0   # 连笔笔画宽度
    disconnection_freq: float = 0.0     # 断笔频率
    reconnection_freq: float = 0.0      # 重新连接频率
    connection_complexity: float = 0.0  # 连笔复杂度
    loop_ratio: float = 0.0            # 环形连笔比例
    straight_ratio: float = 0.0        # 直线连笔比例
    arc_ratio: float = 0.0             # 弧形连笔比例
    connection_regularity: float = 0.0  # 连笔规律性
    stroke_order: float = 0.0          # 笔顺
    connection_energy: float = 0.0      # 连笔能量
    ligature_depth: float = 0.0        # 连笔深度
    connection_width_var: float = 0.0   # 连笔宽度变化
    bridge_style: float = 0.0          # 桥接风格
    connection_elasticity: float = 0.0  # 连笔弹性
    connection_rhythm: float = 0.0      # 连笔节奏
    flow_direction: float = 0.0        # 流向
    connection_tension: float = 0.0     # 连笔张力
    ligature_harmony: float = 0.0      # 连笔和谐度
    connection_dominance: float = 0.0   # 连笔主导度

    @classmethod
    def dim(cls) -> int:
        return 35


@dataclass
class StructureFeatures:
    """结构特征 (40维)"""
    char_ratio: float = 0.0             # 字符宽高比
    component_spacing: float = 0.0      # 部件间距
    stroke_density: float = 0.0         # 笔画密度
    char_complexity: float = 0.0        # 字符复杂度
    balance_score: float = 0.0          # 平衡度
    symmetry_score: float = 0.0         # 对称度
    proportion_score: float = 0.0       # 比例度
    compactness: float = 0.0            # 紧凑度
    coverage_ratio: float = 0.0         # 覆盖率
    stroke_count: float = 0.0           # 笔画数
    component_count: float = 0.0        # 部件数
    radical_style: float = 0.0          # 偏旁风格
    spacing_uniformity: float = 0.0     # 间距均匀度
    alignment_accuracy: float = 0.0     # 对齐精度
    structure_stability: float = 0.0    # 结构稳定性
    frame_ratio: float = 0.0           # 框架比例
    inner_density: float = 0.0          # 内部密度
    outer_density: float = 0.0          # 外部密度
    center_of_mass: float = 0.0         # 质心位置
    aspect_ratio_var: float = 0.0       # 宽高比变化
    stroke_overlap: float = 0.0         # 笔画重叠
    enclosure_ratio: float = 0.0        # 包围比例
    opening_ratio: float = 0.0          # 开口比例
    closure_ratio: float = 0.0          # 闭合比例
    connectivity: float = 0.0           # 连通性
    skeleton_length: float = 0.0        # 骨架长度
    curvature_sum: float = 0.0          # 曲率总和
    corner_count: float = 0.0           # 角点数
    inflection_count: float = 0.0       # 拐点数
    structure_regularity: float = 0.0   # 结构规律性
    radial_balance: float = 0.0         # 径向平衡
    stroke_intersection: float = 0.0    # 笔画交叉
    stroke_junction: float = 0.0        # 笔画连接
    end_point_density: float = 0.0      # 端点密度
    turning_point_density: float = 0.0  # 转折点密度
    fill_ratio: float = 0.0            # 填充比例
    white_space_ratio: float = 0.0      # 空白比例
    structural_harmony: float = 0.0     # 结构和谐度
    grid_alignment: float = 0.0         # 网格对齐
    structure_dominance: float = 0.0    # 结构主导度

    @classmethod
    def dim(cls) -> int:
        return 40


@dataclass
class StartEndFeatures:
    """起收笔特征 (30维)"""
    start_angle: float = 0.0            # 起笔角度
    end_angle: float = 0.0              # 收笔角度
    hook_style: float = 0.0             # 钩的风格
    start_pressure: float = 0.0         # 起笔压力
    end_pressure: float = 0.0           # 收笔压力
    start_speed: float = 0.0            # 起笔速度
    end_speed: float = 0.0              # 收笔速度
    start_shape: float = 0.0            # 起笔形状
    end_shape: float = 0.0              # 收笔形状
    lift_style: float = 0.0             # 提笔风格
    press_style: float = 0.0            # 按笔风格
    turn_style: float = 0.0             # 转笔风格
    pause_style: float = 0.0            # 顿笔风格
    hook_angle: float = 0.0             # 钩的角度
    hook_length: float = 0.0            # 钩的长度
    dot_style: float = 0.0              # 点的风格
    horizontal_start: float = 0.0       # 横起笔
    horizontal_end: float = 0.0         # 横收笔
    vertical_start: float = 0.0         # 竖起笔
    vertical_end: float = 0.0           # 竖收笔
    left_fall: float = 0.0              # 撇
    right_fall: float = 0.0             # 捺
    rising_stroke: float = 0.0          # 提
    turning_stroke: float = 0.0         # 折
    hooking_stroke: float = 0.0         # 钩
    bending_stroke: float = 0.0         # 弯
    start_consistency: float = 0.0      # 起笔一致性
    end_consistency: float = 0.0        # 收笔一致性
    stroke_transition: float = 0.0      # 笔画过渡
    start_end_harmony: float = 0.0      # 起收笔和谐度

    @classmethod
    def dim(cls) -> int:
        return 30


@dataclass
class InkFeatures:
    """墨迹特征 (20维)"""
    ink_density: float = 0.0            # 墨迹密度
    ink_variation: float = 0.0          # 墨迹变化
    edge_sharpness: float = 0.0         # 边缘锐利度
    ink_consistency: float = 0.0        # 墨迹一致性
    ink_saturation: float = 0.0         # 墨迹饱和度
    ink_thickness: float = 0.0          # 墨迹厚度
    ink_spread: float = 0.0             # 墨迹扩散
    ink_dryness: float = 0.0            # 墨迹干燥度
    ink_opacity: float = 0.0            # 墨迹不透明度
    ink_texture: float = 0.0            # 墨迹纹理
    ink_edge_quality: float = 0.0       # 墨迹边缘质量
    ink_blob_ratio: float = 0.0         # 墨迹斑点比例
    ink_feathering: float = 0.0         # 墨迹羽化
    ink_bleed_through: float = 0.0      # 墨迹渗透
    ink_color_temp: float = 0.0         # 墨迹色温
    ink_shade_variation: float = 0.0    # 墨迹色调变化
    ink_grain: float = 0.0             # 墨迹颗粒感
    ink_smoothness: float = 0.0         # 墨迹平滑度
    ink_coverage: float = 0.0           # 墨迹覆盖度
    ink_quality: float = 0.0            # 墨迹质量

    @classmethod
    def dim(cls) -> int:
        return 20


@dataclass
class GlobalFeatures:
    """全局特征 (20维)"""
    slant_angle: float = 0.0            # 倾斜角度
    baseline_tendency: float = 0.0      # 基线趋势
    size_consistency: float = 0.0       # 大小一致性
    writing_speed: float = 0.0          # 书写速度
    rhythm_pattern: float = 0.0         # 节奏模式
    line_spacing: float = 0.0           # 行间距
    word_spacing: float = 0.0           # 字间距
    margin_width: float = 0.0           # 边距宽度
    writing_pressure_global: float = 0.0 # 整体书写压力
    fluency_score: float = 0.0          # 流畅度
    legibility_score: float = 0.0       # 可读性
    consistency_score: float = 0.0      # 一致性
    style_formality: float = 0.0        # 风格正式度
    style_elegance: float = 0.0         # 风格优雅度
    style_strength: float = 0.0         # 风格力度
    page_coverage: float = 0.0          # 页面覆盖率
    writing_rhythm: float = 0.0         # 书写节奏
    overall_balance: float = 0.0        # 整体平衡
    style_uniqueness: float = 0.0       # 风格独特性
    global_harmony: float = 0.0         # 全局和谐度

    @classmethod
    def dim(cls) -> int:
        return 20


@dataclass
class HandwritingFeatures:
    """
    200维笔迹特征向量。

    包含7个子特征组:
    - stroke: 笔锋特征 (30维)
    - pressure: 力度特征 (25维)
    - connection: 连笔特征 (35维)
    - structure: 结构特征 (40维)
    - start_end: 起收笔特征 (30维)
    - ink: 墨迹特征 (20维)
    - global_feat: 全局特征 (20维)

    总计: 200维
    """
    stroke: StrokeFeatures = field(default_factory=StrokeFeatures)
    pressure: PressureFeatures = field(default_factory=PressureFeatures)
    connection: ConnectionFeatures = field(default_factory=ConnectionFeatures)
    structure: StructureFeatures = field(default_factory=StructureFeatures)
    start_end: StartEndFeatures = field(default_factory=StartEndFeatures)
    ink: InkFeatures = field(default_factory=InkFeatures)
    global_feat: GlobalFeatures = field(default_factory=GlobalFeatures)

    @staticmethod
    def total_dim() -> int:
        """返回总特征维度"""
        return (StrokeFeatures.dim() + PressureFeatures.dim() +
                ConnectionFeatures.dim() + StructureFeatures.dim() +
                StartEndFeatures.dim() + InkFeatures.dim() +
                GlobalFeatures.dim())

    def to_vector(self) -> np.ndarray:
        """
        将所有特征展平为200维numpy向量。

        Returns:
            np.ndarray: 200维特征向量
        """
        vectors = []
        for feat_group in [self.stroke, self.pressure, self.connection,
                           self.structure, self.start_end, self.ink,
                           self.global_feat]:
            values = [v for k, v in feat_group.__dict__.items()
                      if isinstance(v, (int, float))]
            vectors.extend(values)
        return np.array(vectors, dtype=np.float32)

    @classmethod
    def from_vector(cls, vector: np.ndarray) -> "HandwritingFeatures":
        """
        从200维numpy向量重建特征对象。

        Args:
            vector: 200维特征向量

        Returns:
            HandwritingFeatures: 特征对象
        """
        assert len(vector) == cls.total_dim(), \
            f"Expected {cls.total_dim()} dimensions, got {len(vector)}"

        feat = cls()
        offset = 0
        for feat_group in [feat.stroke, feat.pressure, feat.connection,
                           feat.structure, feat.start_end, feat.ink,
                           feat.global_feat]:
            fields = [k for k in feat_group.__dict__ if isinstance(getattr(feat_group, k), (int, float))]
            for i, field_name in enumerate(fields):
                setattr(feat_group, field_name, float(vector[offset + i]))
            offset += len(fields)
        return feat

    @classmethod
    def feature_ranges(cls) -> Dict[str, Tuple[int, int]]:
        """
        返回各子特征在200维向量中的索引范围。

        Returns:
            Dict[str, Tuple[int, int]]: 特征名 -> (start_idx, end_idx)
        """
        ranges = {}
        offset = 0
        features = [
            ("stroke", StrokeFeatures.dim()),
            ("pressure", PressureFeatures.dim()),
            ("connection", ConnectionFeatures.dim()),
            ("structure", StructureFeatures.dim()),
            ("start_end", StartEndFeatures.dim()),
            ("ink", InkFeatures.dim()),
            ("global", GlobalFeatures.dim()),
        ]
        for name, dim in features:
            ranges[name] = (offset, offset + dim)
            offset += dim
        return ranges
