import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/standard_charset.dart';
import 'processing_screen.dart';
import '../theme/app_theme.dart';

/// 标准字表引导页面
class CharsetGuideScreen extends StatefulWidget {
  const CharsetGuideScreen({super.key});

  @override
  State<CharsetGuideScreen> createState() => _CharsetGuideScreenState();
}

class _CharsetGuideScreenState extends State<CharsetGuideScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 根据搜索关键词过滤字符（按汉字或拼音匹配）
  List<StandardChar> _filterChars(List<StandardChar> chars) {
    if (_searchQuery.isEmpty) return chars;
    final query = _searchQuery.toLowerCase();
    return chars.where((c) {
      return c.char.contains(query) || c.pinyin.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSearching = _searchQuery.isNotEmpty;
    final filteredBasic = _filterChars(StandardCharset.basicChars);
    final filteredExtended = _filterChars(StandardCharset.extendedChars);
    final filteredAll = _filterChars(StandardCharset.allChars);

    return Scaffold(
      appBar: WFAppBar(
        title: '标准字表',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 提示文字（搜索时隐藏以节省空间）
          if (!isSearching)
            WFCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '请在白纸上按顺序书写以下字符',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: WFColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '最少写30字，写得越多生成的字体越像',
                    style: TextStyle(
                      fontSize: 14,
                      color: WFColors.primary,
                    ),
                  ),
                ],
              ),
            ),

          // 搜索框
          _buildSearchBar(colorScheme),

          // 字表网格
          Expanded(
            child: filteredAll.isEmpty
                ? _buildSearchEmptyState(colorScheme)
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标准字表网格预览（4x10）
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
                        _buildStandardGrid(filteredAll, colorScheme),
                        const SizedBox(height: 24),

                        // 基础字标题
                        if (filteredBasic.isNotEmpty) ...[
                          _buildSectionTitle('基础 30 字（必写）', colorScheme),
                          const SizedBox(height: 12),
                          _buildCharGrid(filteredBasic, colorScheme),
                          const SizedBox(height: 24),
                        ],

                        // 扩展字标题
                        if (filteredExtended.isNotEmpty) ...[
                          _buildSectionTitle('扩展 10 字（推荐）', colorScheme),
                          const SizedBox(height: 8),
                          Text(
                            '写得越多，生成的字体越完整',
                            style: TextStyle(
                              fontSize: 13,
                              color: WFColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildCharGrid(filteredExtended, colorScheme),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
          ),

          // 底部按钮（搜索时隐藏）
          if (!isSearching)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      '写完后点击下方按钮拍照上传',
                      style: TextStyle(
                        fontSize: 13,
                        color: WFColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    WFPrimaryButton(
                      text: '写完了，去拍照',
                      icon: Icons.camera_alt,
                      onPressed: () => _pickImageAndProcess(context),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 搜索框
  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
        decoration: InputDecoration(
          hintText: '搜索汉字或拼音...',
          hintStyle: TextStyle(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        ),
      ),
    );
  }

  /// 搜索无结果提示
  Widget _buildSearchEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 56,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              '没有找到匹配的字符',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '试试搜索汉字或拼音',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: WFColors.textPrimary,
      ),
    );
  }

  /// 构建标准字表的 4 列网格预览
  Widget _buildStandardGrid(List<StandardChar> chars, ColorScheme colorScheme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: chars.length,
      itemBuilder: (context, index) {
        final char = chars[index];
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
                color: WFColors.textPrimary,
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
        color: WFColors.bgPrimary,
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
                color: WFColors.textSecondary.withValues(alpha: 0.6),
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
                color: WFColors.textPrimary,
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
                color: WFColors.textSecondary.withValues(alpha: 0.5),
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
          WFAnimations.slideRoute(ProcessingScreen(
            sourceImages: imageBytes,
            charset: StandardCharset.allCharStrings, // 传入标准字表
          )),
        );
      }
    }
  }
}
