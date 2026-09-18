import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Who authored a chat message.
enum ChatRole { user, assistant }

/// What a chat message renders as.
enum ChatMessageKind { text, toolStep, failure }

/// How an attached file was ingested for the model (see attachment_ingest).
class ChatAttachmentRef {
  final String name;

  /// One of `text` | `image` | `rejected`.
  final String ingest;

  /// Short note (e.g. a rejection reason); nullable.
  final String? note;

  const ChatAttachmentRef({
    required this.name,
    required this.ingest,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'ingest': ingest,
    if (note != null) 'note': note,
  };

  factory ChatAttachmentRef.fromJson(Map<String, dynamic> json) =>
      ChatAttachmentRef(
        name: json['name'] as String,
        ingest: json['ingest'] as String,
        note: json['note'] as String?,
      );
}

/// One persistent chat: model, per-chat inference settings, and metadata.
class ChatSession {
  // Tool-call turns are structured output, not prose: the default is
  // effectively greedy (topK 1) so a 2B model does not sample its way out of a
  // valid call (R3). The per-chat sliders still let a user loosen it.
  static const double defaultTemperature = 0.1;
  static const int defaultTopK = 1;
  static const double defaultTopP = 1.0;
  static const int defaultMaxOutputTokens = 1024;
  static const String defaultModelTaskId = 'agent.llm.qwen';
  static const String defaultTitle = 'New chat';

  final int? id;
  String title;
  String modelTaskId;
  double temperature;
  int topK;
  double topP;
  int maxOutputTokens;
  DateTime createdAt;
  DateTime updatedAt;

  ChatSession({
    this.id,
    required this.title,
    required this.modelTaskId,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.maxOutputTokens,
    required this.createdAt,
    required this.updatedAt,
  });

  /// A brand-new session with the curated defaults, timestamped [now].
  factory ChatSession.fresh(DateTime now) => ChatSession(
    title: defaultTitle,
    modelTaskId: defaultModelTaskId,
    temperature: defaultTemperature,
    topK: defaultTopK,
    topP: defaultTopP,
    maxOutputTokens: defaultMaxOutputTokens,
    createdAt: now,
    updatedAt: now,
  );

  ChatSession copyWith({
    String? title,
    String? modelTaskId,
    double? temperature,
    int? topK,
    double? topP,
    int? maxOutputTokens,
    DateTime? updatedAt,
  }) => ChatSession(
    id: id,
    title: title ?? this.title,
    modelTaskId: modelTaskId ?? this.modelTaskId,
    temperature: temperature ?? this.temperature,
    topK: topK ?? this.topK,
    topP: topP ?? this.topP,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// One rendered line of a chat transcript.
class ChatMessage {
  final int? id;
  final int sessionId;
  final ChatRole role;
  final ChatMessageKind kind;

  /// Answer/user text; `''` for a [ChatMessageKind.toolStep].
  final String text;

  /// The model's `<think>` content; null when absent.
  final String? thinking;

  /// [ChatMessageKind.toolStep] only.
  final String? toolLabel;
  final String? outputName;
  final String? outputPath;

  final List<ChatAttachmentRef> attachments;
  final DateTime createdAt;

  const ChatMessage({
    this.id,
    required this.sessionId,
    required this.role,
    required this.kind,
    required this.text,
    this.thinking,
    this.toolLabel,
    this.outputName,
    this.outputPath,
    this.attachments = const [],
    required this.createdAt,
  });
}

/// Persists and reads the unified chat. List columns are stored as JSON.
/// Mirrors [HistoryRepository]'s plain-sqflite shape (no codegen).
class ChatRepository {
  ChatRepository(this._db);
  final Database _db;

  Future<List<ChatSession>> sessions() async {
    final rows = await _db.query('chat_sessions', orderBy: 'updated_at DESC');
    return [for (final row in rows) _sessionFromRow(row)];
  }

  Future<int> createSession(ChatSession s) {
    return _db.insert('chat_sessions', _sessionValues(s));
  }

  Future<void> updateSession(ChatSession s) {
    return _db.update(
      'chat_sessions',
      _sessionValues(s),
      where: 'id = ?',
      whereArgs: [s.id],
    );
  }

  Future<void> touchSession(int id, DateTime at) {
    return _db.update(
      'chat_sessions',
      {'updated_at': at.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a session and its messages. No FK cascade is configured, so the
  /// child rows are removed explicitly first.
  Future<void> deleteSession(int id) async {
    await _db.delete('chat_messages', where: 'session_id = ?', whereArgs: [id]);
    await _db.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ChatMessage>> messages(int sessionId) async {
    final rows = await _db.query(
      'chat_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at, id',
    );
    return [for (final row in rows) _messageFromRow(row)];
  }

  Future<int> addMessage(ChatMessage m) {
    return _db.insert('chat_messages', {
      'session_id': m.sessionId,
      'role': m.role.name,
      'kind': m.kind.name,
      'text': m.text,
      'thinking': m.thinking,
      'tool_label': m.toolLabel,
      'output_name': m.outputName,
      'output_path': m.outputPath,
      'attachments': jsonEncode([for (final a in m.attachments) a.toJson()]),
      'created_at': m.createdAt.millisecondsSinceEpoch,
    });
  }

  Map<String, Object?> _sessionValues(ChatSession s) => {
    'title': s.title,
    'model_task_id': s.modelTaskId,
    'temperature': s.temperature,
    'top_k': s.topK,
    'top_p': s.topP,
    'max_output_tokens': s.maxOutputTokens,
    'created_at': s.createdAt.millisecondsSinceEpoch,
    'updated_at': s.updatedAt.millisecondsSinceEpoch,
  };

  ChatSession _sessionFromRow(Map<String, Object?> row) => ChatSession(
    id: row['id'] as int,
    title: row['title'] as String,
    modelTaskId: row['model_task_id'] as String,
    temperature: (row['temperature'] as num).toDouble(),
    topK: row['top_k'] as int,
    topP: (row['top_p'] as num).toDouble(),
    maxOutputTokens: row['max_output_tokens'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
  );

  ChatMessage _messageFromRow(Map<String, Object?> row) => ChatMessage(
    id: row['id'] as int,
    sessionId: row['session_id'] as int,
    role: ChatRole.values.byName(row['role'] as String),
    kind: ChatMessageKind.values.byName(row['kind'] as String),
    text: row['text'] as String,
    thinking: row['thinking'] as String?,
    toolLabel: row['tool_label'] as String?,
    outputName: row['output_name'] as String?,
    outputPath: row['output_path'] as String?,
    attachments: [
      for (final e in jsonDecode(row['attachments'] as String) as List)
        ChatAttachmentRef.fromJson((e as Map).cast<String, dynamic>()),
    ],
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
  );
}
