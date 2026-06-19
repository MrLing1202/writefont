import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/project.dart';
import '../../services/storage_service.dart';
import '../auto_generate_screen.dart';
import '../capture_screen.dart';
import '../character_grid_screen.dart';
import '../processing_screen.dart';
import '../project_list_screen.dart';

/// 首页业务逻辑辅助类
class HomeActions {
  /// 打开字符总览（需先选择项目）
  static Future<void> openCharacterGrid(BuildContext context) async {
    final projects = await StorageService.loadProjects();
    if (!context.mounted) return;

    if (projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建并保存一个字体项目')),
      );
      return;
    }

    final selected = await showDialog<FontProject>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择项目'),
        children: projects
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, p),
                child: ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(p.name),
                  subtitle: Text('${p.glyphs.length} 个字符'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            )
            .toList(),
      ),
    );

    if (selected != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CharacterGridScreen(project: selected),
        ),
      );
    }
  }

  /// 快速体验模式：只需10个常用字
  static void startQuickMode(BuildContext context) {
    const quickCharsList = ['的', '一', '是', '不', '了', '在', '人', '有', '我', '他', '这'];
    final now = DateTime.now();
    final dateStr = '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    final project = FontProject(
      id: StorageService.generateId(),
      name: '快速体验 $dateStr',
    );
    for (final char in quickCharsList) {
      project.glyphs[char] = GlyphData(
        character: char,
        unicode: char.codeUnitAt(0),
      );
    }

    StorageService.saveProject(project);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaptureScreen(charset: quickCharsList),
      ),
    );
  }

  /// 一键生成：拍照或选图后直接进入自动处理
  static Future<void> quickCapture(BuildContext context) async {
    final picker = ImagePicker();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('拍照'),
                subtitle: const Text('拍摄手写内容'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('从相册选择'),
                subtitle: const Text('选择已有的手写照片'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !context.mounted) return;

    XFile? image;
    if (source == ImageSource.camera) {
      image = await picker.pickImage(source: ImageSource.camera, imageQuality: 95);
    } else {
      image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    }

    if (image == null || !context.mounted) return;

    final imageBytes = await image.readAsBytes();

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AutoGenerateScreen(imageBytes: imageBytes),
        ),
      );
    }
  }

  /// 自由拍照造字：多张图片选择
  static Future<void> pickImages(BuildContext context) async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 95);

    if (images.isNotEmpty && context.mounted) {
      final imageBytes = await Future.wait(
        images.map((img) => img.readAsBytes()),
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProcessingScreen(sourceImages: imageBytes),
          ),
        );
      }
    }
  }

  /// 打开我的字体页面
  static Future<void> openProjectList(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProjectListScreen()),
    );
  }
}
