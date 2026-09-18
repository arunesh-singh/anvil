/// Host tests for [ChatRepository] against an in-memory sqlite (ffi): session
/// CRUD, updated-desc ordering, ordered messages, and message cascade on
/// session delete.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:anvil/core/chat_repository.dart';

Future<Database> _openDb() async {
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE chat_sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            model_task_id TEXT NOT NULL,
            temperature REAL NOT NULL,
            top_k INTEGER NOT NULL,
            top_p REAL NOT NULL,
            max_output_tokens INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE chat_messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            role TEXT NOT NULL,
            kind TEXT NOT NULL,
            text TEXT NOT NULL,
            thinking TEXT,
            tool_label TEXT,
            output_name TEXT,
            output_path TEXT,
            attachments TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    ),
  );
  return db;
}

ChatSession _session(DateTime at, {String title = 'Chat'}) => ChatSession(
  title: title,
  modelTaskId: 'agent.llm',
  temperature: 0.4,
  topK: 40,
  topP: 0.95,
  maxOutputTokens: 1024,
  createdAt: at,
  updatedAt: at,
);

ChatMessage _message(
  int sessionId,
  DateTime at, {
  ChatRole role = ChatRole.user,
  ChatMessageKind kind = ChatMessageKind.text,
  String text = 'hi',
  String? thinking,
  List<ChatAttachmentRef> attachments = const [],
  String? toolLabel,
  String? outputName,
  String? outputPath,
}) => ChatMessage(
  sessionId: sessionId,
  role: role,
  kind: kind,
  text: text,
  thinking: thinking,
  toolLabel: toolLabel,
  outputName: outputName,
  outputPath: outputPath,
  attachments: attachments,
  createdAt: at,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late ChatRepository repo;

  setUp(() async {
    db = await _openDb();
    repo = ChatRepository(db);
  });

  tearDown(() => db.close());

  test('sessions list newest-updated first', () async {
    final t0 = DateTime.fromMillisecondsSinceEpoch(1000);
    final t1 = DateTime.fromMillisecondsSinceEpoch(2000);
    await repo.createSession(_session(t0, title: 'older'));
    await repo.createSession(_session(t1, title: 'newer'));

    final sessions = await repo.sessions();
    expect(sessions.map((s) => s.title).toList(), ['newer', 'older']);
    expect(sessions.first.id, isNotNull);
  });

  test('createSession returns a row id and roundtrips settings', () async {
    final id = await repo.createSession(
      _session(DateTime.fromMillisecondsSinceEpoch(5), title: 'settings'),
    );
    final s = (await repo.sessions()).single;
    expect(s.id, id);
    expect(s.modelTaskId, 'agent.llm');
    expect(s.temperature, 0.4);
    expect(s.topK, 40);
    expect(s.topP, 0.95);
    expect(s.maxOutputTokens, 1024);
  });

  test('updateSession persists a rename', () async {
    final id = await repo.createSession(
      _session(DateTime.fromMillisecondsSinceEpoch(1), title: 'before'),
    );
    final loaded = (await repo.sessions()).single;
    await repo.updateSession(loaded.copyWith(title: 'after'));
    expect((await repo.sessions()).single.title, 'after');
    expect((await repo.sessions()).single.id, id);
  });

  test('touchSession bumps updated_at', () async {
    final id = await repo.createSession(
      _session(DateTime.fromMillisecondsSinceEpoch(1)),
    );
    await repo.touchSession(id, DateTime.fromMillisecondsSinceEpoch(9999));
    expect(
      (await repo.sessions()).single.updatedAt.millisecondsSinceEpoch,
      9999,
    );
  });

  test('messages read back in created order with fields intact', () async {
    final id = await repo.createSession(
      _session(DateTime.fromMillisecondsSinceEpoch(1)),
    );
    await repo.addMessage(
      _message(
        id,
        DateTime.fromMillisecondsSinceEpoch(10),
        text: 'first',
        attachments: const [ChatAttachmentRef(name: 'a.pdf', ingest: 'text')],
      ),
    );
    await repo.addMessage(
      _message(
        id,
        DateTime.fromMillisecondsSinceEpoch(20),
        role: ChatRole.assistant,
        text: 'second',
        thinking: 'hmm',
      ),
    );

    final msgs = await repo.messages(id);
    expect(msgs.map((m) => m.text).toList(), ['first', 'second']);
    expect(msgs.first.attachments.single.name, 'a.pdf');
    expect(msgs.first.attachments.single.ingest, 'text');
    expect(msgs.last.role, ChatRole.assistant);
    expect(msgs.last.thinking, 'hmm');
  });

  test('a toolStep output_path round-trips', () async {
    final id = await repo.createSession(
      _session(DateTime.fromMillisecondsSinceEpoch(1)),
    );
    await repo.addMessage(
      _message(
        id,
        DateTime.fromMillisecondsSinceEpoch(10),
        role: ChatRole.assistant,
        kind: ChatMessageKind.toolStep,
        text: '',
        toolLabel: 'Add Text to PDF',
        outputName: 'x.pdf',
        outputPath: '/out/x.pdf',
      ),
    );

    final m = (await repo.messages(id)).single;
    expect(m.kind, ChatMessageKind.toolStep);
    expect(m.outputPath, '/out/x.pdf');
    expect(m.outputName, 'x.pdf');
  });

  test('deleteSession removes the session and its messages', () async {
    final keep = await repo.createSession(
      _session(DateTime.fromMillisecondsSinceEpoch(1), title: 'keep'),
    );
    final drop = await repo.createSession(
      _session(DateTime.fromMillisecondsSinceEpoch(2), title: 'drop'),
    );
    await repo.addMessage(
      _message(keep, DateTime.fromMillisecondsSinceEpoch(3)),
    );
    await repo.addMessage(
      _message(drop, DateTime.fromMillisecondsSinceEpoch(4)),
    );
    await repo.addMessage(
      _message(drop, DateTime.fromMillisecondsSinceEpoch(5)),
    );

    await repo.deleteSession(drop);

    expect((await repo.sessions()).map((s) => s.title).toList(), ['keep']);
    expect(await repo.messages(drop), isEmpty);
    expect(await repo.messages(keep), hasLength(1));
  });
}
