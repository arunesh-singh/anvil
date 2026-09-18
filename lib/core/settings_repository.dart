import 'package:flutter/material.dart' show ThemeMode;
import 'package:sqflite/sqflite.dart';

/// Reads/writes user settings from the key/value `settings` table.
///
/// [ThemeMode] is a plain enum from material; storing it here keeps the UI layer
/// thin. The DB persists the lowercase name ('system'|'light'|'dark').
class SettingsRepository {
  SettingsRepository(this._db);
  final Database _db;

  static const _themeKey = 'theme_mode';
  static const _retentionKey = 'retention_days';

  Future<ThemeMode> getThemeMode() async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_themeKey],
      limit: 1,
    );
    if (rows.isEmpty) return ThemeMode.system;
    return switch (rows.first['value'] as String) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _db.insert('settings', {
      'key': _themeKey,
      'value': mode.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Days to keep results before startup pruning removes them. `0` = forever.
  /// Defaults to 30 when unset or unparseable.
  Future<int> getRetentionDays() async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_retentionKey],
      limit: 1,
    );
    if (rows.isEmpty) return 30;
    return int.tryParse(rows.first['value'] as String) ?? 30;
  }

  Future<void> setRetentionDays(int days) async {
    await _db.insert('settings', {
      'key': _retentionKey,
      'value': days.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
