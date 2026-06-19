import 'package:flutter/material.dart';
import '../../models/project.dart';

/// 参数调节面板 — 阈值、腐蚀、膨胀、平滑度、对比度、反转颜色
class ParameterPanel extends StatelessWidget {
  final ProcessingParams params;
  final ValueChanged<ProcessingParams> onChanged;

  const ParameterPanel({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with reset button
          Row(
            children: [
              Text(
                '参数调节',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '（推荐值）',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => onChanged(ProcessingParams()),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('恢复默认'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Threshold
          _buildSlider(
            label: '阈值',
            value: params.threshold,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            icon: Icons.contrast,
            colorScheme: colorScheme,
            onChanged: (v) => onChanged(params.copyWith(threshold: v)),
          ),
          const SizedBox(height: 8),

          // Two sliders in a row
          Row(
            children: [
              Expanded(
                child: _buildSlider(
                  label: '腐蚀',
                  value: params.erosion.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  icon: Icons.remove_circle_outline,
                  colorScheme: colorScheme,
                  onChanged: (v) => onChanged(params.copyWith(erosion: v.round())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSlider(
                  label: '膨胀',
                  value: params.dilation.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  icon: Icons.add_circle_outline,
                  colorScheme: colorScheme,
                  onChanged: (v) => onChanged(params.copyWith(dilation: v.round())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Smoothing and contrast
          Row(
            children: [
              Expanded(
                child: _buildSlider(
                  label: '平滑度',
                  value: params.smoothness,
                  min: 0.0,
                  max: 1.0,
                  icon: Icons.blur_on,
                  colorScheme: colorScheme,
                  onChanged: (v) => onChanged(params.copyWith(smoothness: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSlider(
                  label: '对比度',
                  value: params.contrast,
                  min: 0.5,
                  max: 3.0,
                  icon: Icons.brightness_6,
                  colorScheme: colorScheme,
                  onChanged: (v) => onChanged(params.copyWith(contrast: v)),
                ),
              ),
            ],
          ),

          // Invert toggle
          Row(
            children: [
              Icon(Icons.swap_horiz, size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('反转颜色', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
              const Spacer(),
              Switch(
                value: params.invertColors,
                onChanged: (v) => onChanged(params.copyWith(invertColors: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required IconData icon,
    required ColorScheme colorScheme,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
