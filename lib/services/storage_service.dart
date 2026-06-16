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
}
