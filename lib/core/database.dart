import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens (creating on first run) the single app database `anvil.db`.
///
/// We use sqflite over drift to avoid build_runner/codegen in Phase 0 (D-note in
/// the plan). One table for run history, one key/value table for settings, one
/// append-only table for the app log.
Future<Database> openAnvilDatabase() async {
  final dir = await getDatabasesPath();
  final path = p.join(dir, 'anvil.db');
  return openDatabase(
    path,
    version: 5,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE history(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tool_id TEXT NOT NULL,
          input_names TEXT NOT NULL,   -- JSON array string
          output_paths TEXT NOT NULL,  -- JSON array string
          created_at INTEGER NOT NULL  -- epoch ms
        )
      ''');
      await db.execute('''
        CREATE TABLE settings(
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
      await _createLogs(db);
      await _createChat(db);
    },
    onUpgrade: (db, from, to) async {
      // v1 -> v2: the app log (LogRepository). Existing rows are untouched.
      if (from < 2) await _createLogs(db);
      // v2 -> v3: unified chat (ChatRepository). Existing rows are untouched.
      if (from < 3) await _createChat(db);
      // v3 -> v4: a toolStep's output file path so it can be reopened later.
      // A device still at v3 has the table but not the column; devices at <=2
      // get the full v4 _createChat above, so guard to exactly v3.
      if (from == 3) {
        await db.execute(
          'ALTER TABLE chat_messages ADD COLUMN output_path TEXT',
        );
      }
      // v4 -> v5: greedy sampling defaults for tool calls. Chats created
      // earlier carry per-session sampling columns and would otherwise keep
      // the old high-variance values. A no-op for from < 3 (the _createChat
      // above just made an empty table).
      if (from < 5) {
        await db.execute(
          'UPDATE chat_sessions SET temperature = 0.1, top_k = 1, top_p = 1.0',
        );
      }
    },
  );
}

Future<void> _createLogs(Database db) async {
  await db.execute('''
    CREATE TABLE logs(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      at INTEGER NOT NULL,         -- epoch ms
      level TEXT NOT NULL,         -- info | warn | error
      source TEXT NOT NULL,        -- tool | agent | model | app
      message TEXT NOT NULL,
      detail TEXT
    )
  ''');
  // The screen and the export both read newest-first.
  await db.execute('CREATE INDEX idx_logs_at ON logs(at DESC)');
}

Future<void> _createChat(Database db) async {
  await db.execute('''
    CREATE TABLE chat_sessions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      model_task_id TEXT NOT NULL,      -- e.g. 'agent.llm'
      temperature REAL NOT NULL,
      top_k INTEGER NOT NULL,
      top_p REAL NOT NULL,
      max_output_tokens INTEGER NOT NULL,
      created_at INTEGER NOT NULL,      -- epoch ms
      updated_at INTEGER NOT NULL       -- epoch ms; list order
    )
  ''');
  await db.execute('''
    CREATE TABLE chat_messages(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL,
      role TEXT NOT NULL,               -- user | assistant
      kind TEXT NOT NULL,               -- text | toolStep | failure
      text TEXT NOT NULL,               -- answer/user text; '' for toolStep
      thinking TEXT,                    -- model <think> content, nullable
      tool_label TEXT,                  -- toolStep only
      output_name TEXT,                 -- toolStep only
      output_path TEXT,                 -- toolStep only; reopen/share target
      attachments TEXT NOT NULL,        -- JSON array of {name, ingest, note}
      created_at INTEGER NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_chat_messages_session ON chat_messages(session_id, created_at)',
  );
}
