import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AiChatRole { user, assistant }

class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.quote,
  });

  final String id;
  final AiChatRole role;
  final String content;
  final int createdAt;
  final String? quote;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    'createdAt': createdAt,
    'quote': quote,
  };

  static AiChatMessage fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String? ?? AiChatRole.user.name;
    final role = AiChatRole.values.firstWhere(
      (item) => item.name == roleName,
      orElse: () => AiChatRole.user,
    );
    return AiChatMessage(
      id: json['id'] as String,
      role: role,
      content: json['content'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      quote: json['quote'] as String?,
    );
  }
}

class AiChatConversation {
  const AiChatConversation({
    required this.id,
    required this.title,
    required this.bookId,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String title;
  final String? bookId;
  final int createdAt;
  final int updatedAt;
  final List<AiChatMessage> messages;

  AiChatConversation copyWith({
    String? title,
    String? bookId,
    int? createdAt,
    int? updatedAt,
    List<AiChatMessage>? messages,
  }) {
    return AiChatConversation(
      id: id,
      title: title ?? this.title,
      bookId: bookId ?? this.bookId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'bookId': bookId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'messages': messages.map((item) => item.toJson()).toList(),
  };

  static AiChatConversation fromJson(Map<String, dynamic> json) {
    final messages = (json['messages'] as List<dynamic>? ?? [])
        .map((item) => AiChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
    return AiChatConversation(
      id: json['id'] as String,
      title: json['title'] as String? ?? '新对话',
      bookId: json['bookId'] as String?,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      messages: messages,
    );
  }
}

class AiChatStore {
  AiChatStore._();

  static final AiChatStore instance = AiChatStore._();

  File? _dataFile;
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    final docsDir = await getApplicationDocumentsDirectory();
    _dataFile = File(p.join(docsDir.path, 'ai_chat_history.json'));
    _initialized = true;
  }

  Future<List<AiChatConversation>> loadAll() async {
    await _ensureInit();
    final file = _dataFile;
    if (file == null || !await file.exists()) return [];
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(AiChatConversation.fromJson)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> saveAll(List<AiChatConversation> conversations) async {
    await _ensureInit();
    final file = _dataFile;
    if (file == null) return;
    final encoded = jsonEncode(
      conversations.map((item) => item.toJson()).toList(),
    );
    await file.writeAsString(encoded);
  }
}
