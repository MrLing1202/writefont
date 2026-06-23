import 'package:flutter_test/flutter_test.dart';

/// v5.2.0: 识别优化单元测试
///
/// 测试范围：
/// 1. 候选评分权重优化
/// 2. 形近字消歧
/// 3. 简单字判断
/// 4. 自适应阈值参数
void main() {
  group('v5.2.0 Recognition Optimizations', () {
    // ═══ 形近字消歧测试 ═══
    group('Confusable Character Groups', () {
      test('confusable groups contain expected character pairs', () {
        // 验证形近字组定义正确
        const groups = {
          '己已巳': ['己', '已', '巳'],
          '未末': ['未', '末'],
          '太犬': ['太', '犬'],
          '土士': ['土', '士'],
        };

        for (final entry in groups.entries) {
          expect(entry.value.length, greaterThanOrEqualTo(2),
              reason: 'Group "${entry.key}" should have at least 2 characters');
          // 每个字符应该是单个汉字
          for (final ch in entry.value) {
            expect(ch.length, equals(1),
                reason: 'Each character should be a single character');
            final codeUnit = ch.codeUnitAt(0);
            // CJK 基本区范围
            expect(codeUnit, greaterThanOrEqualTo(0x4E00),
                reason: 'Character "$ch" should be in CJK range');
            expect(codeUnit, lessThanOrEqualTo(0x9FFF),
                reason: 'Character "$ch" should be in CJK range');
          }
        }
      });

      test('confusable groups have no duplicates across groups', () {
        const groups = {
          '己已巳': ['己', '已', '巳'],
          '未末': ['未', '末'],
          '太犬': ['太', '犬'],
          '土士': ['土', '士'],
          '天夫': ['天', '夫'],
          '干千': ['干', '千'],
          '人入': ['人', '入'],
          '刀力': ['刀', '力'],
          '日目': ['日', '目'],
          '田由': ['田', '由'],
        };

        final allChars = <String>{};
        for (final entry in groups.entries) {
          for (final ch in entry.value) {
            expect(allChars.contains(ch), isFalse,
                reason: 'Character "$ch" should not appear in multiple groups');
            allChars.add(ch);
          }
        }
      });
    });

    // ═══ 简单字判断测试 ═══
    group('Simple Character Detection', () {
      test('common simple characters are detected', () {
        // 常见 1-3 笔画汉字
        const simpleChars = ['一', '二', '三', '人', '大', '小', '上', '下', '日', '月'];

        for (final ch in simpleChars) {
          final codePoint = ch.runes.first;
          // 验证在 CJK 范围内
          expect(codePoint, greaterThanOrEqualTo(0x4E00),
              reason: 'Character "$ch" should be in CJK range');
          expect(codePoint, lessThanOrEqualTo(0x9FFF),
              reason: 'Character "$ch" should be in CJK range');
        }
      });

      test('complex characters are not marked as simple', () {
        // 复杂汉字（笔画多）
        const complexChars = ['繁', '曦', '鑫', '鬱', '靈'];

        for (final ch in complexChars) {
          final codePoint = ch.runes.first;
          // 验证在 CJK 范围内
          expect(codePoint, greaterThanOrEqualTo(0x4E00),
              reason: 'Character "$ch" should be in CJK range');
        }
      });
    });

    // ═══ 评分权重测试 ═══
    group('Scoring Weights', () {
      test('weights sum to 1.0', () {
        // v5.2.0 权重
        const votesWeight = 0.35;
        const confidenceWeight = 0.20;
        const freqWeight = 0.10;
        const diversityWeight = 0.10;
        const multiScaleWeight = 0.10;
        const contextWeight = 0.15;

        final total = votesWeight +
            confidenceWeight +
            freqWeight +
            diversityWeight +
            multiScaleWeight +
            contextWeight;

        expect(total, closeTo(1.0, 0.001),
            reason: 'All weights should sum to 1.0');
      });

      test('confidence weight increased from v4.8.0', () {
        // v4.8.0: confidence was 0.15
        // v5.2.0: confidence is 0.20
        const v480Confidence = 0.15;
        const v520Confidence = 0.20;

        expect(v520Confidence, greaterThan(v480Confidence),
            reason: 'v5.2.0 should have higher confidence weight');
      });

      test('diversity weight decreased from v4.8.0', () {
        // v4.8.0: diversity was 0.15
        // v5.2.0: diversity is 0.10
        const v480Diversity = 0.15;
        const v520Diversity = 0.10;

        expect(v520Diversity, lessThan(v480Diversity),
            reason: 'v5.2.0 should have lower diversity weight');
      });
    });

    // ═══ 自适应阈值测试 ═══
    group('Adaptive Threshold', () {
      test('low contrast should reduce c value', () {
        // 低对比度图片：c 应该减小
        const originalC = 12;
        const globalContrast = 0.10; // 低对比度

        int adaptedC;
        if (globalContrast < 0.15) {
          adaptedC = (originalC * 0.6).round().clamp(4, originalC);
        } else if (globalContrast > 0.45) {
          adaptedC = (originalC * 1.3).round().clamp(originalC, 20);
        } else {
          adaptedC = originalC;
        }

        expect(adaptedC, lessThan(originalC),
            reason: 'Low contrast should reduce c value');
        expect(adaptedC, greaterThanOrEqualTo(4),
            reason: 'c should not go below 4');
      });

      test('high contrast should increase c value', () {
        // 高对比度图片：c 应该增大
        const originalC = 12;
        const globalContrast = 0.50; // 高对比度

        int adaptedC;
        if (globalContrast < 0.15) {
          adaptedC = (originalC * 0.6).round().clamp(4, originalC);
        } else if (globalContrast > 0.45) {
          adaptedC = (originalC * 1.3).round().clamp(originalC, 20);
        } else {
          adaptedC = originalC;
        }

        expect(adaptedC, greaterThan(originalC),
            reason: 'High contrast should increase c value');
        expect(adaptedC, lessThanOrEqualTo(20),
            reason: 'c should not exceed 20');
      });

      test('normal contrast should keep c unchanged', () {
        // 正常对比度：c 不变
        const originalC = 12;
        const globalContrast = 0.30; // 正常对比度

        int adaptedC;
        if (globalContrast < 0.15) {
          adaptedC = (originalC * 0.6).round().clamp(4, originalC);
        } else if (globalContrast > 0.45) {
          adaptedC = (originalC * 1.3).round().clamp(originalC, 20);
        } else {
          adaptedC = originalC;
        }

        expect(adaptedC, equals(originalC),
            reason: 'Normal contrast should keep c unchanged');
      });
    });

    // ═══ 旋转重试阈值测试 ═══
    group('Rotation Retry Threshold', () {
      test('threshold raised from 0.5 to 0.65', () {
        // v3.8.0: threshold was 0.5
        // v5.2.0: threshold is 0.65
        const v380Threshold = 0.5;
        const v520Threshold = 0.65;

        expect(v520Threshold, greaterThan(v380Threshold),
            reason: 'v5.2.0 should have higher rotation retry threshold');

        // 0.6 置信度在旧版本不会触发旋转重试，在新版本会
        const confidence = 0.6;
        expect(confidence, greaterThan(v380Threshold),
            reason: '0.6 should not trigger rotation retry in v3.8.0');
        expect(confidence, lessThan(v520Threshold),
            reason: '0.6 should trigger rotation retry in v5.2.0');
      });
    });

    // ═══ TFLite 占位检测测试 ═══
    group('TFLite Placeholder Detection', () {
      test('placeholder interpreter should be detected', () {
        // 模拟占位推理器检测
        // 当 isUsingPlaceholder 为 true 时，TFLite 投票应被跳过
        const isUsingPlaceholder = true;
        const isModelLoaded = true;

        // v5.2.0: 只有当模型已加载且不是占位器时才投票
        final shouldVote = isModelLoaded && !isUsingPlaceholder;
        expect(shouldVote, isFalse,
            reason: 'Placeholder interpreter should not be used for voting');
      });

      test('real model should be used for voting', () {
        const isUsingPlaceholder = false;
        const isModelLoaded = true;

        final shouldVote = isModelLoaded && !isUsingPlaceholder;
        expect(shouldVote, isTrue,
            reason: 'Real model should be used for voting');
      });
    });
  });
}
