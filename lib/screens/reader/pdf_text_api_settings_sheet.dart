import 'package:flutter/material.dart';

import '../../services/pdf_text_api_store.dart';

class PdfTextApiSettingsSheet extends StatefulWidget {
  const PdfTextApiSettingsSheet({
    super.key,
    required this.initial,
    required this.onSave,
    required this.onTest,
  });

  final PdfTextApiSettings initial;
  final ValueChanged<PdfTextApiSettings> onSave;
  final Future<String> Function(PdfTextApiSettings settings) onTest;

  @override
  State<PdfTextApiSettingsSheet> createState() =>
      _PdfTextApiSettingsSheetState();
}

class _PdfTextApiSettingsSheetState extends State<PdfTextApiSettingsSheet> {
  late PdfTextApiProvider _provider;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _apiSecretController;
  late final TextEditingController _secretIdController;
  late final TextEditingController _secretKeyController;
  late final TextEditingController _tencentRegionController;
  late final TextEditingController _baiduAuthUrlController;
  late final TextEditingController _baiduOcrUrlController;
  late final TextEditingController _promptController;
  bool _testing = false;
  String? _testMessage;
  bool _testPassed = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _provider = initial.provider;
    _baseUrlController = TextEditingController(text: initial.baseUrl);
    _modelController = TextEditingController(text: initial.model);
    _apiKeyController = TextEditingController(text: initial.apiKey);
    _apiSecretController = TextEditingController(text: initial.apiSecret);
    _secretIdController = TextEditingController(text: initial.secretId);
    _secretKeyController = TextEditingController(text: initial.secretKey);
    _tencentRegionController = TextEditingController(
      text: initial.tencentRegion,
    );
    _baiduAuthUrlController = TextEditingController(text: initial.baiduAuthUrl);
    _baiduOcrUrlController = TextEditingController(text: initial.baiduOcrUrl);
    _promptController = TextEditingController(text: initial.prompt);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    _secretIdController.dispose();
    _secretKeyController.dispose();
    _tencentRegionController.dispose();
    _baiduAuthUrlController.dispose();
    _baiduOcrUrlController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const isLlm = true;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PDF识别接口设置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PdfTextApiProvider>(
                initialValue: _provider,
                decoration: const InputDecoration(labelText: '服务商'),
                items: PdfTextApiProvider.values
                    .map(
                      (provider) => DropdownMenuItem<PdfTextApiProvider>(
                        value: provider,
                        child: Text(_providerLabel(provider)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _provider = value);
                },
              ),
              const SizedBox(height: 10),
              if (isLlm) ...[
                _textField(_baseUrlController, 'Base URL（可留空走默认）'),
                const SizedBox(height: 10),
                _textField(_modelController, '模型（可留空走默认）'),
                const SizedBox(height: 10),
                _textField(_apiKeyController, 'API Key'),
                const SizedBox(height: 10),
                _textField(_promptController, '识别提示词', maxLines: 3),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _fillRecommendedDefaults,
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('填充推荐默认'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _testing ? null : _testConfig,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering_outlined),
                label: Text(_testing ? '测试中...' : '测试配置'),
              ),
              if (_testMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _testPassed
                        ? Colors.green.withOpacity(0.08)
                        : Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _testPassed
                          ? Colors.green.withOpacity(0.3)
                          : Colors.red.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    _testMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _testPassed
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                '说明：读取PDF时优先提取本地文本层，仅对图片页调用接口。',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  FilledButton(onPressed: _save, child: const Text('保存')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _providerLabel(PdfTextApiProvider provider) {
    switch (provider) {
      case PdfTextApiProvider.openai:
        return 'OpenAI';
      case PdfTextApiProvider.aliyun:
        return '阿里云';
      case PdfTextApiProvider.glm:
        return 'GLM';
    }
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  void _save() {
    final settings = _buildSettings();
    widget.onSave(settings);
    Navigator.pop(context);
  }

  PdfTextApiSettings _buildSettings() {
    return widget.initial.copyWith(
      provider: _provider,
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      apiSecret: _apiSecretController.text.trim(),
      secretId: _secretIdController.text.trim(),
      secretKey: _secretKeyController.text.trim(),
      tencentRegion: _tencentRegionController.text.trim(),
      baiduAuthUrl: _baiduAuthUrlController.text.trim(),
      baiduOcrUrl: _baiduOcrUrlController.text.trim(),
      prompt: _promptController.text.trim().isEmpty
          ? widget.initial.prompt
          : _promptController.text.trim(),
    );
  }

  void _fillRecommendedDefaults() {
    final recommended = _buildSettings().withRecommendedDefaults();
    _baseUrlController.text = recommended.baseUrl;
    _modelController.text = recommended.model;
    _tencentRegionController.text = recommended.tencentRegion;
    _baiduAuthUrlController.text = recommended.baiduAuthUrl;
    _baiduOcrUrlController.text = recommended.baiduOcrUrl;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已填充推荐默认参数')));
  }

  Future<void> _testConfig() async {
    setState(() {
      _testing = true;
      _testPassed = false;
      _testMessage = '正在测试配置，请稍候...';
    });
    try {
      final message = await widget.onTest(_buildSettings());
      if (!mounted) return;
      setState(() {
        _testPassed = true;
        _testMessage = message;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _testPassed = false;
        _testMessage = '测试失败：$err';
      });
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }
}
