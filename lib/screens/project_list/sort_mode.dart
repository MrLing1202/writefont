/// 排序方式枚举
enum SortMode {
  nameAsc, // 按名称升序
  nameDesc, // 按名称降序
  createdDesc, // 按创建时间倒序
  createdAsc, // 按创建时间正序
  updatedDesc, // 按修改时间倒序
  updatedAsc, // 按修改时间正序
  charCountDesc, // 按字符数量倒序
  charCountAsc, // 按字符数量正序
  progressDesc, // 按编辑进度倒序
  progressAsc, // 按编辑进度正序
}

/// 排序预设数据模型
class SortPreset {
  final String name;
  final SortMode primarySort;
  final SortMode? secondarySort;
  final bool reversed;

  const SortPreset({
    required this.name,
    required this.primarySort,
    this.secondarySort,
    this.reversed = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'primarySort': primarySort.index,
        'secondarySort': secondarySort?.index,
        'reversed': reversed,
      };

  factory SortPreset.fromJson(Map<String, dynamic> json) => SortPreset(
        name: json['name'] as String,
        primarySort: SortMode.values[json['primarySort'] as int],
        secondarySort: json['secondarySort'] != null
            ? SortMode.values[json['secondarySort'] as int]
            : null,
        reversed: json['reversed'] as bool? ?? false,
      );
}
