import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 新版本更新提示弹窗
/// 首次启动新版本时展示，让用户立刻感知到升级
class WhatsNewDialog extends StatelessWidget {
  final String version;
  final String subtitle;
  final List<WhatsNewItem> items;

  const WhatsNewDialog({
    super.key,
    required this.version,
    required this.subtitle,
    required this.items,
  });

  /// 检查并显示（仅首次）
  static Future<void> checkAndShow(
    BuildContext context, {
    required String version,
    required String subtitle,
    required List<WhatsNewItem> items,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final lastShown = prefs.getString('last_whats_new_version') ?? '';
    if (lastShown == version) return;
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => WhatsNewDialog(version: version, subtitle: subtitle, items: items),
    );
    await prefs.setString('last_whats_new_version', version);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部装饰
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, size: 28, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            Text('$version 更新', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 14, color: cs.primary, fontWeight: FontWeight.w500)),
            const SizedBox(height: 20),

            // 功能列表
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                        if (item.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(item.description, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('知道了', style: TextStyle(fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WhatsNewItem {
  final String icon;
  final String title;
  final String description;

  const WhatsNewItem({required this.icon, required this.title, this.description = ''});
}
