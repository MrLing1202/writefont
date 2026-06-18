import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/standard_charset.dart';
import 'processing_screen.dart';

/// 标准字表引导页面
class CharsetGuideScreen extends StatelessWidget {
  const CharsetGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('标准字表'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 提示文字
          Container(
            padding: const EdgeInsets.all(16),
            color: colorScheme.surfaceVariant.withValues(alpha: 0.3),
            child: Column(
              children: [
                Text(
                  '请在白纸上按顺序书写以下字符',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '最少写30字，写得越多生成的字体越像',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),

          // 字表网格
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标准 40 字字表网格预览（4x10）
                  _buildSectionTitle('标准字表预览', colorScheme),
                  const SizedBox(height: 4),
                  Text(
                    '来源：GB2312 常用字',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStandardGrid(colorScheme),
                  const SizedBox(height: 24),

                  // 基础30字标题
                  _buildSectionTitle('基础 30 字（必写）', colorScheme),
                  const SizedBox(height: 12),

                  // 基础字网格
                  _buildCharGrid(StandardCharset.basicChars, colorScheme),

                  const SizedBox(height: 24),

                  // 扩展10字标题
                  _buildSectionTitle('扩展 10 字（推荐）', colorScheme),
                  const SizedBox(height: 8),
                  Text(
                    '写得越多，生成的字体越完整',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 扩展字网格
                  _buildCharGrid(StandardCharset.extendedChars, colorScheme),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // 底部按钮
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 提示
                  Text(
                    '写完后点击下方按钮拍照上传',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 按钮
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _pickImageAndProcess(context),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('写完了，去拍照'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
    );
  }

  /// 构建标准 40 字字表的 4x10 网格预览
  Widget _buildStandardGrid(ColorScheme colorScheme) {
    final allChars = StandardCharset.allChars;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: allChars.length,
      itemBuilder: (context, index) {
        final char = allChars[index];
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Center(
            child: Text(
              char.char,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCharGrid(List<StandardChar> chars, ColorScheme colorScheme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: chars.length,
      itemBuilder: (context, index) {
        final char = chars[index];
        return _buildCharCell(char, colorScheme);
      },
    );
  }

  Widget _buildCharCell(StandardChar char, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // 序号
          Positioned(
            top: 4,
            left: 6,
            child: Text(
              '${char.index}',
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),

          // 字符
          Center(
            child: Text(
              char.char,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),

          // 拼音
          Positioned(
            bottom: 4,
            left: 0,
            right: 0,
            child: Text(
              char.pinyin,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImageAndProcess(BuildContext context) async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 95);

    if (images.isNotEmpty && context.mounted) {
      // 读取图片字节
      final imageBytes = await Future.wait(
        images.map((img) => img.readAsBytes()),
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProcessingScreen(
              sourceImages: imageBytes,
              charset: StandardCharset.allCharStrings, // 传入标准字表
            ),
          ),
        );
      }
    }
  }
}
