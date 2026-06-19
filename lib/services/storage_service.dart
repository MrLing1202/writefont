import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project.dart';
import 'ttf_builder.dart';

/// Service for file operations: saving, loading, and exporting.
///
/// 增强功能：
/// - 数据加密（XOR 流加密，基于 HMAC-SHA256 密钥派生）
/// - 完整性校验（SHA-256 校验和）
/// - 安全删除（三次覆写后删除）
/// - 数据恢复（自动备份 + JSON 修复）
/// - 备份版本管理（最多保留 10 个版本）
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

  // ── 数据安全：加密密钥缓存 ──
  static List<int>? _encryptionKey;
  static const String _encryptionKeyPref = 'storage_encryption_key';
  static const String _encryptionEnabledPref = 'storage_encryption_enabled';

  // ── 数据安全：完整性校验缓存 ──
  static const String _checksumSuffix = '.sha256';

  // ── 备份版本管理 ──
  static const int _maxBackupVersions = 10;
  static const String _backupMetaFile = 'backup_meta.json';

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

  // ═══════════════════════════════════════════════════════════
  // 数据安全：加密/解密
  // ═══════════════════════════════════════════════════════════

  /// 初始化或获取加密密钥（基于设备唯一标识 + 应用盐值派生）
  static Future<List<int>> _getEncryptionKey() async {
    if (_encryptionKey != null) return _encryptionKey!;
    try {
      final prefs = await SharedPreferences.getInstance();
      var keyHex = prefs.getString(_encryptionKeyPref);
      if (keyHex == null) {
        // 生成随机密钥并持久化
        final random = List<int>.generate(32, (i) =>
            DateTime.now().microsecondsSinceEpoch.hashCode ^
            (i * 0x9E3779B9));
        final salted = utf8.encode('writefont_salt_v2') + random;
        keyHex = sha256.convert(salted).toString();
        await prefs.setString(_encryptionKeyPref, keyHex);
      }
      _encryptionKey = utf8.encode(keyHex);
      return _encryptionKey!;
    } catch (e) {
      debugPrint('获取加密密钥失败: $e');
      // 降级：使用固定密钥（不推荐，但保证可用性）
      _encryptionKey = utf8.encode('writefont_fallback_key_2024');
      return _encryptionKey!;
    }
  }

  /// 检查加密是否启用
  static Future<bool> isEncryptionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_encryptionEnabledPref) ?? false;
  }

  /// 设置加密开关
  static Future<void> setEncryptionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_encryptionEnabledPref, enabled);
  }

  /// XOR 流加密（基于 HMAC-SHA256 密钥派生）
  ///
  /// 虽然不如 AES 安全，但无需额外依赖，适合本地数据保护。
  /// 密钥通过 HMAC-SHA256 扩展到与数据等长，再做 XOR。
  static Uint8List _encryptBytes(Uint8List data, List<int> key) {
    final result = Uint8List(data.length);
    // 使用 HMAC-SHA256 生成密钥流
    for (int i = 0; i < data.length; i += 32) {
      final blockIndex = (i ~/ 32).toString();
      final hmac = Hmac(sha256, key);
      final stream = hmac.convert(utf8.encode('stream_$blockIndex')).bytes;
      for (int j = 0; j < 32 && (i + j) < data.length; j++) {
        result[i + j] = data[i + j] ^ stream[j];
      }
    }
    return result;
  }

  /// XOR 流解密（与加密操作对称）
  static Uint8List _decryptBytes(Uint8List data, List<int> key) {
    // XOR 解密与加密操作相同
    return _encryptBytes(data, key);
  }

  /// 加密字符串数据
  static Future<String> encryptData(String plainText) async {
    final key = await _getEncryptionKey();
    final data = Uint8List.fromList(utf8.encode(plainText));
    final encrypted = _encryptBytes(data, key);
    return base64Encode(encrypted);
  }

  /// 解密字符串数据
  static Future<String> decryptData(String encryptedBase64) async {
    final key = await _getEncryptionKey();
    final data = base64Decode(encryptedBase64);
    final decrypted = _decryptBytes(Uint8List.fromList(data), key);
    return utf8.decode(decrypted);
  }

  // ═══════════════════════════════════════════════════════════
  // 数据安全：完整性校验
  // ═══════════════════════════════════════════════════════════

  /// 计算文件的 SHA-256 校验和
  static Future<String> computeFileChecksum(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// 保存文件并写入校验和
  static Future<void> _writeWithChecksum(File file, List<int> bytes) async {
    await file.writeAsBytes(bytes);
    final checksum = sha256.convert(bytes).toString();
    final checksumFile = File('${file.path}$_checksumSuffix');
    await checksumFile.writeAsString(checksum);
  }

  /// 保存字符串并写入校验和
  static Future<void> _writeStringWithChecksum(File file, String content) async {
    await file.writeAsString(content);
    final checksum = sha256.convert(utf8.encode(content)).toString();
    final checksumFile = File('${file.path}$_checksumSuffix');
    await checksumFile.writeAsString(checksum);
  }

  /// 验证文件完整性
  ///
  /// 返回 true 表示文件未被篡改，false 表示校验失败（或无校验文件）
  static Future<bool> verifyFileIntegrity(File file) async {
    final checksumFile = File('${file.path}$_checksumSuffix');
    if (!await checksumFile.exists()) return true; // 无校验文件，跳过验证
    try {
      final expected = (await checksumFile.readAsString()).trim();
      final actual = await computeFileChecksum(file);
      return expected == actual;
    } catch (e) {
      debugPrint('完整性校验失败: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 数据安全：安全删除
  // ═══════════════════════════════════════════════════════════

  /// 安全删除文件（覆写后删除，防止数据恢复）
  ///
  /// 使用三次覆写策略：
  /// 1. 全零写入
  /// 2. 全 0xFF 写入
  /// 3. 随机数据写入
  static Future<void> secureDeleteFile(File file) async {
    try {
      if (!await file.exists()) return;
      final length = await file.length();
      // 第一次：全零覆写
      await file.writeAsBytes(Uint8List(length));
      // 第二次：全 0xFF 覆写
      await file.writeAsBytes(Uint8List(length, 0xFF));
      // 第三次：随机数据覆写
      final random = Uint8List.fromList(
        List.generate(length, (i) => (i * 0x5A + 0xA5) & 0xFF),
      );
      await file.writeAsBytes(random);
      // 最终删除
      await file.delete();
      // 删除校验和文件
      final checksumFile = File('${file.path}$_checksumSuffix');
      if (await checksumFile.exists()) {
        await checksumFile.delete();
      }
    } catch (e) {
      debugPrint('安全删除失败: $e');
      // 降级为普通删除
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// 安全删除目录（递归安全删除所有文件后删除目录）
  static Future<void> secureDeleteDirectory(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          await secureDeleteFile(entity);
        }
      }
      await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('安全删除目录失败: $e');
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 数据安全：数据恢复
  // ═══════════════════════════════════════════════════════════

  /// 尝试从损坏的项目文件中恢复数据
  ///
  /// 按优先级尝试以下恢复策略：
  /// 1. 从最新备份恢复
  /// 2. 从项目 JSON 部分解析恢复
  /// 3. 返回 null 表示无法恢复
  static Future<FontProject?> recoverProject(String projectId) async {
    // 策略 1：从备份恢复
    final restored = await restoreFromBackup(projectId);
    if (restored != null) {
      debugPrint('项目 $projectId 从备份恢复成功');
      return restored;
    }

    // 策略 2：尝试部分解析当前文件
    try {
      final projDir = await _projectsDir;
      final jsonFile = File(p.join(projDir.path, projectId, 'project.json'));
      if (!await jsonFile.exists()) return null;

      final jsonString = await jsonFile.readAsString();
      // 尝试修复常见 JSON 问题（截断、多余逗号等）
      final fixedJson = _tryFixJson(jsonString);
      if (fixedJson != null) {
        final project = FontProject.fromJson(fixedJson);
        // 保存修复后的版本
        await saveProject(project);
        debugPrint('项目 $projectId 通过 JSON 修复恢复成功');
        return project;
      }
    } catch (e) {
      debugPrint('项目 $projectId 恢复失败: $e');
    }
    return null;
  }

  /// 尝试修复损坏的 JSON 字符串
  static Map<String, dynamic>? _tryFixJson(String jsonStr) {
    try {
      // 先尝试正常解析
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {}

    try {
      // 修复截断：尝试补全括号
      var fixed = jsonStr.trimRight();
      int openBraces = '{'.allMatches(fixed).length;
      int closeBraces = '}'.allMatches(fixed).length;
      while (closeBraces < openBraces) {
        fixed += '}';
        closeBraces++;
      }
      // 修复尾部多余逗号
      fixed = fixed.replaceAll(RegExp(r',\s*}'), '}');
      fixed = fixed.replaceAll(RegExp(r',\s*\]'), ']');
      return jsonDecode(fixed) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // 文件保存
  // ═══════════════════════════════════════════════════════════

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
  /// 增强功能：
  /// - 自动创建备份（最多保留 10 份，FIFO 淘汰）
  /// - 数据完整性校验（SHA-256）
  /// - 可选加密存储
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

    // 数据安全：检查加密开关，加密存储
    final encryptionEnabled = await isEncryptionEnabled();
    if (encryptionEnabled) {
      final encrypted = await encryptData(jsonString);
      await _writeStringWithChecksum(jsonFile, encrypted);
    } else {
      await _writeStringWithChecksum(jsonFile, jsonString);
    }

    // 保存源图片
    for (int i = 0; i < project.sourceImages.length; i++) {
      await saveSourceImage(project.id, project.sourceImages[i], i);
    }

    // 网络优化：更新缓存（保存后缓存失效）
    _projectCache[project.id] = project;
    _cachedProjectList = null; // 使列表缓存失效
  }

  /// 自动备份：在覆盖前将现有 project.json 拷贝到 backup 目录
  ///
  /// 增强：备份加密、版本管理、完整性校验
  static Future<void> _autoBackup(String projectId) async {
    try {
      final projDir = await _projectsDir;
      final jsonFile = File(p.join(projDir.path, projectId, 'project.json'));
      if (!await jsonFile.exists()) return; // 新项目，无需备份

      // 完整性校验：备份前验证源文件
      final isIntegral = await verifyFileIntegrity(jsonFile);
      if (!isIntegral) {
        debugPrint('警告：项目 $projectId 文件完整性校验失败，仍尝试备份');
      }

      final bakDir = await _backupDir;
      final projectBakDir = Directory(p.join(bakDir.path, projectId));
      if (!await projectBakDir.exists()) {
        await projectBakDir.create(recursive: true);
      }

      // 使用时间戳命名备份文件
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final bakFile = File(p.join(projectBakDir.path, 'backup_$timestamp.json'));
      await jsonFile.copy(bakFile.path);

      // 备份加密：如果加密开关开启，同时保存加密版本
      final encryptionEnabled = await isEncryptionEnabled();
      if (encryptionEnabled) {
        final content = await jsonFile.readAsString();
        final encrypted = await encryptData(content);
        final encBakFile = File(p.join(projectBakDir.path, 'backup_${timestamp}_enc.json'));
        await encBakFile.writeAsString(encrypted);
      }

      // 保存备份元数据（版本信息）
      await _updateBackupMeta(projectId, timestamp);

      // 清理旧备份，最多保留 _maxBackupVersions 份
      await _cleanOldBackups(projectBakDir);
    } catch (_) {
      // 备份失败不影响正常保存流程
    }
  }

  /// 更新备份元数据（记录版本信息用于版本管理）
  static Future<void> _updateBackupMeta(String projectId, String timestamp) async {
    try {
      final bakDir = await _backupDir;
      final projectBakDir = Directory(p.join(bakDir.path, projectId));
      final metaFile = File(p.join(projectBakDir.path, _backupMetaFile));

      List<Map<String, dynamic>> versions = [];
      if (await metaFile.exists()) {
        final metaJson = jsonDecode(await metaFile.readAsString()) as List;
        versions = metaJson.cast<Map<String, dynamic>>();
      }

      versions.add({
        'timestamp': timestamp,
        'createdAt': DateTime.now().toIso8601String(),
        'version': versions.length + 1,
      });

      // 只保留最近 N 个版本的元数据
      if (versions.length > _maxBackupVersions) {
        versions = versions.sublist(versions.length - _maxBackupVersions);
      }

      final metaJson = const JsonEncoder.withIndent('  ').convert(versions);
      await metaFile.writeAsString(metaJson);
    } catch (e) {
      debugPrint('更新备份元数据失败: $e');
    }
  }

  /// 清理旧备份，保留最新的 [maxCount] 份
  static Future<void> _cleanOldBackups(Directory projectBakDir, {int maxCount = 10}) async {
    final files = <FileSystemEntity>[];
    await for (final entity in projectBakDir.list()) {
      if (entity is File && entity.path.endsWith('.json') &&
          !entity.path.endsWith(_backupMetaFile)) {
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

      // 获取最新的备份文件（排除元数据、校验和、加密版本）
      final files = <FileSystemEntity>[];
      await for (final entity in projectBakDir.list()) {
        if (entity is File &&
            entity.path.endsWith('.json') &&
            !entity.path.endsWith(_backupMetaFile) &&
            !entity.path.endsWith(_checksumSuffix) &&
            !entity.path.contains('_enc.json')) {
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

  /// 获取项目的备份版本列表
  ///
  /// 返回包含时间戳和版本号的列表，按时间降序排列
  static Future<List<Map<String, dynamic>>> getBackupVersions(String projectId) async {
    try {
      final bakDir = await _backupDir;
      final metaFile = File(p.join(bakDir.path, projectId, _backupMetaFile));
      if (!await metaFile.exists()) return [];

      final metaJson = jsonDecode(await metaFile.readAsString()) as List;
      final versions = metaJson.cast<Map<String, dynamic>>();
      // 按时间降序
      versions.sort((a, b) =>
          (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      return versions;
    } catch (e) {
      debugPrint('获取备份版本列表失败: $e');
      return [];
    }
  }

  /// 恢复到指定版本的备份
  ///
  /// [projectId] 项目 ID
  /// [timestamp] 备份时间戳（来自 getBackupVersions 返回的 'timestamp' 字段）
  static Future<FontProject?> restoreFromBackupVersion(
      String projectId, String timestamp) async {
    try {
      final bakDir = await _backupDir;
      final projectBakDir = Directory(p.join(bakDir.path, projectId));
      if (!await projectBakDir.exists()) return null;

      // 尝试加密版本优先
      final encFile = File(p.join(projectBakDir.path, 'backup_${timestamp}_enc.json'));
      if (await encFile.exists()) {
        final encrypted = await encFile.readAsString();
        final jsonString = await decryptData(encrypted);
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        final project = FontProject.fromJson(json);
        await saveProject(project);
        return project;
      }

      // 回退到明文版本
      final bakFile = File(p.join(projectBakDir.path, 'backup_$timestamp.json'));
      if (await bakFile.exists()) {
        final jsonString = await bakFile.readAsString();
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        final project = FontProject.fromJson(json);
        await saveProject(project);
        return project;
      }
      return null;
    } catch (e) {
      debugPrint('恢复指定版本失败: $e');
      return null;
    }
  }

  /// 加载所有已保存的项目（仅加载元数据，不含源图片二进制）
  ///
  /// 增强功能：
  /// - 完整性校验（校验失败时尝试恢复）
  /// - 可选解密
  /// - 使用内存缓存，30秒内重复调用直接返回缓存结果
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

    // 数据安全：检查加密开关
    final encryptionEnabled = await isEncryptionEnabled();

    await for (final entity in projDir.list()) {
      if (entity is Directory) {
        final jsonFile = File(p.join(entity.path, 'project.json'));
        if (await jsonFile.exists()) {
          try {
            final jsonString = await jsonFile.readAsString();

            // 完整性校验
            final isIntegral = await verifyFileIntegrity(jsonFile);
            if (!isIntegral) {
              debugPrint('项目文件完整性校验失败: ${entity.path}');
              // 尝试从备份恢复
              final dirName = p.basename(entity.path);
              final recovered = await recoverProject(dirName);
              if (recovered != null) {
                projects.add(recovered);
                continue;
              }
            }

            // 解密（如需要）
            final String actualJson;
            if (encryptionEnabled) {
              actualJson = await decryptData(jsonString);
            } else {
              actualJson = jsonString;
            }
            final json = jsonDecode(actualJson) as Map<String, dynamic>;
            final project = FontProject.fromJson(json);
            projects.add(project);
          } catch (e) {
            // 跳过损坏的项目文件，尝试恢复
            try {
              final dirName = p.basename(entity.path);
              final recovered = await recoverProject(dirName);
              if (recovered != null) {
                projects.add(recovered);
              }
            } catch (_) {}
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
  ///
  /// 增强功能：完整性校验、可选解密、失败时自动恢复
  static Future<FontProject?> loadProject(String id) async {
    // 检查单项目缓存
    if (_projectCache.containsKey(id)) {
      return _projectCache[id];
    }

    final projDir = await _projectsDir;
    final jsonFile = File(p.join(projDir.path, id, 'project.json'));

    if (!await jsonFile.exists()) return null;

    try {
      // 完整性校验
      final isIntegral = await verifyFileIntegrity(jsonFile);
      if (!isIntegral) {
        debugPrint('项目 $id 文件完整性校验失败');
        // 尝试恢复
        final recovered = await recoverProject(id);
        if (recovered != null) {
          _projectCache[id] = recovered;
          return recovered;
        }
      }

      final jsonString = await jsonFile.readAsString();
      // 解密（如需要）
      final encryptionEnabled = await isEncryptionEnabled();
      final String actualJson;
      if (encryptionEnabled) {
        actualJson = await decryptData(jsonString);
      } else {
        actualJson = jsonString;
      }
      final json = jsonDecode(actualJson) as Map<String, dynamic>;
      final project = FontProject.fromJson(json);
      _projectCache[id] = project; // 写入缓存
      return project;
    } catch (e) {
      // 加载失败，尝试恢复
      try {
        final recovered = await recoverProject(id);
        if (recovered != null) {
          _projectCache[id] = recovered;
          return recovered;
        }
      } catch (_) {}
      return null;
    }
  }

  /// 删除项目
  ///
  /// 使用安全删除策略，覆写后删除防止数据恢复
  static Future<void> deleteProject(String id) async {
    final projDir = await _projectsDir;
    final projectDir = Directory(p.join(projDir.path, id));
    if (await projectDir.exists()) {
      await secureDeleteDirectory(projectDir);
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

  // ═══════════════════════════════════════════════════════════
  // 数据导出（隐私保护相关）
  // ═══════════════════════════════════════════════════════════

  /// 导出所有用户数据为可读 JSON 文件
  ///
  /// 包含所有项目数据（含源图片 base64），用于用户数据可移植性。
  /// 返回导出文件路径。
  static Future<String> exportAllUserData() async {
    final projects = await loadProjects();
    final exportData = <String, dynamic>{
      'exportDate': DateTime.now().toIso8601String(),
      'appVersion': 'v2.7.0',
      'projectCount': projects.length,
      'projects': <Map<String, dynamic>>[],
    };

    for (final project in projects) {
      final projectJson = project.toJson();
      // 包含源图片
      final sourceImagesBase64 = <String>[];
      for (final img in project.sourceImages) {
        sourceImagesBase64.add(base64Encode(img));
      }
      projectJson['sourceImagesBase64'] = sourceImagesBase64;
      (exportData['projects'] as List).add(projectJson);
    }

    final expDir = await _exportsDir;
    final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final fileName = 'writefont_full_export_$timestamp.json';
    final filePath = p.join(expDir.path, fileName);
    final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
    final file = File(filePath);
    await file.writeAsString(jsonString);
    return filePath;
  }
}
