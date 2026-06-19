import 'package:flutter/material.dart';

/// 预览场景模板
class PreviewTemplates {
  PreviewTemplates._();

  // ── 正文模板 ──
  static const newsArticle = '新华社北京电 — 在数字化浪潮席卷全球的今天，人工智能技术正在深刻改变着我们的生活方式。从智能制造到智慧城市，从医疗健康到文化传承，AI 的应用场景不断拓展。专家指出，未来十年将是人工智能发展的关键时期，技术创新与产业融合将持续深化。';

  static const novelParagraph = '月亮升起来了，照在院子里那棵老槐树上，叶子的影子在地上轻轻摇晃。他坐在石阶上，手里捧着一杯温热的茶，望着远处的山峦出神。风从山谷里吹来，带着松柏的清香和泥土的气息，让人感到一种说不出的宁静。';

  // ── 标题模板 ──
  static const articleTitle = '探索未来：人工智能与手写艺术的融合';
  static const posterTitle = '手迹造字\n让每一个字\n都有温度';

  // ── 表格模板 ──
  static const dataTable = '项目名称 | 状态 | 进度\n手迹造字 | 进行中 | 85%\n字体预览 | 已完成 | 100%\n风格迁移 | 测试中 | 70%\n批量处理 | 已上线 | 100%';

  static const schedule = '时间 | 周一 | 周二 | 周三\n09:00 | 晨会 | 评审 | 设计\n14:00 | 编码 | 测试 | 评审\n16:00 | 文档 | 演示 | 总结';

  // ── 代码模板 ──
  static const codeSnippet = 'void main() {\n  final font = FontProject(\n    name: \'手迹字体\',\n    glyphs: {},\n  );\n\n  print(font.name);\n}';

  // 所有模板列表
  static const all = [
    PreviewTemplateItem(
      name: '新闻文章',
      content: newsArticle,
      category: PreviewCategory.body,
    ),
    PreviewTemplateItem(
      name: '小说段落',
      content: novelParagraph,
      category: PreviewCategory.body,
    ),
    PreviewTemplateItem(
      name: '文章标题',
      content: articleTitle,
      category: PreviewCategory.headline,
    ),
    PreviewTemplateItem(
      name: '海报标题',
      content: posterTitle,
      category: PreviewCategory.headline,
    ),
    PreviewTemplateItem(
      name: '数据表格',
      content: dataTable,
      category: PreviewCategory.table,
    ),
    PreviewTemplateItem(
      name: '日程表',
      content: schedule,
      category: PreviewCategory.table,
    ),
    PreviewTemplateItem(
      name: '代码片段',
      content: codeSnippet,
      category: PreviewCategory.code,
    ),
  ];
}

enum PreviewCategory { body, headline, table, code }

extension PreviewCategoryX on PreviewCategory {
  String get label {
    switch (this) {
      case PreviewCategory.body:
        return '正文';
      case PreviewCategory.headline:
        return '标题';
      case PreviewCategory.table:
        return '表格';
      case PreviewCategory.code:
        return '代码';
    }
  }

  IconData get icon {
    switch (this) {
      case PreviewCategory.body:
        return Icons.article;
      case PreviewCategory.headline:
        return Icons.title;
      case PreviewCategory.table:
        return Icons.table_chart;
      case PreviewCategory.code:
        return Icons.code;
    }
  }
}

class PreviewTemplateItem {
  final String name;
  final String content;
  final PreviewCategory category;

  const PreviewTemplateItem({
    required this.name,
    required this.content,
    required this.category,
  });
}
