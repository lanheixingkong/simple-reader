import 'package:flutter/material.dart';

import '../../services/ai_chat_api_store.dart';

class AiChatApiSettingsSheet extends StatefulWidget {
  const AiChatApiSettingsSheet({
    super.key,
    required this.initial,
    required this.onSave,
    required this.onTest,
  });

  final AiChatApiSettings initial;
  final ValueChanged<AiChatApiSettings> onSave;
  final Future<String> Function(AiChatApiSettings settings) onTest;

  @override
  State<AiChatApiSettingsSheet> createState() => _AiChatApiSettingsSheetState();
}

class _AiChatApiSettingsSheetState extends State<AiChatApiSettingsSheet> {
  late AiChatApiProvider _provider;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _systemPromptController;
  late final TextEditingController _webSearchApiKeyController;
  late final TextEditingController _webSearchBaseUrlController;
  late double _temperature;
  late bool _agentEnabled;
  late bool _webSearchEnabled;
  late WebSearchProvider _webSearchProvider;
  bool _testing = false;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _provider = initial.provider;
    _baseUrlController = TextEditingController(text: initial.baseUrl);
    _modelController = TextEditingController(text: initial.model);
    _apiKeyController = TextEditingController(text: initial.apiKey);
    _systemPromptController = TextEditingController(text: initial.systemPrompt);
    _webSearchApiKeyController = TextEditingController(
      text: initial.webSearchApiKey,
    );
    _webSearchBaseUrlController = TextEditingController(
      text: initial.webSearchBaseUrl,
    );
    _temperature = initial.temperature;
    _agentEnabled = initial.agentEnabled;
    _webSearchEnabled = initial.webSearchEnabled;
    _webSearchProvider = initial.webSearchProvider;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    _systemPromptController.dispose();
    _webSearchApiKeyController.dispose();
    _webSearchBaseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'AI问答接口设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AiChatApiProvider>(
                initialValue: _provider,
                decoration: const InputDecoration(
                  labelText: '服务商',
                  border: OutlineInputBorder(),
                ),
                items: AiChatApiProvider.values
                    .map(
                      (item) => DropdownMenuItem<AiChatApiProvider>(
                        value: item,
                        child: Text(_providerLabel(item)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _provider = value);
                },
              ),
              const SizedBox(height: 12),
              _textField(_baseUrlController, 'Base URL（可留空走默认）'),
              const SizedBox(height: 12),
              _textField(_modelController, '模型（可留空走默认）'),
              const SizedBox(height: 12),
              _textField(_apiKeyController, 'API Key', obscure: true),
              const SizedBox(height: 12),
              const Text('温度（temperature）'),
              Slider(
                value: _temperature.clamp(0.0, 1.5),
                min: 0,
                max: 1.5,
                divisions: 15,
                label: _temperature.toStringAsFixed(1),
                onChanged: (value) => setState(() => _temperature = value),
              ),
              const SizedBox(height: 8),
              _textField(_systemPromptController, '系统提示词', maxLines: 4),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 Agent 模式'),
                subtitle: const Text('允许模型自主选择并调用已启用的工具'),
                value: _agentEnabled,
                onChanged: (value) => setState(() => _agentEnabled = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用联网搜索'),
                subtitle: const Text('模型会根据问题自主决定是否搜索'),
                value: _webSearchEnabled,
                onChanged: _agentEnabled
                    ? (value) => setState(() => _webSearchEnabled = value)
                    : null,
              ),
              if (_agentEnabled && _webSearchEnabled) ...[
                const SizedBox(height: 4),
                DropdownButtonFormField<WebSearchProvider>(
                  initialValue: _webSearchProvider,
                  decoration: const InputDecoration(
                    labelText: '联网搜索服务商',
                    border: OutlineInputBorder(),
                  ),
                  items: WebSearchProvider.values
                      .map(
                        (item) => DropdownMenuItem<WebSearchProvider>(
                          value: item,
                          child: Text(_webSearchProviderLabel(item)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _webSearchProvider = value);
                  },
                ),
                const SizedBox(height: 12),
                if (_webSearchProvider != WebSearchProvider.searxng) ...[
                  _textField(
                    _webSearchApiKeyController,
                    '${_webSearchProviderName(_webSearchProvider)} API Key',
                    obscure: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '无需自建服务。工具会将搜索摘要和来源链接交给 Agent。',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ] else ...[
                  _textField(
                    _webSearchBaseUrlController,
                    'SearXNG 实例地址，例如 http://127.0.0.1:8080',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'SearXNG 免费开源，但公共实例可能限流或禁用 JSON API。',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(onPressed: _save, child: const Text('保存')),
                  OutlinedButton(
                    onPressed: _fillRecommended,
                    child: const Text('填入推荐值'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_testing ? '测试中...' : '测试配置'),
                  ),
                ],
              ),
              if (_testMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _testMessage!,
                  style: TextStyle(
                    color: _testMessage!.contains('通过')
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '此配置与 PDF 识别接口配置隔离，互不影响。',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      maxLines: obscure ? 1 : maxLines,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  String _providerLabel(AiChatApiProvider provider) {
    switch (provider) {
      case AiChatApiProvider.openai:
        return 'OpenAI';
      case AiChatApiProvider.aliyun:
        return '阿里云';
      case AiChatApiProvider.glm:
        return 'GLM';
      case AiChatApiProvider.deepseek:
        return 'DeepSeek';
    }
  }

  String _webSearchProviderLabel(WebSearchProvider provider) {
    return switch (provider) {
      WebSearchProvider.tavily => 'Tavily（无需自建，推荐）',
      WebSearchProvider.exa => 'Exa（无需自建）',
      WebSearchProvider.brave => 'Brave Search（无需自建）',
      WebSearchProvider.serper => 'Serper（无需自建）',
      WebSearchProvider.searxng => 'SearXNG（开源/自托管）',
    };
  }

  String _webSearchProviderName(WebSearchProvider provider) {
    return switch (provider) {
      WebSearchProvider.tavily => 'Tavily',
      WebSearchProvider.exa => 'Exa',
      WebSearchProvider.brave => 'Brave Search',
      WebSearchProvider.serper => 'Serper',
      WebSearchProvider.searxng => 'SearXNG',
    };
  }

  void _save() {
    final settings = _buildSettings();
    widget.onSave(settings);
    Navigator.of(context).pop();
  }

  void _fillRecommended() {
    final patched = _buildSettings().withRecommendedDefaults();
    setState(() {
      _baseUrlController.text = patched.baseUrl;
      _modelController.text = patched.model;
    });
  }

  Future<void> _test() async {
    final settings = _buildSettings();
    setState(() {
      _testing = true;
      _testMessage = '正在测试配置，请稍候...';
    });
    try {
      final message = await widget.onTest(settings);
      if (!mounted) return;
      setState(() => _testMessage = message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _testMessage = '测试失败：$error');
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  AiChatApiSettings _buildSettings() {
    return AiChatApiSettings(
      provider: _provider,
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      systemPrompt: _systemPromptController.text.trim(),
      temperature: _temperature.clamp(0.0, 1.5),
      agentEnabled: _agentEnabled,
      webSearchEnabled: _agentEnabled && _webSearchEnabled,
      webSearchProvider: _webSearchProvider,
      webSearchApiKey: _webSearchApiKeyController.text.trim(),
      webSearchBaseUrl: _webSearchBaseUrlController.text.trim(),
    );
  }
}
