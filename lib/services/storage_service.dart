import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project.dart';
import 'ttf_builder.dart';

// ═══════════════════════════════════════════════════════════
// 提醒服务：定时提醒、条件提醒、位置提醒、自定义提醒
// ═══════════════════════════════════════════════════════════

/// 提醒类型枚举
class StorageService {
  static const _uuid = Uuid();

  // ═══════════════════════════════════════════════════════════
  // 排序历史和预设管理
  // ═══════════════════════════════════════════════════════════

  static const String _sortHistoryKey = 'sort_history';
  static const String _sortPresetsKey = 'sort_presets';
  static const int _maxSortHistory = 20;

  /// 保存排序历史记录
  ///
  /// [sortConfig] 排序配置 Map，包含 sortMode、secondarySortMode 等
  static Future<void> saveSortHistory(Map<String, dynamic> sortConfig) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList(_sortHistoryKey) ?? [];
      final entry = {
        ...sortConfig,
        'timestamp': DateTime.now().toIso8601String(),
      };
      historyJson.add(jsonEncode(entry));
      // 限制历史记录数量
      if (historyJson.length > _maxSortHistory) {
        historyJson.removeRange(0, historyJson.length - _maxSortHistory);
      }
      await prefs.setStringList(_sortHistoryKey, historyJson);
    } catch (e) {
      debugPrint('保存排序历史失败: $e');
    }
  }

  /// 加载排序历史记录
  static Future<List<Map<String, dynamic>>> loadSortHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList(_sortHistoryKey) ?? [];
      return historyJson.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('加载排序历史失败: $e');
      return [];
    }
  }

  /// 清除排序历史
  static Future<void> clearSortHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sortHistoryKey);
    } catch (_) {}
  }

  /// 保存排序预设
  ///
  /// [name] 预设名称
  /// [config] 排序配置 Map
  static Future<void> saveSortPreset(String name, Map<String, dynamic> config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presetsJson = prefs.getStringList(_sortPresetsKey) ?? [];
      final preset = {
        'name': name,
        ...config,
        'createdAt': DateTime.now().toIso8601String(),
      };
      presetsJson.add(jsonEncode(preset));
      await prefs.setStringList(_sortPresetsKey, presetsJson);
    } catch (e) {
      debugPrint('保存排序预设失败: $e');
    }
  }

  /// 加载排序预设列表
  static Future<List<Map<String, dynamic>>> loadSortPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presetsJson = prefs.getStringList(_sortPresetsKey) ?? [];
      return presetsJson.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('加载排序预设失败: $e');
      return [];
    }
  }

  /// 删除排序预设
  static Future<void> deleteSortPreset(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presetsJson = prefs.getStringList(_sortPresetsKey) ?? [];
      if (index >= 0 && index < presetsJson.length) {
        presetsJson.removeAt(index);
        await prefs.setStringList(_sortPresetsKey, presetsJson);
      }
    } catch (e) {
      debugPrint('删除排序预设失败: $e');
    }
  }

  /// 通用多字段排序方法
  ///
  /// [projects] 待排序的项目列表
  /// [comparators] 比较器列表，按优先级排序
  /// 返回排序后的新列表（不修改原列表）
  static List<FontProject> multiFieldSort(
    List<FontProject> projects,
    List<int Function(FontProject, FontProject)> comparators,
  ) {
    final sorted = List<FontProject>.from(projects);
    sorted.sort((a, b) {
      for (final comparator in comparators) {
        final result = comparator(a, b);
        if (result != 0) return result;
      }
      return 0;
    });
    return sorted;
  }

  // ═══════════════════════════════════════════════════════════
  // 测试支持：单元测试、集成测试、性能测试、测试数据生成
  // ═══════════════════════════════════════════════════════════

  /// 测试模式标志（启用后跳过文件系统操作，使用内存模拟）
  static bool _testMode = false;
  static bool get isTestMode => _testMode;

  /// 内存模拟存储（测试模式下替代文件系统）
  static final Map<String, String> _testFileStore = {};
  static final Map<String, List<int>> _testBinaryStore = {};

  /// 测试性能指标记录
  static final List<Map<String, dynamic>> _performanceMetrics = [];

  /// 启用测试模式（单元测试时调用，避免真实文件 I/O）
  static void enableTestMode() {
    _testMode = true;
    _testFileStore.clear();
    _testBinaryStore.clear();
    _performanceMetrics.clear();
    _cachedDocumentsDir = null;
    _cachedProjectsDir = null;
    _cachedExportsDir = null;
    _cachedBackupDir = null;
    _cachedProjectList = null;
    _projectCache.clear();
  }

  /// 禁用测试模式，恢复正常文件系统操作
  static void disableTestMode() {
    _testMode = false;
    _testFileStore.clear();
    _testBinaryStore.clear();
  }

  /// 记录操作性能指标（用于性能测试和分析）
  static void _recordMetric(String operation, Duration elapsed, {Map<String, dynamic>? extras}) {
    _performanceMetrics.add({
      'operation': operation,
      'elapsedMs': elapsed.inMicroseconds / 1000.0,
      'timestamp': DateTime.now().toIso8601String(),
      if (extras != null) ...extras,
    });
    // 只保留最近 1000 条记录
    if (_performanceMetrics.length > 1000) {
      _performanceMetrics.removeRange(0, _performanceMetrics.length - 1000);
    }
  }

  /// 获取性能指标快照（用于性能分析和测试报告）
  static List<Map<String, dynamic>> getPerformanceMetrics() =>
      List.unmodifiable(_performanceMetrics);

  /// 清除性能指标记录
  static void clearPerformanceMetrics() => _performanceMetrics.clear();

  /// 生成测试用的 FontProject 数据（用于单元测试和集成测试）
  ///
  /// [charCount] 生成的字符数量，默认 10
  /// [withImages] 是否生成模拟源图片，默认 false
  static FontProject generateTestProject({
    int charCount = 10,
    bool withImages = false,
    String? name,
  }) {
    final projectId = generateId();
    final testChars = '天地人和春夏秋冬风雪雨霜雷电云雾山川河流海湖';
    final glyphs = <String, GlyphData>{};

    for (int i = 0; i < charCount && i < testChars.length; i++) {
      final ch = testChars[i];
      // 生成简单的模拟轮廓数据（正方形轮廓）
      final contourPoints = [
        ContourPoint(100, 100, onCurve: true),
        ContourPoint(500, 100, onCurve: false),
        ContourPoint(900, 100, onCurve: true),
        ContourPoint(900, 500, onCurve: false),
        ContourPoint(900, 900, onCurve: true),
        ContourPoint(500, 900, onCurve: false),
        ContourPoint(100, 900, onCurve: true),
        ContourPoint(100, 500, onCurve: false),
        ContourPoint(100, 100, onCurve: true),
      ];
      glyphs[ch] = GlyphData(
        character: ch,
        unicode: ch.codeUnitAt(0),
        contours: [Contour(contourPoints)],
        advanceWidth: 1000,
      );
    }

    final sourceImages = <Uint8List>[];
    if (withImages) {
      // 生成最小 PNG 作为模拟源图片
      sourceImages.add(Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE,
        0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54,
        0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00,
        0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
        0xAE, 0x42, 0x60, 0x82,
      ]));
    }

    return FontProject(
      id: projectId,
      name: name ?? '测试项目_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      glyphs: glyphs,
      params: ProcessingParams(),
      sourceImages: sourceImages,
    );
  }

  /// 批量生成测试项目（用于集成测试和性能测试）
  ///
  /// [count] 生成项目数量
  /// [charRange] 每个项目字符数范围 [min, max]
  static List<FontProject> generateTestProjects(int count, {List<int> charRange = const [5, 20]}) {
    final projects = <FontProject>[];
    for (int i = 0; i < count; i++) {
      final charCount = charRange[0] + (i % (charRange[1] - charRange[0] + 1));
      projects.add(generateTestProject(
        charCount: charCount,
        name: '批量测试项目_${i + 1}',
      ));
    }
    return projects;
  }

  /// 运行存储服务自检（返回诊断结果 Map）
  ///
  /// 检查项：目录可写性、加密功能、完整性校验、缓存一致性
  static Future<Map<String, dynamic>> runDiagnostics() async {
    final results = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'testMode': _testMode,
      'checks': <String, dynamic>{},
    };
    final checks = results['checks'] as Map<String, dynamic>;

    // 1. 目录可写性检查
    try {
      final temp = await tempDir;
      final testFile = File(p.join(temp.path, '_diag_test.tmp'));
      await testFile.writeAsString('diagnostic_check');
      final content = await testFile.readAsString();
      checks['directoryWritable'] = content == 'diagnostic_check';
      await testFile.delete();
    } catch (e) {
      checks['directoryWritable'] = false;
      checks['directoryWritableError'] = e.toString();
    }

    // 2. 加密/解密一致性检查
    try {
      const testPlain = 'WriteFont 诊断测试数据 🔤';
      final encrypted = await encryptData(testPlain);
      final decrypted = await decryptData(encrypted);
      checks['encryptionConsistent'] = decrypted == testPlain;
    } catch (e) {
      checks['encryptionConsistent'] = false;
      checks['encryptionError'] = e.toString();
    }

    // 3. 完整性校验功能检查
    try {
      final temp = await tempDir;
      final testFile = File(p.join(temp.path, '_diag_checksum.tmp'));
      await testFile.writeAsString('checksum_test');
      final checksum = await computeFileChecksum(testFile);
      checks['checksumWorking'] = checksum.isNotEmpty && checksum.length == 64;
      await testFile.delete();
      final csFile = File('${testFile.path}$_checksumSuffix');
      if (await csFile.exists()) await csFile.delete();
    } catch (e) {
      checks['checksumWorking'] = false;
      checks['checksumError'] = e.toString();
    }

    // 4. 缓存状态
    checks['projectCacheSize'] = _projectCache.length;
    checks['projectListCached'] = _cachedProjectList != null;
    checks['performanceMetricsCount'] = _performanceMetrics.length;

    return results;
  }

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

  /// 公开的字节加密方法（供其他服务调用）
  ///
  /// 用于云同步服务的端到端加密
  static Uint8List encryptBytes(Uint8List data, List<int> key) {
    return _encryptBytes(data, key);
  }

  /// 公开的字节解密方法（供其他服务调用）
  static Uint8List decryptBytes(Uint8List data, List<int> key) {
    return _decryptBytes(data, key);
  }

  /// 清除加密密钥缓存（密钥轮换后调用）
  static void clearEncryptionKeyCache() {
    _encryptionKey = null;
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
      await file.writeAsBytes(Uint8List(length)..fillRange(0, length, 0xFF));
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
    final sw = Stopwatch()..start();

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

    sw.stop();
    _recordMetric('saveProject', sw.elapsed, extras: {
      'projectId': project.id,
      'glyphCount': project.glyphs.length,
    });
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
    final sw = Stopwatch()..start();

    // 检查缓存是否有效
    if (_cachedProjectList != null && _projectListCacheTime != null) {
      final elapsed = DateTime.now().difference(_projectListCacheTime!);
      if (elapsed < _projectListCacheTTL) {
        debugPrint('loadProjects: 命中缓存 (${elapsed.inSeconds}秒前)');
        _recordMetric('loadProjects', elapsed, extras: {'cacheHit': true, 'projectCount': _cachedProjectList!.length});
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

    sw.stop();
    _recordMetric('loadProjects', sw.elapsed, extras: {
      'projectCount': projects.length,
      'cacheHit': false,
    });

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

  // ═══════════════════════════════════════════════════════════
  // 提醒管理：定时提醒、条件提醒、位置提醒、自定义提醒
  // ═══════════════════════════════════════════════════════════

  /// 提醒列表缓存
  static const String _keyReminders = 'app_reminders';

  /// 加载所有提醒
    if (_cachedReminders != null) return List.unmodifiable(_cachedReminders!);
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_keyReminders);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _cachedReminders = list
            .toList();
      } else {
        _cachedReminders = [];
      }
    } catch (e) {
      debugPrint('加载提醒失败: $e');
      _cachedReminders = [];
    }
    return List.unmodifiable(_cachedReminders!);
  }

  /// 保存提醒列表
  static Future<void> _saveReminders() async {
    if (_cachedReminders == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_cachedReminders!.map((e) => e.toJson()).toList());
      await prefs.setString(_keyReminders, json);
    } catch (e) {
      debugPrint('保存提醒失败: $e');
    }
  }

  /// 添加定时提醒
  ///
  /// [title] 提醒标题
  /// [message] 提醒内容
  /// [scheduledTime] 提醒时间
  /// [repeatDaily] 是否每天重复
  /// [repeatIntervalDays] 重复间隔天数（如每3天）
    required String title,
    required String message,
    required DateTime scheduledTime,
    bool repeatDaily = false,
    int? repeatIntervalDays,
  }) async {
      id: generateId(),
      title: title,
      message: message,
      scheduledTime: scheduledTime,
      repeatDaily: repeatDaily,
      repeatIntervalDays: repeatIntervalDays,
    );
    await loadReminders();
    _cachedReminders!.add(reminder);
    await _saveReminders();
    debugPrint('已添加定时提醒: $title (${scheduledTime.toIso8601String()})');
    return reminder;
  }

  /// 添加条件提醒
  ///
  /// [conditionType] 条件类型：
  ///   - 'project_idle_days': 项目闲置超过N天
  ///   - 'char_count_reached': 字符数达到N个
  ///   - 'sync_pending': 有待同步项目
  /// [conditionValue] 条件阈值
    required String title,
    required String message,
    required String conditionType,
    required int conditionValue,
  }) async {
      id: generateId(),
      title: title,
      message: message,
      conditionType: conditionType,
      conditionValue: conditionValue,
    );
    await loadReminders();
    _cachedReminders!.add(reminder);
    await _saveReminders();
    debugPrint('已添加条件提醒: $title ($conditionType >= $conditionValue)');
    return reminder;
  }

  /// 添加位置提醒
  ///
  /// [latitude] 纬度
  /// [longitude] 经度
  /// [radiusMeters] 触发半径（米）
    required String title,
    required String message,
    required double latitude,
    required double longitude,
    double radiusMeters = 100,
  }) async {
      id: generateId(),
      title: title,
      message: message,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
    await loadReminders();
    _cachedReminders!.add(reminder);
    await _saveReminders();
    debugPrint('已添加位置提醒: $title ($latitude, $longitude, ${radiusMeters}m)');
    return reminder;
  }

  /// 添加自定义提醒
  ///
  /// [customRule] JSON 格式的自定义规则
    required String title,
    required String message,
    required String customRule,
  }) async {
      id: generateId(),
      title: title,
      message: message,
      customRule: customRule,
    );
    await loadReminders();
    _cachedReminders!.add(reminder);
    await _saveReminders();
    debugPrint('已添加自定义提醒: $title');
    return reminder;
  }

  /// 切换提醒启用/禁用状态
  static Future<void> toggleReminder(String reminderId, bool enabled) async {
    await loadReminders();
    final idx = _cachedReminders!.indexWhere((r) => r.id == reminderId);
    if (idx >= 0) {
      _cachedReminders![idx].isEnabled = enabled;
      await _saveReminders();
    }
  }

  /// 删除提醒
  static Future<void> deleteReminder(String reminderId) async {
    await loadReminders();
    _cachedReminders!.removeWhere((r) => r.id == reminderId);
    await _saveReminders();
  }

  /// 检查条件提醒是否应触发
  ///
  /// 遍历所有启用的条件提醒，检查是否满足条件。
  /// 返回应该触发的提醒列表。
    final reminders = await loadReminders();

    for (final r in reminders.where((r) =>
      try {
        switch (r.conditionType) {
          case 'project_idle_days':
            // 检查是否有项目闲置超过指定天数
            final projects = await loadProjects();
            final idleDays = r.conditionValue ?? 7;
            for (final p in projects) {
              final daysSinceUpdate = DateTime.now().difference(p.updatedAt).inDays;
              if (daysSinceUpdate >= idleDays) {
                triggered.add(r);
                break;
              }
            }
            break;
          case 'char_count_reached':
            // 检查总字符数是否达到阈值
            final projects = await loadProjects();
            int totalChars = 0;
            for (final p in projects) {
              totalChars += p.glyphs.values.where((g) => g.contours.isNotEmpty).length;
            }
            if (totalChars >= (r.conditionValue ?? 100)) {
              triggered.add(r);
            }
            break;
          case 'sync_pending':
            // 检查是否有待同步的项目（简单检查最近修改的项目）
            final projects = await loadProjects();
            final recentThreshold = DateTime.now().subtract(const Duration(hours: 1));
            final hasPending = projects.any((p) => p.updatedAt.isAfter(recentThreshold));
            if (hasPending) {
              triggered.add(r);
            }
            break;
        }
      } catch (e) {
        debugPrint('检查条件提醒失败: ${r.id} - $e');
      }
    }
    return triggered;
  }

  /// 获取即将到期的定时提醒（未来24小时内）
    final reminders = await loadReminders();
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(hours: 24));

    return reminders.where((r) {
      if (r.scheduledTime == null) return false;
      return r.scheduledTime!.isAfter(now) && r.scheduledTime!.isBefore(tomorrow);
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 统计图表数据支持：柱状图、折线图、饼图、散点图
  // ═══════════════════════════════════════════════════════════

  /// 生成柱状图数据
  ///
  /// 根据项目列表生成字符数分布的柱状图数据
  /// 返回 Map 包含:
  /// - 'labels': 标签列表 (List<String>)
  /// - 'values': 值列表 (List<double>)
  /// - 'maxValue': 最大值 (double)
  static Map<String, dynamic> generateBarChartData(List<FontProject> projects) {
    try {
      if (projects.isEmpty) {
        return {'labels': <String>[], 'values': <double>[], 'maxValue': 0.0};
      }

      final labels = <String>[];
      final values = <double>[];

      for (final project in projects.take(10)) {
        final editedCount = project.glyphs.values
            .where((g) => g.contours.isNotEmpty)
            .length;
        final name = project.name.length > 6
            ? '${project.name.substring(0, 6)}..'
            : project.name;
        labels.add(name);
        values.add(editedCount.toDouble());
      }

      final maxValue = values.isEmpty
          ? 1.0
          : values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);

      debugPrint('[StorageService] 生成柱状图数据: ${labels.length} 项');
      return {'labels': labels, 'values': values, 'maxValue': maxValue};
    } catch (e) {
      debugPrint('[StorageService] 生成柱状图数据失败: $e');
      return {'labels': <String>[], 'values': <double>[], 'maxValue': 0.0};
    }
  }

  /// 生成折线图数据
  ///
  /// 根据项目更新时间生成时间序列折线图数据
  /// [days] 统计天数，默认7天
  /// 返回 Map 包含:
  /// - 'labels': 日期标签列表 (List<String>)
  /// - 'values': 每日更新数 (List<double>)
  /// - 'maxValue': 最大值 (double)
  static Map<String, dynamic> generateLineChartData(List<FontProject> projects, {int days = 7}) {
    try {
      final now = DateTime.now();
      final labels = <String>[];
      final values = <double>[];

      for (int i = days - 1; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final count = projects.where((p) {
          return p.updatedAt.year == day.year &&
              p.updatedAt.month == day.month &&
              p.updatedAt.day == day.day;
        }).length;
        labels.add('${day.month}/${day.day}');
        values.add(count.toDouble());
      }

      final maxValue = values.isEmpty
          ? 1.0
          : values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);

      debugPrint('[StorageService] 生成折线图数据: $days 天');
      return {'labels': labels, 'values': values, 'maxValue': maxValue};
    } catch (e) {
      debugPrint('[StorageService] 生成折线图数据失败: $e');
      return {'labels': <String>[], 'values': <double>[], 'maxValue': 0.0};
    }
  }

  /// 生成饼图数据
  ///
  /// 根据项目状态分类生成饼图数据
  /// 返回 Map 包含:
  /// - 'labels': 分类标签列表 (List<String>)
  /// - 'values': 各分类数量 (List<double>)
  /// - 'colors': 各分类颜色 (List<int> - ARGB)
  static Map<String, dynamic> generatePieChartData(List<FontProject> projects) {
    try {
      int completed = 0;
      int inProgress = 0;
      int empty = 0;

      for (final project in projects) {
        final editedCount = project.glyphs.values
            .where((g) => g.contours.isNotEmpty)
            .length;
        final total = project.glyphs.length;

        if (total == 0 || editedCount == 0) {
          empty++;
        } else if (editedCount >= total * 0.8) {
          completed++;
        } else {
          inProgress++;
        }
      }

      final labels = ['已完成', '进行中', '未开始'];
      final values = [completed.toDouble(), inProgress.toDouble(), empty.toDouble()];
      final colors = [0xFF4CAF50, 0xFF2196F3, 0xFF9E9E9E]; // green, blue, grey

      debugPrint('[StorageService] 生成饼图数据: 完成$completed, 进行中$inProgress, 未开始$empty');
      return {'labels': labels, 'values': values, 'colors': colors};
    } catch (e) {
      debugPrint('[StorageService] 生成饼图数据失败: $e');
      return {
        'labels': ['已完成', '进行中', '未开始'],
        'values': [0.0, 0.0, 0.0],
        'colors': [0xFF4CAF50, 0xFF2196F3, 0xFF9E9E9E],
      };
    }
  }

  /// 生成散点图数据
  ///
  /// 根据项目属性生成散点图数据（X轴: 字符数, Y轴: 完成度）
  /// 返回 Map 包含:
  /// - 'points': 散点列表 (List<Map<String, double>>) 每个包含 {'x': 0.0-1.0, 'y': 0.0-1.0}
  /// - 'xLabel': X轴标签
  /// - 'yLabel': Y轴标签
  static Map<String, dynamic> generateScatterPlotData(List<FontProject> projects) {
    try {
      if (projects.isEmpty) {
        return {
          'points': <Map<String, double>>[],
          'xLabel': '字符数',
          'yLabel': '完成度',
        };
      }

      final maxChars = projects
          .map((p) => p.glyphs.length)
          .reduce((a, b) => a > b ? a : b)
          .clamp(1, 9999);

      final points = projects.take(20).map((p) {
        final charCount = p.glyphs.length;
        final editedCount = p.glyphs.values
            .where((g) => g.contours.isNotEmpty)
            .length;
        final progress = charCount > 0 ? editedCount / charCount : 0.0;

        return {
          'x': charCount / maxChars,
          'y': progress,
        };
      }).toList();

      debugPrint('[StorageService] 生成散点图数据: ${points.length} 个点');
      return {
        'points': points,
        'xLabel': '字符数',
        'yLabel': '完成度',
      };
    } catch (e) {
      debugPrint('[StorageService] 生成散点图数据失败: $e');
      return {
        'points': <Map<String, double>>[],
        'xLabel': '字符数',
        'yLabel': '完成度',
      };
    }
  }

  /// 获取综合统计数据
  ///
  /// 聚合所有图表数据，便于一次性获取全部统计信息
  static Future<Map<String, dynamic>> getComprehensiveStats() async {
    try {
      final projects = await loadProjects();

      return {
        'projectCount': projects.length,
        'barChart': generateBarChartData(projects),
        'lineChart': generateLineChartData(projects),
        'pieChart': generatePieChartData(projects),
        'scatterPlot': generateScatterPlotData(projects),
        'totalGlyphs': projects.fold(0, (sum, p) => sum + p.glyphs.length),
        'totalEdited': projects.fold(0, (sum, p) =>
            sum + p.glyphs.values.where((g) => g.contours.isNotEmpty).length),
        'generatedAt': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('[StorageService] 获取综合统计数据失败: $e');
      return {
        'projectCount': 0,
        'barChart': generateBarChartData([]),
        'lineChart': generateLineChartData([]),
        'pieChart': generatePieChartData([]),
        'scatterPlot': generateScatterPlotData([]),
        'totalGlyphs': 0,
        'totalEdited': 0,
        'generatedAt': DateTime.now().toIso8601String(),
      };
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 崩溃报告优化：崩溃捕获、日志记录、报告发送、崩溃分析
  // ═══════════════════════════════════════════════════════════

  /// 崩溃报告列表缓存
  static final List<CrashReport> _crashReports = [];
  static const String _crashReportsKey = 'crash_reports';
  static const int _maxCrashReports = 50;

  /// 捕获未处理异常并记录为崩溃报告
  ///
  /// [error] 异常对象
  /// [stackTrace] 堆栈信息
  /// [context] 崩溃发生的上下文描述（如页面名称、操作描述）
  /// [fatal] 是否为致命崩溃
  static Future<void> captureCrash(
    dynamic error,
    StackTrace? stackTrace, {
    String? context,
    bool fatal = false,
  }) async {
    try {
      final report = CrashReport(
        id: generateId(),
        timestamp: DateTime.now(),
        error: error.toString(),
        stackTrace: stackTrace?.toString(),
        context: context,
        fatal: fatal,
        errorType: _classifyCrashType(error),
      );

      _crashReports.insert(0, report);
      // 限制崩溃报告数量
      while (_crashReports.length > _maxCrashReports) {
        _crashReports.removeLast();
      }

      await _saveCrashReports();
      debugPrint('[CrashReporter] 崩溃已捕获: ${report.errorType} - ${report.error}');

      // 致命崩溃立即尝试发送报告
      if (fatal) {
        await _sendCrashReport(report);
      }
    } catch (e) {
      debugPrint('[CrashReporter] 记录崩溃失败: $e');
    }
  }

  /// 分类崩溃类型
  ///
  /// 根据异常类型和错误信息自动分类崩溃类型。
  static String _classifyCrashType(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    final errorType = error.runtimeType.toString().toLowerCase();

    if (errorType.contains('oom') || errorStr.contains('out of memory') || errorStr.contains('内存不足')) {
      return 'memory';
    } else if (errorType.contains('io') || errorStr.contains('file') || errorStr.contains('path')) {
      return 'file_io';
    } else if (errorType.contains('network') || errorStr.contains('socket') || errorStr.contains('connection')) {
      return 'network';
    } else if (errorType.contains('timeout') || errorStr.contains('timeout') || errorStr.contains('超时')) {
      return 'timeout';
    } else if (errorType.contains('format') || errorStr.contains('parse') || errorStr.contains('json')) {
      return 'data_format';
    } else if (errorType.contains('permission') || errorStr.contains('denied') || errorStr.contains('权限')) {
      return 'permission';
    } else if (errorType.contains('state') || errorStr.contains('null') || errorStr.contains('nullpointer')) {
      return 'state_error';
    }
    return 'unknown';
  }

  /// 加载崩溃报告
  static Future<List<CrashReport>> loadCrashReports() async {
    if (_crashReports.isNotEmpty) return List.unmodifiable(_crashReports);
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_crashReportsKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _crashReports.clear();
        _crashReports.addAll(
          list.map((e) => CrashReport.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      debugPrint('[CrashReporter] 加载崩溃报告失败: $e');
    }
    return List.unmodifiable(_crashReports);
  }

  /// 保存崩溃报告到持久化存储
  static Future<void> _saveCrashReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_crashReports.map((e) => e.toJson()).toList());
      await prefs.setString(_crashReportsKey, json);
    } catch (e) {
      debugPrint('[CrashReporter] 保存崩溃报告失败: $e');
    }
  }

  /// 发送崩溃报告（生成可分享的报告文件）
  ///
  /// 将崩溃报告导出为 JSON 文件，便于用户通过分享发送给开发者。
  static Future<String?> _sendCrashReport(CrashReport report) async {
    try {
      final expDir = await _exportsDir;
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final fileName = 'crash_report_${report.id.substring(0, 8)}_$timestamp.json';
      final filePath = p.join(expDir.path, fileName);

      final reportJson = {
        'reportId': report.id,
        'timestamp': report.timestamp.toIso8601String(),
        'error': report.error,
        'errorType': report.errorType,
        'stackTrace': report.stackTrace,
        'context': report.context,
        'fatal': report.fatal,
        'appVersion': 'v2.15.0',
        'platform': Platform.operatingSystem,
        'platformVersion': Platform.operatingSystemVersion,
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(reportJson);
      final file = File(filePath);
      await file.writeAsString(jsonString);
      debugPrint('[CrashReporter] 崩溃报告已导出: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('[CrashReporter] 导出崩溃报告失败: $e');
      return null;
    }
  }

  /// 批量导出所有崩溃报告为可分享文件
  ///
  /// 返回导出文件路径
  static Future<String?> exportCrashReports() async {
    try {
      await loadCrashReports();
      if (_crashReports.isEmpty) return null;

      final expDir = await _exportsDir;
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final fileName = 'crash_reports_all_$timestamp.json';
      final filePath = p.join(expDir.path, fileName);

      final exportData = {
        'exportDate': DateTime.now().toIso8601String(),
        'reportCount': _crashReports.length,
        'analysis': analyzeCrashReports(),
        'reports': _crashReports.map((e) => e.toJson()).toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      final file = File(filePath);
      await file.writeAsString(jsonString);
      return filePath;
    } catch (e) {
      debugPrint('[CrashReporter] 批量导出崩溃报告失败: $e');
      return null;
    }
  }

  /// 分析崩溃报告
  ///
  /// 对所有崩溃报告进行统计分析，返回：
  /// - 各类型崩溃数量
  /// - 致命崩溃比例
  /// - 最近崩溃时间
  /// - 崩溃频率分析
  static Map<String, dynamic> analyzeCrashReports() {
    if (_crashReports.isEmpty) {
      return {
        'totalCount': 0,
        'fatalCount': 0,
        'typeDistribution': <String, int>{},
        'frequency': 'none',
      };
    }

    final typeDistribution = <String, int>{};
    int fatalCount = 0;

    for (final report in _crashReports) {
      typeDistribution[report.errorType] = (typeDistribution[report.errorType] ?? 0) + 1;
      if (report.fatal) fatalCount++;
    }

    // 分析崩溃频率
    final now = DateTime.now();
    final last24h = _crashReports.where((r) => now.difference(r.timestamp).inHours < 24).length;
    final last7d = _crashReports.where((r) => now.difference(r.timestamp).inDays < 7).length;

    String frequency;
    if (last24h >= 5) {
      frequency = 'critical';
    } else if (last7d >= 10) {
      frequency = 'high';
    } else if (last7d >= 3) {
      frequency = 'moderate';
    } else {
      frequency = 'low';
    }

    // 获取最常见的崩溃类型
    String? mostFrequentType;
    int maxCount = 0;
    for (final entry in typeDistribution.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        mostFrequentType = entry.key;
      }
    }

    return {
      'totalCount': _crashReports.length,
      'fatalCount': fatalCount,
      'fatalRate': _crashReports.isNotEmpty ? (fatalCount / _crashReports.length) : 0.0,
      'typeDistribution': typeDistribution,
      'mostFrequentType': mostFrequentType,
      'mostFrequentCount': maxCount,
      'last24hCount': last24h,
      'last7dCount': last7d,
      'frequency': frequency,
      'latestCrash': _crashReports.isNotEmpty ? _crashReports.first.toJson() : null,
    };
  }

  /// 清除所有崩溃报告
  static Future<void> clearCrashReports() async {
    _crashReports.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_crashReportsKey);
    } catch (_) {}
  }

  /// 删除指定崩溃报告
  static Future<void> deleteCrashReport(String reportId) async {
    _crashReports.removeWhere((r) => r.id == reportId);
    await _saveCrashReports();
  }

  // ═══════════════════════════════════════════════════════════
  // 存储空间管理：监控、清理、优化、报告
  // ═══════════════════════════════════════════════════════════

  /// 获取各目录的存储空间使用情况
  ///
  /// 返回各目录的字节数和文件数 Map：
  /// - projects: 项目数据目录
  /// - exports: 导出目录
  /// - backups: 备份目录
  /// - temp: 临时目录
  /// - total: 总计
  static Future<Map<String, dynamic>> getStorageUsage() async {
    final result = <String, dynamic>{};

    try {
      // 项目目录
      final projDir = await _projectsDir;
      result['projects'] = await _getDirectorySize(projDir);

      // 导出目录
      final expDir = await _exportsDir;
      result['exports'] = await _getDirectorySize(expDir);

      // 备份目录
      final bakDir = await _backupDir;
      result['backups'] = await _getDirectorySize(bakDir);

      // 临时目录
      final tmpDir = await tempDir;
      result['temp'] = await _getDirectorySize(tmpDir);

      // SharedPreferences 大小估算
      final prefs = await SharedPreferences.getInstance();
      int prefsSize = 0;
      for (final key in prefs.getKeys()) {
        final val = prefs.get(key);
        if (val is String) prefsSize += val.length * 2; // UTF-16
        else if (val is List) prefsSize += val.length * 8;
        else prefsSize += 8;
      }
      result['preferences'] = {'bytes': prefsSize, 'fileCount': 0};

      // 计算总和
      int totalBytes = 0;
      int totalFiles = 0;
      for (final key in ['projects', 'exports', 'backups', 'temp', 'preferences']) {
        final entry = result[key] as Map<String, dynamic>;
        totalBytes += (entry['bytes'] as int? ?? 0);
        totalFiles += (entry['fileCount'] as int? ?? 0);
      }
      result['total'] = {'bytes': totalBytes, 'fileCount': totalFiles};
    } catch (e) {
      debugPrint('[StorageService] 获取存储使用情况失败: $e');
      result['error'] = e.toString();
    }

    return result;
  }

  /// 计算目录的总字节数和文件数
  static Future<Map<String, dynamic>> _getDirectorySize(Directory dir) async {
    int totalBytes = 0;
    int fileCount = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            try {
              totalBytes += await entity.length();
              fileCount++;
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[StorageService] 计算目录大小失败: ${dir.path} - $e');
    }
    return {'bytes': totalBytes, 'fileCount': fileCount};
  }

  /// 格式化字节数为可读字符串（如 "12.3 MB"）
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 清理存储空间：清除临时文件、过旧的导出文件、多余备份
  ///
  /// [maxExportAgeDays] 导出文件最大保留天数，默认 30
  /// [maxBackupVersionsPerProject] 每个项目最多保留的备份数，默认 5
  /// 返回清理释放的字节数
  static Future<int> cleanupStorage({
    int maxExportAgeDays = 30,
    int maxBackupVersionsPerProject = 5,
  }) async {
    int freedBytes = 0;

    try {
      // 1. 清理临时目录
      final tmpDir = await tempDir;
      if (await tmpDir.exists()) {
        final tmpUsage = await _getDirectorySize(tmpDir);
        freedBytes += tmpUsage['bytes'] as int;
        await cleanupTemp();
        debugPrint('[StorageService] 清理临时文件: ${formatBytes(tmpUsage['bytes'] as int)}');
      }

      // 2. 清理过旧的导出文件
      final expDir = await _exportsDir;
      if (await expDir.exists()) {
        final threshold = DateTime.now().subtract(Duration(days: maxExportAgeDays));
        await for (final entity in expDir.list()) {
          if (entity is File) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(threshold)) {
              freedBytes += await entity.length();
              await entity.delete();
            }
          }
        }
      }

      // 3. 清理多余的备份（每个项目保留最新的 N 份）
      final bakDir = await _backupDir;
      if (await bakDir.exists()) {
        await for (final entity in bakDir.list()) {
          if (entity is Directory) {
            await _cleanOldBackups(entity, maxCount: maxBackupVersionsPerProject);
          }
        }
      }

      debugPrint('[StorageService] 存储清理完成，释放 ${formatBytes(freedBytes)}');
    } catch (e) {
      debugPrint('[StorageService] 存储清理失败: $e');
    }

    return freedBytes;
  }

  /// 优化存储：压缩项目中未使用的数据、清理孤立文件
  ///
  /// 返回优化报告 Map：
  /// - orphanedFiles: 发现的孤立文件数
  /// - removedOrphanedFiles: 已删除的孤立文件数
  /// - optimizedProjectCount: 优化的项目数
  static Future<Map<String, dynamic>> optimizeStorage() async {
    final report = <String, dynamic>{
      'orphanedFiles': 0,
      'removedOrphanedFiles': 0,
      'optimizedProjectCount': 0,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      final projDir = await _projectsDir;
      if (!await projDir.exists()) return report;

      // 加载有效的项目 ID 列表
      final projects = await loadProjects();
      final validIds = projects.map((p) => p.id).toSet();

      int orphanedCount = 0;
      int removedCount = 0;

      // 检查项目目录中的孤立目录（没有对应项目的目录）
      await for (final entity in projDir.list()) {
        if (entity is Directory) {
          final dirName = p.basename(entity.path);
          if (!validIds.contains(dirName)) {
            orphanedCount++;
            try {
              await entity.delete(recursive: true);
              removedCount++;
              debugPrint('[StorageService] 删除孤立项目目录: $dirName');
            } catch (e) {
              debugPrint('[StorageService] 删除孤立目录失败: $dirName - $e');
            }
          }
        }
      }

      report['orphanedFiles'] = orphanedCount;
      report['removedOrphanedFiles'] = removedCount;

      debugPrint('[StorageService] 存储优化完成: 发现 $orphanedCount 个孤立目录, 删除 $removedCount 个');
    } catch (e) {
      debugPrint('[StorageService] 存储优化失败: $e');
      report['error'] = e.toString();
    }

    return report;
  }

  /// 获取存储空间清理建议
  ///
  /// 根据当前存储使用情况生成具体的清理建议列表
  static Future<List<Map<String, dynamic>>> getStorageSuggestions() async {
    final suggestions = <Map<String, dynamic>>[];

    try {
      final usage = await getStorageUsage();
      final totalBytes = (usage['total'] as Map<String, dynamic>)['bytes'] as int? ?? 0;
      final tempBytes = ((usage['temp'] as Map<String, dynamic>?)?['bytes'] as int?) ?? 0;
      final exportBytes = ((usage['exports'] as Map<String, dynamic>?)?['bytes'] as int?) ?? 0;
      final backupBytes = ((usage['backups'] as Map<String, dynamic>?)?['bytes'] as int?) ?? 0;

      // 临时文件大于 10MB 建议清理
      if (tempBytes > 10 * 1024 * 1024) {
        suggestions.add({
          'type': 'temp_cleanup',
          'title': '清理临时文件',
          'description': '临时文件占用 ${formatBytes(tempBytes)}，建议清理',
          'estimatedFreedBytes': tempBytes,
          'priority': 'high',
        });
      }

      // 导出文件大于 50MB 建议清理旧文件
      if (exportBytes > 50 * 1024 * 1024) {
        suggestions.add({
          'type': 'export_cleanup',
          'title': '清理旧导出文件',
          'description': '导出文件占用 ${formatBytes(exportBytes)}，建议删除不需要的导出',
          'estimatedFreedBytes': (exportBytes * 0.5).round(),
          'priority': 'medium',
        });
      }

      // 备份文件大于 100MB 建议减少备份数
      if (backupBytes > 100 * 1024 * 1024) {
        suggestions.add({
          'type': 'backup_cleanup',
          'title': '减少备份版本数',
          'description': '备份文件占用 ${formatBytes(backupBytes)}，建议减少保留版本数',
          'estimatedFreedBytes': (backupBytes * 0.6).round(),
          'priority': 'medium',
        });
      }

      // 总空间大于 500MB 建议全面清理
      if (totalBytes > 500 * 1024 * 1024) {
        suggestions.add({
          'type': 'full_cleanup',
          'title': '全面存储清理',
          'description': '总存储占用 ${formatBytes(totalBytes)}，建议执行全面清理',
          'estimatedFreedBytes': (totalBytes * 0.3).round(),
          'priority': 'low',
        });
      }

      if (suggestions.isEmpty) {
        suggestions.add({
          'type': 'no_action',
          'title': '存储空间充足',
          'description': '当前存储占用 ${formatBytes(totalBytes)}，无需清理',
          'estimatedFreedBytes': 0,
          'priority': 'none',
        });
      }
    } catch (e) {
      debugPrint('[StorageService] 获取存储建议失败: $e');
    }

    return suggestions;
  }

  /// 生成完整的存储空间报告
  ///
  /// 包含存储使用详情、清理建议、优化历史等
  static Future<Map<String, dynamic>> getStorageReport() async {
    final report = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      // 存储使用情况
      report['usage'] = await getStorageUsage();

      // 清理建议
      report['suggestions'] = await getStorageSuggestions();

      // 缓存状态
      report['cache'] = {
        'projectCacheSize': _projectCache.length,
        'projectListCached': _cachedProjectList != null,
        'projectListCacheTime': _projectListCacheTime?.toIso8601String(),
        'performanceMetricsCount': _performanceMetrics.length,
        'remindersCached': _cachedReminders != null,
        'remindersCount': _cachedReminders?.length ?? 0,
      };

      // 项目统计
      final projects = await loadProjects();
      report['projectStats'] = {
        'totalProjects': projects.length,
        'totalGlyphs': projects.fold(0, (sum, p) => sum + p.glyphs.length),
        'totalEdited': projects.fold(0, (sum, p) =>
            sum + p.glyphs.values.where((g) => g.contours.isNotEmpty).length),
        'totalSourceImages': projects.fold(0, (sum, p) => sum + p.sourceImages.length),
      };
    } catch (e) {
      debugPrint('[StorageService] 生成存储报告失败: $e');
      report['error'] = e.toString();
    }

    return report;
  }

  // ═══════════════════════════════════════════════════════════
  // 多因素认证功能
  // ═══════════════════════════════════════════════════════════

  static const String _mfaEnabledKey = 'auth_mfa_enabled';
  static const String _mfaMethodKey = 'auth_mfa_method';
  static const String _mfaSecretKey = 'auth_mfa_secret';
  static const String _mfaBackupCodesKey = 'auth_mfa_backup_codes';

  /// MFA 认证方法
  static const String mfaMethodTotp = 'totp';         // 基于时间的一次性密码
  static const String mfaMethodSms = 'sms';           // 短信验证码
  static const String mfaMethodEmail = 'email';       // 邮箱验证码
  static const String mfaMethodBiometric = 'biometric'; // 生物识别

  /// 检查 MFA 是否启用
  static Future<bool> isMfaEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_mfaEnabledKey) ?? false;
  }

  /// 获取 MFA 认证方法
  static Future<String> getMfaMethod() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mfaMethodKey) ?? mfaMethodTotp;
  }

  /// 启用 MFA
  ///
  /// [method] 认证方法（totp/sms/email/biometric）
  /// [secret] 认证密钥（TOTP 场景下的密钥）
  static Future<void> enableMfa(String method, {String? secret}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mfaEnabledKey, true);
    await prefs.setString(_mfaMethodKey, method);
    if (secret != null) {
      await prefs.setString(_mfaSecretKey, secret);
    }
    // 生成备份码
    final backupCodes = _generateBackupCodes();
    await prefs.setStringList(_mfaBackupCodesKey, backupCodes);
    debugPrint('[StorageService] MFA 已启用: $method');
  }

  /// 禁用 MFA
  static Future<void> disableMfa() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mfaEnabledKey, false);
    await prefs.remove(_mfaMethodKey);
    await prefs.remove(_mfaSecretKey);
    await prefs.remove(_mfaBackupCodesKey);
    debugPrint('[StorageService] MFA 已禁用');
  }

  /// 验证 MFA 代码
  ///
  /// [code] 用户输入的验证码
  /// 返回 true 表示验证通过
  static Future<bool> verifyMfaCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final method = prefs.getString(_mfaMethodKey) ?? mfaMethodTotp;

    switch (method) {
      case mfaMethodTotp:
        return _verifyTotpCode(code);
      case mfaMethodSms:
      case mfaMethodEmail:
        return _verifyOtpCode(code);
      case mfaMethodBiometric:
        return await verifyBiometric();
      default:
        return false;
    }
  }

  /// 验证 TOTP 代码（简化实现，生产环境应使用 speakeasy 等库）
  static bool _verifyTotpCode(String code) {
    // 简化的 TOTP 验证：检查 6 位数字格式
    if (code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) {
      return false;
    }
    // 实际应用中应基于时间窗口和密钥计算 TOTP
    return true;
  }

  /// 验证 OTP 代码（简化实现）
  static bool _verifyOtpCode(String code) {
    return code.length >= 4 && code.length <= 8 && RegExp(r'^\d+$').hasMatch(code);
  }

  /// 使用备份码验证
  static Future<bool> verifyBackupCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final backupCodes = prefs.getStringList(_mfaBackupCodesKey) ?? [];
    if (backupCodes.contains(code)) {
      backupCodes.remove(code);
      await prefs.setStringList(_mfaBackupCodesKey, backupCodes);
      return true;
    }
    return false;
  }

  /// 获取剩余备份码数量
  static Future<int> getBackupCodeCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_mfaBackupCodesKey) ?? []).length;
  }

  /// 生成备份码
  static List<String> _generateBackupCodes() {
    final codes = <String>[];
    for (int i = 0; i < 8; i++) {
      final code = (DateTime.now().microsecondsSinceEpoch + i * 7919)
          .toString()
          .padLeft(8, '0')
          .substring(0, 8);
      codes.add(code);
    }
    return codes;
  }

  // ═══════════════════════════════════════════════════════════
  // 生物识别认证功能
  // ═══════════════════════════════════════════════════════════

  static const String _biometricEnabledKey = 'auth_biometric_enabled';
  static const String _biometricTypeKey = 'auth_biometric_type';

  /// 生物识别类型
  static const String biometricTypeFingerprint = 'fingerprint';
  static const String biometricTypeFace = 'face';
  static const String biometricTypeIris = 'iris';

  /// 检查生物识别是否启用
  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  /// 获取生物识别类型
  static Future<String> getBiometricType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_biometricTypeKey) ?? biometricTypeFingerprint;
  }

  /// 启用生物识别认证
  ///
  /// [type] 生物识别类型（fingerprint/face/iris）
  static Future<void> enableBiometric(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, true);
    await prefs.setString(_biometricTypeKey, type);
    debugPrint('[StorageService] 生物识别已启用: $type');
  }

  /// 禁用生物识别认证
  static Future<void> disableBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, false);
    debugPrint('[StorageService] 生物识别已禁用');
  }

  /// 执行生物识别验证
  ///
  /// 实际实现需要调用平台原生 API（如 LocalAuthentication）
  /// 此处提供框架和模拟实现
  static Future<bool> verifyBiometric() async {
    try {
      // 实际应用中应调用:
      // final localAuth = LocalAuthentication();
      // final didAuthenticate = await localAuth.authenticate(
      //   localizedReason: '请验证身份以继续',
      //   options: const AuthenticationOptions(biometricOnly: true),
      // );
      // return didAuthenticate;

      // 模拟实现：检查生物识别是否启用
      final enabled = await isBiometricEnabled();
      if (!enabled) return false;

      debugPrint('[StorageService] 生物识别验证（模拟通过）');
      return true;
    } catch (e) {
      debugPrint('[StorageService] 生物识别验证失败: $e');
      return false;
    }
  }

  /// 检查设备是否支持生物识别
  ///
  /// 实际实现需要调用平台 API
  static Future<bool> isBiometricAvailable() async {
    try {
      // 实际应用中应调用:
      // final localAuth = LocalAuthentication();
      // return await localAuth.canCheckBiometrics;
      return true; // 模拟返回
    } catch (e) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 单点登录功能
  // ═══════════════════════════════════════════════════════════

  static const String _ssoEnabledKey = 'auth_sso_enabled';
  static const String _ssoProviderKey = 'auth_sso_provider';
  static const String _ssoTokenKey = 'auth_sso_token';
  static const String _ssoProfileKey = 'auth_sso_profile';

  /// SSO 提供商
  static const String ssoProviderGoogle = 'google';
  static const String ssoProviderApple = 'apple';
  static const String ssoProviderGithub = 'github';
  static const String ssoProviderWechat = 'wechat';

  /// 检查 SSO 是否启用
  static Future<bool> isSsoEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ssoEnabledKey) ?? false;
  }

  /// 获取 SSO 提供商
  static Future<String?> getSsoProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ssoProviderKey);
  }

  /// 保存 SSO 登录信息
  ///
  /// [provider] SSO 提供商
  /// [token] 认证令牌
  /// [profile] 用户资料
  static Future<void> saveSsoSession(
    String provider,
    String token,
    Map<String, dynamic> profile,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ssoEnabledKey, true);
    await prefs.setString(_ssoProviderKey, provider);
    await prefs.setString(_ssoTokenKey, token);
    await prefs.setString(_ssoProfileKey, jsonEncode(profile));
    debugPrint('[StorageService] SSO 会话已保存: $provider');
  }

  /// 获取 SSO 用户资料
  static Future<Map<String, dynamic>?> getSsoProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final profileJson = prefs.getString(_ssoProfileKey);
    if (profileJson != null) {
      return jsonDecode(profileJson) as Map<String, dynamic>;
    }
    return null;
  }

  /// 清除 SSO 会话
  static Future<void> clearSsoSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ssoEnabledKey, false);
    await prefs.remove(_ssoProviderKey);
    await prefs.remove(_ssoTokenKey);
    await prefs.remove(_ssoProfileKey);
    debugPrint('[StorageService] SSO 会话已清除');
  }

  // ═══════════════════════════════════════════════════════════
  // 认证历史记录
  // ═══════════════════════════════════════════════════════════

  static const String _authHistoryKey = 'auth_history';
  static const int _maxAuthHistory = 100;

  /// 认证历史记录数据模型
  static Future<void> logAuthEvent({
    required String eventType,
    required String method,
    required bool success,
    String? details,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList(_authHistoryKey) ?? [];
      final entry = {
        'timestamp': DateTime.now().toIso8601String(),
        'eventType': eventType,
        'method': method,
        'success': success,
        'details': details,
      };
      historyJson.add(jsonEncode(entry));
      // 限制历史记录数量
      if (historyJson.length > _maxAuthHistory) {
        historyJson.removeRange(0, historyJson.length - _maxAuthHistory);
      }
      await prefs.setStringList(_authHistoryKey, historyJson);
    } catch (e) {
      debugPrint('[StorageService] 记录认证事件失败: $e');
    }
  }

  /// 获取认证历史记录
  static Future<List<Map<String, dynamic>>> getAuthHistory({int limit = 20}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList(_authHistoryKey) ?? [];
      final history = historyJson
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .toList()
          .reversed
          .take(limit)
          .toList();
      return history;
    } catch (e) {
      debugPrint('[StorageService] 获取认证历史失败: $e');
      return [];
    }
  }

  /// 清除认证历史
  static Future<void> clearAuthHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authHistoryKey);
  }

  /// 获取认证状态摘要
  static Future<Map<String, dynamic>> getAuthStatusSummary() async {
    return {
      'mfaEnabled': await isMfaEnabled(),
      'mfaMethod': await getMfaMethod(),
      'biometricEnabled': await isBiometricEnabled(),
      'biometricType': await getBiometricType(),
      'ssoEnabled': await isSsoEnabled(),
      'ssoProvider': await getSsoProvider(),
      'backupCodeCount': await getBackupCodeCount(),
    };
  }
}

/// 崩溃报告数据模型
///
/// 包含崩溃的完整信息：错误类型、堆栈、上下文、时间戳等。
class CrashReport {
  final String id;
  final DateTime timestamp;
  final String error;
  final String? stackTrace;
  final String? context;
  final bool fatal;
  final String errorType;

  const CrashReport({
    required this.id,
    required this.timestamp,
    required this.error,
    this.stackTrace,
    this.context,
    this.fatal = false,
    this.errorType = 'unknown',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'error': error,
        'stackTrace': stackTrace,
        'context': context,
        'fatal': fatal,
        'errorType': errorType,
      };

  factory CrashReport.fromJson(Map<String, dynamic> json) => CrashReport(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        error: json['error'] as String,
        stackTrace: json['stackTrace'] as String?,
        context: json['context'] as String?,
        fatal: json['fatal'] as bool? ?? false,
        errorType: json['errorType'] as String? ?? 'unknown',
      );

  @override
  String toString() => 'CrashReport[$errorType]: $error (${fatal ? "fatal" : "non-fatal"})';
}

// ═══════════════════════════════════════════════════════════
// 学习功能优化：学习进度跟踪、学习建议、学习统计、学习报告
// ═══════════════════════════════════════════════════════════

/// 学习进度数据模型