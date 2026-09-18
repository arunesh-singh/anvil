import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// One row of run history.
class HistoryRecord {
  final int? id;
  final String toolId;
  final List<String> inputNames;
  final List<String> outputPaths;
  final DateTime createdAt;

  const HistoryRecord({
    this.id,
    required this.toolId,
    required this.inputNames,
    required this.outputPaths,
    required this.createdAt,
  });
}

/// Persists and reads run history. List columns are stored as JSON strings.
class HistoryRepository {
  HistoryRepository(this._db);
  final Database _db;

  Future<int> add(HistoryRecord r) {
    return _db.insert('history', {
      'tool_id': r.toolId,
      'input_names': jsonEncode(r.inputNames),
      'output_paths': jsonEncode(r.outputPaths),
      'created_at': r.createdAt.millisecondsSinceEpoch,
    });
  }

  Future<List<HistoryRecord>> all() async {
    final rows = await _db.query('history', orderBy: 'created_at DESC');
    return [for (final row in rows) _fromRow(row)];
  }

  /// Deletes every history row. Callers clear output files separately.
  Future<void> clear() => _db.delete('history');

  /// Removes and returns rows created strictly before [cutoff]. The caller
  /// deletes the returned records' [HistoryRecord.outputPaths] from disk.
  Future<List<HistoryRecord>> pruneOlderThan(DateTime cutoff) async {
    final ms = cutoff.millisecondsSinceEpoch;
    final rows = await _db.query(
      'history',
      where: 'created_at < ?',
      whereArgs: [ms],
    );
    final removed = [for (final row in rows) _fromRow(row)];
    await _db.delete('history', where: 'created_at < ?', whereArgs: [ms]);
    return removed;
  }

  HistoryRecord _fromRow(Map<String, Object?> row) {
    return HistoryRecord(
      id: row['id'] as int?,
      toolId: row['tool_id'] as String,
      inputNames: _decodeList(row['input_names'] as String),
      outputPaths: _decodeList(row['output_paths'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  List<String> _decodeList(String json) =>
      [for (final e in jsonDecode(json) as List) e as String];
}
