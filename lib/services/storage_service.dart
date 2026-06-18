import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../models/project.dart';
import 'ttf_builder.dart';

/// Service for file operations: saving, loading, and exporting.
class StorageService {
  static const _uuid = Uuid();

  /// Get the app's documents directory.
  static Future<Directory> get _documentsDir async {
    final dir = await getApplicationDocumentsDirectory();
    final writefontDir = Directory(p.join(dir.path, 'writefont'));
    if (!await writefontDir.exists()) {
      await writefontDir.create(recursive: true);
    }
    return writefontDir;
  }

  /// Get the projects directory.
  static Future<Directory> get _projectsDir async {
    final docs = await _documentsDir;
    final projDir = Directory(p.join(docs.path, 'projects'));
    if (!await projDir.exists()) {
      await projDir.create(recursive: true);
    }
    return projDir;
  }

  /// Get the exports directory.
  static Future<Directory> get _exportsDir async {
    final docs = await _documentsDir;
    final expDir = Directory(p.join(docs.path, 'exports'));
    if (!await expDir.exists()) {
      await expDir.create(recursive: true);
    }
    return expDir;
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
  static Future<String> exportTtf(FontProject project) async {
    final expDir = await _exportsDir;
    final fileName = '${project.name.replaceAll(RegExp(r'[^\w]'), '_')}.ttf';
    final filePath = p.join(expDir.path, fileName);

    // Build the TTF
    final glyphs = project.glyphs.values.toList();
    final builder = TtfBuilder(
      glyphs: glyphs,
      familyName: project.name,
      unitsPerEm: 1000,
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
    } catch (_) {}
  }

  // ============================================================
  // 项目持久化管理
  // ============================================================

  /// 保存项目到本地文件（JSON 格式）
  static Future<void> saveProject(FontProject project) async {
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
  }

  /// 加载所有已保存的项目（仅加载元数据，不含源图片二进制）
  static Future<List<FontProject>> loadProjects() async {
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
    return projects;
  }

  /// 根据 ID 加载单个项目
  static Future<FontProject?> loadProject(String id) async {
    final projDir = await _projectsDir;
    final jsonFile = File(p.join(projDir.path, id, 'project.json'));

    if (!await jsonFile.exists()) return null;

    try {
      final jsonString = await jsonFile.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return FontProject.fromJson(json);
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
}
