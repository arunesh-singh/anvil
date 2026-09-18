/// The app log: a durable, bounded record of what the app did and what broke.
///
/// Every user-visible action (tool run, agent step, model download) and every
/// surfaced failure lands here, so a user can see what happened offline and
/// hand us one exported file instead of a bug report from memory.
///
/// Storage mirrors [HistoryRepository]: a plain sqflite table, no codegen.
library;

import 'package:sqflite/sqflite.dart';

/// Severity of one log line. Ordered: [info] < warn < error.
enum LogLevel {
  info,
  warn,
  error;

  static LogLevel parse(String raw) => switch (raw) {
        'warn' => warn,
        'error' => error,
        _ => info,
      };
}

/// One recorded action or failure.
class LogEntry {
  final int? id;
  final DateTime at;
  final LogLevel level;

  /// Coarse origin: `tool`, `agent`, `model`, `app`.
  final String source;

  /// One-line summary shown in the list.
  final String message;

  /// Optional multi-line context (error text, stack head, arguments).
  final String? detail;

  const LogEntry({
    this.id,
    required this.at,
    required this.level,
    required this.source,
    required this.message,
    this.detail,
  });
}

/// Persists and reads the app log, newest first.
class LogRepository {
  LogRepository(this._db);
  final Database _db;

  Future<int> add(LogEntry e) => _db.insert('logs', {
        'at': e.at.millisecondsSinceEpoch,
        'level': e.level.name,
        'source': e.source,
        'message': e.message,
        'detail': e.detail,
      });

  /// Newest [limit] entries, optionally only [level] and above.
  Future<List<LogEntry>> recent({int limit = 500, LogLevel? minLevel}) async {
    final rows = await _db.query(
      'logs',
      where: minLevel == null || minLevel == LogLevel.info
          ? null
          : 'level IN (${_atLeast(minLevel).map((l) => "'${l.name}'").join(',')})',
      orderBy: 'at DESC, id DESC',
      limit: limit,
    );
    return [for (final row in rows) _fromRow(row)];
  }

  /// Total entries and how many of them are errors — the badge on the
  /// diagnostics row, in one query instead of two list reads.
  Future<({int total, int errors})> counts() async {
    final rows = await _db.rawQuery(
      "SELECT COUNT(*) AS total, "
      "SUM(CASE WHEN level = 'error' THEN 1 ELSE 0 END) AS errors FROM logs",
    );
    final row = rows.first;
    return (
      total: (row['total'] as int?) ?? 0,
      errors: (row['errors'] as int?) ?? 0,
    );
  }

  Future<void> clear() => _db.delete('logs');

  /// Drops everything but the newest [keep] entries. Ids are AUTOINCREMENT, so
  /// this is one primary-key range delete rather than a sort of the whole table.
  Future<void> trim({int keep = 2000}) async {
    final rows = await _db.rawQuery('SELECT MAX(id) AS maxId FROM logs');
    final maxId = rows.first['maxId'] as int?;
    if (maxId == null || maxId <= keep) return;
    await _db.delete('logs', where: 'id <= ?', whereArgs: [maxId - keep]);
  }

  static List<LogLevel> _atLeast(LogLevel min) =>
      [for (final l in LogLevel.values) if (l.index >= min.index) l];

  LogEntry _fromRow(Map<String, Object?> row) => LogEntry(
        id: row['id'] as int?,
        at: DateTime.fromMillisecondsSinceEpoch(row['at'] as int),
        level: LogLevel.parse(row['level'] as String),
        source: row['source'] as String,
        message: row['message'] as String,
        detail: row['detail'] as String?,
      );
}

/// Renders [entries] (newest first) as the exported plain-text log: a short
/// header, then one `timestamp  LEVEL  source  message` line per entry with
/// indented detail. Pure — host-tested.
String formatLogExport(List<LogEntry> entries, {required DateTime generatedAt}) {
  final errors = entries.where((e) => e.level == LogLevel.error).length;
  final out = StringBuffer()
    ..writeln('Anvil app log')
    ..writeln('Exported: ${generatedAt.toIso8601String()}')
    ..writeln('Entries: ${entries.length} \u00b7 Errors: $errors')
    ..writeln('All processing is on-device; this file contains only local '
        'file names and error text.')
    ..writeln('-' * 60);
  for (final e in entries) {
    out.writeln('${e.at.toIso8601String()}  '
        '${e.level.name.toUpperCase().padRight(5)}  '
        '${e.source.padRight(6)}  ${e.message}');
    final detail = e.detail;
    if (detail != null && detail.trim().isNotEmpty) {
      for (final line in detail.trimRight().split('\n')) {
        out.writeln('    $line');
      }
    }
  }
  return out.toString();
}
