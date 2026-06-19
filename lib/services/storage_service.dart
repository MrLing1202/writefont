import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../models/project.dart';
import 'ttf_builder.dart';

/// Service for file operations: saving, loading, and exporting.
class StorageService {
  static const _uuid = Uuid();

  // ── 目录路径缓存（首次调用时初始化，后续直接返回） ──
  static Directory? _cachedDocumentsDir;
  static Directory? _cachedProjectsDir;
  static Directory? _cachedExportsDir;
  static Directory? _cachedBackupDir;

  // ── 网络优化：项目列表缓存（减少重复文件 I/O） ──
  static List<FontProject>? _cachedProjectList;
  static DateTime? _projectListCacheTime;
  static const Duration _projectListCacheTTL = Duration(seconds: 30);

  // ── 网络优化：单项目缓存（减少重复文件读取） ──
  static final Map<String, FontProject> _projectCache = {};

  /// Get the app's documents directory.
  static Future<Directory> get _documentsDir async {
    if (_cachedDocumentsDir != null) return _cachedDocumentsDir!;
    final dir = await getApplicationDocumentsDirectory();
    final writefontDir = Directory(p.join(dir.path, 'writefont'));
    if (!await writefontDir.exists()) {
      await writefontDir.create(recursive: true);
    }
    _cachedDocumentsDir = writefontDir;
    return writefontDir;
  }

  /// Get the projects directory.
  static Future<Directory> get _projectsDir async {
    if (_cachedProjectsDir != null) return _cachedProjectsDir!;
    final docs = await _documentsDir;
    final projDir = Directory(p.join(docs.path, 'projects'));
    if (!await projDir.exists()) {
      await projDir.create(recursive: true);
    }
    _cachedProjectsDir = projDir;
    return projDir;
  }

  /// Get the exports directory.
  static Future<Directory> get _exportsDir async {
    if (_cachedExportsDir != null) return _cachedExportsDir!;
    final docs = await _documentsDir;
    final expDir = Directory(p.join(docs.path, 'exports'));
    if (!await expDir.exists()) {
      await expDir.create(recursive: true);
    }
    _cachedExportsDir = expDir;
    return expDir;
  }

  /// Get the backup directory.
  static Future<Directory> get _backupDir async {
    if (_cachedBackupDir != null) return _cachedBackupDir!;
    final docs = await _documentsDir;
    final bakDir = Directory(p.join(docs.path, 'backups'));
    if (!await bakDir.exists()) {
      await bakDir.create(recursive: true);
    }
    _cachedBackupDir = bakDir;
    return bakDir;
  }

  /// Generate a unique project ID.
  static String generateId() => _uuid.v4();

  /// Save a source image for a project.
  static Future<String> saveSourceImage(String projectId, Uint8List imageBytes, int index) async {
    final projDir = await _projectsDir;
    final imgDir = Directory(p.join(projDir.path, projectId, 'images'));
    if (!await imgDir.exists()) {
      await imgDir.create(recursive: true);
    }
    final filePath = p.join(imgDir.path, 'source_$index.png');
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);
    return filePath;
  }

  /// Save a processed character image.
  static Future<String> saveCharacterImage(String projectId, String character, Uint8List imageBytes) async {
    final projDir = await _projectsDir;
    final charDir = Directory(p.join(projDir.path, projectId, 'characters'));
    if (!await charDir.exists()) {
      await charDir.create(recursive: true);
    }
    final codeUnit = character.codeUnitAt(0);
    final filePath = p.join(charDir.path, 'char_${codeUnit.toRadixString(16)}.png');
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);
    return filePath;
  }

  /// Build and export a TTF font file.
  /// Returns the file path of the exported font.
  ///
  /// 可选参数 [familyName] / [subfamilyName] / [version] / [copyright] / [description]
  /// 用于覆盖默认的字体元数据。
  static Future<String> exportTtf(
    FontProject project, {
    String? familyName,
    String? subfamilyName,
    String? version,
    String? copyright,
    String? description,
  }) async {
    final effectiveName = familyName ?? project.name;
    final expDir = await _exportsDir;
    final fileName = '${effectiveName.replaceAll(RegExp(r'[^\w]'), '_')}.ttf';
    final filePath = p.join(expDir.path, fileName);

    // Build the TTF with optional metadata
    final glyphs = project.glyphs.values.toList();
    final builder = TtfBuilder(
      glyphs: glyphs,
      familyName: project.name,
      unitsPerEm: 1000,
      customFamilyName: familyName,
      customSubfamilyName: subfamilyName,
      customVersion: version,
      customCopyright: copyright,
      customDescription: description,
    );

    final ttfBytes = builder.build();
    final file = File(filePath);
    await file.writeAsBytes(ttfBytes);

    return filePath;
  }

  /// Share a TTF file using the system share sheet.
  static Future<void> shareTtf(String filePath) async {
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: 'WriteFont 手写字体',
      text: '使用手迹造字生成的手写字体文件',
    );
  }

  /// Get the temporary directory for processing.
  static Future<Directory> get tempDir async {
    final dir = await getTemporaryDirectory();
    final tempDir = Directory(p.join(dir.path, 'writefont_temp'));
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return tempDir;
  }

  /// Clean up temporary files.
  static Future<void> cleanupTemp() async {
    try {
      final dir = await tempDir;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('清理临时文件失败: $e');
    }
  }

  // ============================================================
  // 项目持久化管理
  // ============================================================

  /// 保存项目到本地文件（JSON 格式）
  ///
  /// 每次保存时自动创建备份（最多保留 5 份，FIFO 淘汰）
  static Future<void> saveProject(FontProject project) async {
    // ── 自动备份（仅对已存在的项目创建备份）──
    await _autoBackup(project.id);

    final projDir = await _projectsDir;
    final projectDir = Directory(p.join(projDir.path, project.id));
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }

    // 更新修改时间
    project.updatedAt = DateTime.now();

    // 保存项目元数据 JSON
    final jsonFile = File(p.join(projectDir.path, 'project.json'));
    final jsonString = const JsonEncoder.withIndent('  ').convert(project.toJson());
    await jsonFile.writeAsString(jsonString);

    // 保存源图片
    for (int i = 0; i < project.sourceImages.length; i++) {
      await saveSourceImage(project.id, project.sourceImages[i], i);
    }

    // 网络优化：更新缓存（保存后缓存失效）
    _projectCache[project.id] = project;
    _cachedProjectList = null; // 使列表缓存失效
  }

  /// 自动备份：在覆盖前将现有 project.json 拷贝到 backup 目录
  static Future<void> _autoBackup(String projectId) async {
    try {
      final projDir = await _projectsDir;
      final jsonFile = File(p.join(projDir.path, projectId, 'project.json'));
      if (!await jsonFile.exists()) return; // 新项目，无需备份

      final bakDir = await _backupDir;
      final projectBakDir = Directory(p.join(bakDir.path, projectId));
      if (!await projectBakDir.exists()) {
        await projectBakDir.create(recursive: true);
      }

      // 使用时间戳命名备份文件
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final bakFile = File(p.join(projectBakDir.path, 'backup_$timestamp.json'));
      await jsonFile.copy(bakFile.path);

      // 清理旧备份，最多保留 5 份
      await _cleanOldBackups(projectBakDir);
    } catch (_) {
      // 备份失败不影响正常保存流程
    }
  }

  /// 清理旧备份，保留最新的 [maxCount] 份
  static Future<void> _cleanOldBackups(Directory projectBakDir, {int maxCount = 5}) async {
    final files = <FileSystemEntity>[];
    await for (final entity in projectBakDir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        files.add(entity);
      }
    }

    if (files.length <= maxCount) return;

    // 按修改时间排序（旧的在前）
    files.sort((a, b) {
      final aTime = a.statSync().modified;
      final bTime = b.statSync().modified;
      return aTime.compareTo(bTime);
    });

    // 删除多余的旧备份
    final toDelete = files.length - maxCount;
    for (int i = 0; i < toDelete; i++) {
      try {
        await files[i].delete();
      } catch (e) {
        debugPrint('删除旧备份失败: $e');
      }
    }
  }

  /// 从备份恢复项目
  ///
  /// [projectId] 要恢复的项目 ID
  /// 恢复最新一份备份并覆盖当前项目数据
  static Future<FontProject?> restoreFromBackup(String projectId) async {
    try {
      final bakDir = await _backupDir;
      final projectBakDir = Directory(p.join(bakDir.path, projectId));
      if (!await projectBakDir.exists()) return null;

      // 获取最新的备份文件
      final files = <FileSystemEntity>[];
      await for (final entity in projectBakDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          files.add(entity);
        }
      }
      if (files.isEmpty) return null;

      files.sort((a, b) {
        final aTime = a.statSync().modified;
        final bTime = b.statSync().modified;
        return bTime.compareTo(aTime); // 降序，最新的在前
      });

      final latestBak = files.first as File;
      final jsonString = await latestBak.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final project = FontProject.fromJson(json);

      // 用备份数据覆盖当前项目
      await saveProject(project);
      return project;
    } catch (_) {
      return null;
    }
  }

  /// 加载所有已保存的项目（仅加载元数据，不含源图片二进制）
  /// 网络优化：使用内存缓存，30秒内重复调用直接返回缓存结果
  static Future<List<FontProject>> loadProjects() async {
    // 检查缓存是否有效
    if (_cachedProjectList != null && _projectListCacheTime != null) {
      final elapsed = DateTime.now().difference(_projectListCacheTime!);
      if (elapsed < _projectListCacheTTL) {
        debugPrint('loadProjects: 命中缓存 (${elapsed.inSeconds}秒前)');
        return _cachedProjectList!;
      }
    }

    final projDir = await _projectsDir;
    final projects = <FontProject>[];

    if (!await projDir.exists()) return projects;

    await for (final entity in projDir.list()) {
      if (entity is Directory) {
        final jsonFile = File(p.join(entity.path, 'project.json'));
        if (await jsonFile.exists()) {
          try {
            final jsonString = await jsonFile.readAsString();
            final json = jsonDecode(jsonString) as Map<String, dynamic>;
            final project = FontProject.fromJson(json);
            projects.add(project);
          } catch (e) {
            // 跳过损坏的项目文件
            continue;
          }
        }
      }
    }

    // 按更新时间倒序排列
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    // 写入缓存
    _cachedProjectList = projects;
    _projectListCacheTime = DateTime.now();

    return projects;
  }

  /// 根据 ID 加载单个项目
  /// 网络优化：使用内存缓存减少重复文件读取
  static Future<FontProject?> loadProject(String id) async {
    // 检查单项目缓存
    if (_projectCache.containsKey(id)) {
      return _projectCache[id];
    }

    final projDir = await _projectsDir;
    final jsonFile = File(p.join(projDir.path, id, 'project.json'));

    if (!await jsonFile.exists()) return null;

    try {
      final jsonString = await jsonFile.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final project = FontProject.fromJson(json);
      _projectCache[id] = project; // 写入缓存
      return project;
    } catch (e) {
      return null;
    }
  }

  /// 删除项目
  static Future<void> deleteProject(String id) async {
    final projDir = await _projectsDir;
    final projectDir = Directory(p.join(projDir.path, id));
    if (await projectDir.exists()) {
      await projectDir.delete(recursive: true);
    }
    // 网络优化：清除缓存
    _projectCache.remove(id);
    _cachedProjectList = null;
  }

  /// 获取项目中某个字符的原始图片
  static Future<Uint8List?> loadCharacterImage(String projectId, String character) async {
    final projDir = await _projectsDir;
    final codeUnit = character.codeUnitAt(0);
    final filePath = p.join(
      projDir.path,
      projectId,
      'characters',
      'char_${codeUnit.toRadixString(16)}.png',
    );
    final file = File(filePath);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  /// 获取项目中某个字符的源图片（从源图片列表中的第一张裁切）
  static Future<Uint8List?> loadSourceImage(String projectId, int index) async {
    final projDir = await _projectsDir;
    final filePath = p.join(
      projDir.path,
      projectId,
      'images',
      'source_$index.png',
    );
    final file = File(filePath);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  // ============================================================
  // 项目导出/导入备份
  // ============================================================

  /// 将项目导出为 JSON 备份文件（含源图片 base64 编码）
  ///
  /// - 包含所有 glyph 数据（contours、metrics）
  /// - 包含处理参数（ProcessingParams）
  /// - 将 sourceImages 转为 base64 编码内嵌到 JSON
  /// - 文件名格式: {项目名}_backup.json
  ///
  /// 返回导出文件的完整路径
  static Future<String> exportProject(FontProject project) async {
    final expDir = await _exportsDir;
    final safeName = project.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final fileName = '${safeName}_backup.json';
    final filePath = p.join(expDir.path, fileName);

    // 构建导出 JSON（含 sourceImages 的 base64 编码）
    final exportJson = project.toJson();

    // 将源图片转为 base64 编码并嵌入 JSON
    final sourceImagesBase64 = <String>[];
    for (int i = 0; i < project.sourceImages.length; i++) {
      sourceImagesBase64.add(base64Encode(project.sourceImages[i]));
    }
    exportJson['sourceImagesBase64'] = sourceImagesBase64;

    final jsonString = const JsonEncoder.withIndent('  ').convert(exportJson);
    final file = File(filePath);
    await file.writeAsString(jsonString);

    return filePath;
  }

  /// 从 JSON 备份文件导入项目
  ///
  /// - 解析 JSON，重建 FontProject
  /// - 将 base64 编码的 sourceImages 还原为二进制
  /// - 保存到本地项目目录
  ///
  /// [jsonPath] JSON 备份文件的完整路径
  /// 返回导入的 FontProject，失败返回 null
  static Future<FontProject?> importProject(String jsonPath) async {
    try {
      final file = File(jsonPath);
      if (!await file.exists()) return null;

      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      return await importProjectFromJson(json);
    } catch (e) {
      return null;
    }
  }

  /// 从已解析的 JSON Map 导入项目（避免重复读取文件）
  ///
  /// [json] 已解析的项目 JSON 数据
  /// 返回导入的 FontProject，失败返回 null
  static Future<FontProject?> importProjectFromJson(Map<String, dynamic> json) async {
    try {
      // 重建 FontProject
      final project = FontProject.fromJson(json);

      // 还原 base64 编码的源图片
      final sourceImagesBase64 = json['sourceImagesBase64'] as List<dynamic>?;
      if (sourceImagesBase64 != null) {
        project.sourceImages = sourceImagesBase64
            .map((b64) => base64Decode(b64 as String))
            .toList();
      }

      // 为导入的项目生成新 ID（避免冲突）
      final newProject = FontProject(
        id: generateId(),
        name: project.name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        glyphs: project.glyphs,
        params: project.params,
        sourceImages: project.sourceImages,
      );

      // 保存到本地
      await saveProject(newProject);

      return newProject;
    } catch (e) {
      return null;
    }
  }
}
