import 'package:shared_preferences/shared_preferences.dart';

enum PdfTextApiProvider { openai, aliyun, glm }

class PdfTextApiSettings {
  const PdfTextApiSettings({
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.apiSecret,
    required this.secretId,
    required this.secretKey,
    required this.tencentRegion,
    required this.baiduAuthUrl,
    required this.baiduOcrUrl,
    required this.prompt,
  });

  final PdfTextApiProvider provider;
  final String baseUrl;
  final String model;
  final String apiKey;
  final String apiSecret;
  final String secretId;
  final String secretKey;
  final String tencentRegion;
  final String baiduAuthUrl;
  final String baiduOcrUrl;
  final String prompt;

  factory PdfTextApiSettings.defaults() {
    return const PdfTextApiSettings(
      provider: PdfTextApiProvider.openai,
      baseUrl: '',
      model: '',
      apiKey: '',
      apiSecret: '',
      secretId: '',
      secretKey: '',
      tencentRegion: 'ap-beijing',
      baiduAuthUrl: 'https://aip.baidubce.com/oauth/2.0/token',
      baiduOcrUrl: 'https://aip.baidubce.com/rest/2.0/ocr/v1/accurate_basic',
      prompt: '请识别这页PDF图片中的所有文字，尽量保持原段落顺序输出纯文本，不要添加解释。',
    );
  }

  PdfTextApiSettings copyWith({
    PdfTextApiProvider? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
    String? apiSecret,
    String? secretId,
    String? secretKey,
    String? tencentRegion,
    String? baiduAuthUrl,
    String? baiduOcrUrl,
    String? prompt,
  }) {
    return PdfTextApiSettings(
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      apiSecret: apiSecret ?? this.apiSecret,
      secretId: secretId ?? this.secretId,
      secretKey: secretKey ?? this.secretKey,
      tencentRegion: tencentRegion ?? this.tencentRegion,
      baiduAuthUrl: baiduAuthUrl ?? this.baiduAuthUrl,
      baiduOcrUrl: baiduOcrUrl ?? this.baiduOcrUrl,
      prompt: prompt ?? this.prompt,
    );
  }

  String providerLabel() {
    switch (provider) {
      case PdfTextApiProvider.openai:
        return 'OpenAI';
      case PdfTextApiProvider.aliyun:
        return '阿里云';
      case PdfTextApiProvider.glm:
        return 'GLM';
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

  bool requiresLlmApi() {
    return true;
  }

  PdfTextApiSettings withRecommendedDefaults() {
    return copyWith(
      baseUrl: recommendedBaseUrlFor(provider),
      model: recommendedModelFor(provider),
      tencentRegion: tencentRegion,
      baiduAuthUrl: baiduAuthUrl,
      baiduOcrUrl: baiduOcrUrl,
    );
  }

  static String recommendedBaseUrlFor(PdfTextApiProvider provider) {
    switch (provider) {
      case PdfTextApiProvider.openai:
        return 'https://api.openai.com/v1';
      case PdfTextApiProvider.aliyun:
        return 'https://dashscope.aliyuncs.com/compatible-mode/v1';
      case PdfTextApiProvider.glm:
        return 'https://api.z.ai/api/paas/v4';
    }
  }

  static String recommendedModelFor(PdfTextApiProvider provider) {
    switch (provider) {
      case PdfTextApiProvider.openai:
        return 'gpt-4.1-mini';
      case PdfTextApiProvider.aliyun:
        return 'qwen-vl-plus';
      case PdfTextApiProvider.glm:
        return 'glm-ocr';
    }
  }
}

class PdfTextApiStore {
  PdfTextApiStore._();

  static final PdfTextApiStore instance = PdfTextApiStore._();

  static const _providerKey = 'pdf_text_api_provider';
  static const _baseUrlKey = 'pdf_text_api_base_url';
  static const _modelKey = 'pdf_text_api_model';
  static const _apiKeyKey = 'pdf_text_api_key';
  static const _apiSecretKey = 'pdf_text_api_secret';
  static const _secretIdKey = 'pdf_text_api_secret_id';
  static const _secretKeyKey = 'pdf_text_api_secret_key';
  static const _tencentRegionKey = 'pdf_text_tencent_region';
  static const _baiduAuthUrlKey = 'pdf_text_baidu_auth_url';
  static const _baiduOcrUrlKey = 'pdf_text_baidu_ocr_url';
  static const _promptKey = 'pdf_text_prompt';

  Future<PdfTextApiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final providerName =
        prefs.getString(_providerKey) ?? PdfTextApiProvider.openai.name;
    final provider = PdfTextApiProvider.values.firstWhere(
      (item) => item.name == providerName,
      orElse: () => PdfTextApiProvider.openai,
    );
    final defaults = PdfTextApiSettings.defaults();
    return PdfTextApiSettings(
      provider: provider,
      baseUrl: prefs.getString(_baseUrlKey) ?? defaults.baseUrl,
      model: prefs.getString(_modelKey) ?? defaults.model,
      apiKey: prefs.getString(_apiKeyKey) ?? defaults.apiKey,
      apiSecret: prefs.getString(_apiSecretKey) ?? defaults.apiSecret,
      secretId: prefs.getString(_secretIdKey) ?? defaults.secretId,
      secretKey: prefs.getString(_secretKeyKey) ?? defaults.secretKey,
      tencentRegion:
          prefs.getString(_tencentRegionKey) ?? defaults.tencentRegion,
      baiduAuthUrl: prefs.getString(_baiduAuthUrlKey) ?? defaults.baiduAuthUrl,
      baiduOcrUrl: prefs.getString(_baiduOcrUrlKey) ?? defaults.baiduOcrUrl,
      prompt: prefs.getString(_promptKey) ?? defaults.prompt,
    );
  }

  Future<void> save(PdfTextApiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerKey, settings.provider.name);
    await prefs.setString(_baseUrlKey, settings.baseUrl);
    await prefs.setString(_modelKey, settings.model);
    await prefs.setString(_apiKeyKey, settings.apiKey);
    await prefs.setString(_apiSecretKey, settings.apiSecret);
    await prefs.setString(_secretIdKey, settings.secretId);
    await prefs.setString(_secretKeyKey, settings.secretKey);
    await prefs.setString(_tencentRegionKey, settings.tencentRegion);
    await prefs.setString(_baiduAuthUrlKey, settings.baiduAuthUrl);
    await prefs.setString(_baiduOcrUrlKey, settings.baiduOcrUrl);
    await prefs.setString(_promptKey, settings.prompt);
  }
}
