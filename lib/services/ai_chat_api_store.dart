import 'package:shared_preferences/shared_preferences.dart';

enum AiChatApiProvider { openai, aliyun, glm, deepseek }

class AiChatApiSettings {
  const AiChatApiSettings({
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.systemPrompt,
    required this.temperature,
  });

  final AiChatApiProvider provider;
  final String baseUrl;
  final String model;
  final String apiKey;
  final String systemPrompt;
  final double temperature;

  factory AiChatApiSettings.defaults() {
    return const AiChatApiSettings(
      provider: AiChatApiProvider.openai,
      baseUrl: '',
      model: '',
      apiKey: '',
      systemPrompt: '你是阅读助手。回答要准确、简洁；如果用户提供引用内容，优先基于引用回答，并明确不确定性。',
      temperature: 0.3,
    );
  }

  AiChatApiSettings copyWith({
    AiChatApiProvider? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
    String? systemPrompt,
    double? temperature,
  }) {
    return AiChatApiSettings(
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
    );
  }

  String providerLabel() {
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

  String effectiveBaseUrl() {
    if (baseUrl.trim().isNotEmpty) return baseUrl.trim();
    return recommendedBaseUrlFor(provider);
  }

  String effectiveModel() {
    if (model.trim().isNotEmpty) return model.trim();
    return recommendedModelFor(provider);
  }

  AiChatApiSettings withRecommendedDefaults() {
    return copyWith(
      baseUrl: recommendedBaseUrlFor(provider),
      model: recommendedModelFor(provider),
    );
  }

  static String recommendedBaseUrlFor(AiChatApiProvider provider) {
    switch (provider) {
      case AiChatApiProvider.openai:
        return 'https://api.openai.com/v1';
      case AiChatApiProvider.aliyun:
        return 'https://dashscope.aliyuncs.com/compatible-mode/v1';
      case AiChatApiProvider.glm:
        return 'https://open.bigmodel.cn/api/paas/v4';
      case AiChatApiProvider.deepseek:
        return 'https://api.deepseek.com/v1';
    }
  }

  static String recommendedModelFor(AiChatApiProvider provider) {
    switch (provider) {
      case AiChatApiProvider.openai:
        return 'gpt-4.1-mini';
      case AiChatApiProvider.aliyun:
        return 'qwen-plus';
      case AiChatApiProvider.glm:
        return 'glm-4.5-air';
      case AiChatApiProvider.deepseek:
        return 'deepseek-chat';
    }
  }
}

class AiChatApiStore {
  AiChatApiStore._();

  static final AiChatApiStore instance = AiChatApiStore._();

  static const _providerKey = 'ai_chat_api_provider';
  static const _baseUrlKey = 'ai_chat_api_base_url';
  static const _modelKey = 'ai_chat_api_model';
  static const _apiKeyKey = 'ai_chat_api_key';
  static const _systemPromptKey = 'ai_chat_system_prompt';
  static const _temperatureKey = 'ai_chat_temperature';

  Future<AiChatApiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final providerName =
        prefs.getString(_providerKey) ?? AiChatApiProvider.openai.name;
    final provider = AiChatApiProvider.values.firstWhere(
      (item) => item.name == providerName,
      orElse: () => AiChatApiProvider.openai,
    );
    final defaults = AiChatApiSettings.defaults();
    final savedTemperature = prefs.getDouble(_temperatureKey);
    return AiChatApiSettings(
      provider: provider,
      baseUrl: prefs.getString(_baseUrlKey) ?? defaults.baseUrl,
      model: prefs.getString(_modelKey) ?? defaults.model,
      apiKey: prefs.getString(_apiKeyKey) ?? defaults.apiKey,
      systemPrompt: prefs.getString(_systemPromptKey) ?? defaults.systemPrompt,
      temperature: (savedTemperature ?? defaults.temperature).clamp(0.0, 1.5),
    );
  }

  Future<void> save(AiChatApiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerKey, settings.provider.name);
    await prefs.setString(_baseUrlKey, settings.baseUrl);
    await prefs.setString(_modelKey, settings.model);
    await prefs.setString(_apiKeyKey, settings.apiKey);
    await prefs.setString(_systemPromptKey, settings.systemPrompt);
    await prefs.setDouble(
      _temperatureKey,
      settings.temperature.clamp(0.0, 1.5),
    );
  }
}
