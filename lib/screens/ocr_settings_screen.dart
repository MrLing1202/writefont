import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/recognition_service.dart';

/// OCR 识别设置页面
class OcrSettingsScreen extends StatefulWidget {
  const OcrSettingsScreen({super.key});

  @override
  State<OcrSettingsScreen> createState() => _OcrSettingsScreenState();
}

class _OcrSettingsScreenState extends State<OcrSettingsScreen> {
  final RecognitionService _recognitionService = RecognitionService.instance;
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();

  bool _useCloud = false;
  bool _isLoading = true;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final useCloud = await _recognitionService.getUseCloud();
    final cloudUrl = await _recognitionService.getCloudUrl();

    setState(() {
      _useCloud = useCloud;
      _urlController.text = cloudUrl ?? '';
      _isLoading = false;
    });
  }

  Future<void> _saveSettings({bool showSnackbar = true}) async {
    await _recognitionService.setUseCloud(_useCloud);
    final userKey = _keyController.text.trim();
    await _recognitionService.setCloudConfig(
      _urlController.text.trim(),
      userKey.isEmpty ? null : userKey,
    );

    if (showSnackbar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);

    try {
      // 先保存当前 UI 输入的配置，确保测试使用最新值
      await _saveSettings(showSnackbar: false);

      // 创建一个简单的测试图片（1x1 白色 PNG）
      final testImage = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG header
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // 8-bit RGB
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, // data
        0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, // checksum
        0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND
        0x44, 0xAE, 0x42, 0x60, 0x82,
      ]);

      // 使用当前 UI 选择的模式，而不是已保存的配置
      final result = await _recognitionService.recognizeCharacter(
        testImage,
        forceUseCloud: _useCloud,
      );

      if (mounted) {
        final mode = _useCloud ? '云端' : '本地';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result != null ? '$mode识别成功！识别到: $result' : '$mode识别成功（返回空结果）'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('测试失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isTesting = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('识别设置'),
        actions: [
          TextButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            label: const Text('保存'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 本地识别说明
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.phone_android, color: colorScheme.primary),
                            const SizedBox(width: 12),
                            Text(
                              '本地识别（默认）',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '使用 Google ML Kit 离线识别中文手写字符，无需网络，完全免费。',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '当前为默认模式，安装即可使用',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 云端识别选项
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.cloud_upload, color: colorScheme.secondary),
                            const SizedBox(width: 12),
                            Text(
                              RecognitionService.cloudDisplayName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'DeepSeek 开源 3B 视觉 OCR 模型，通过硅基流动免费 API 调用，仅需填写 API Key。',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 开关
                        SwitchListTile(
                          title: const Text('启用云端识别'),
                          subtitle: const Text('关闭则使用本地 ML Kit'),
                          value: _useCloud,
                          onChanged: (value) {
                            setState(() => _useCloud = value);
                    _saveSettings(showSnackbar: false);
                          },
                        ),

                        if (_useCloud) ...[
                          const Divider(),
                          const SizedBox(height: 8),

                          // API 地址
                          TextField(
                            controller: _urlController,
                            decoration: InputDecoration(
                              labelText: 'API 地址',
                              hintText: RecognitionService.defaultCloudUrl,
                              prefixIcon: const Icon(Icons.link),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.url,
                          ),

                          const SizedBox(height: 16),

                          // API Key
                          TextField(
                            controller: _keyController,
                            decoration: InputDecoration(
                              labelText: 'API Key（硅基流动）',
                              hintText: 'sk-xxxxxxxxxxxxxxxxxxxxxxxx',
                              prefixIcon: const Icon(Icons.key),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            obscureText: true,
                          ),

                          const SizedBox(height: 16),

                          // 测试按钮
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isTesting ? null : _testConnection,
                              icon: _isTesting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.wifi_tethering),
                              label: Text(_isTesting ? '测试中...' : '测试连接'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 使用说明
                Card(
                  color: colorScheme.surfaceVariant.withOpacity(0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '如何获取 API Key',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '1. 访问 siliconflow.cn 注册账号\n'
                          '2. 进入「API 密钥」页面创建密钥\n'
                          '3. 将密钥粘贴到上方输入框即可\n\n'
                          'DeepSeek-OCR 模型目前免费调用，无需充值。\n'
                          '也可替换为其他兼容 OpenAI 格式的云端 API。',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
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
}
