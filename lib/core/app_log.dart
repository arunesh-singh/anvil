/// Write side of the app log, plus the export.
///
/// Call sites use the top-level [logAction] / [logWarning] / [logError]
/// helpers: they are fire-and-forget, never throw, and no-op when no [AppLog]
/// is registered (host tests of unrelated code). Logging MUST NOT be able to
/// break a tool run.
library;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/log_repository.dart';
import 'package:anvil/core/tool_io.dart';

/// Source tags. Kept as constants so the filter and the export stay consistent.
const String logSourceTool = 'tool';
const String logSourceAgent = 'agent';
const String logSourceModel = 'model';
const String logSourceApp = 'app';

/// Stack traces are truncated to this many lines: enough to place a crash,
/// bounded so one bad frame cannot bloat the table.
const int _maxStackLines = 12;

/// Entries beyond this count are trimmed away (oldest first).
const int _keepEntries = 2000;

/// Serializes writes to [LogRepository] so entry order matches call order and
/// a slow insert never blocks the caller.
class AppLog {
  AppLog(this._repo);
  final LogRepository _repo;

  /// Head of the write chain. Lazily created by the first [write] so the
  /// chain's completion callbacks belong to the zone that actually logs, not
  /// to whichever zone happened to construct this object; also costs nothing
  /// for an [AppLog] that never gets written to.
  Future<void>? _tail;
  int _sinceTrim = 0;

  void write(
    LogLevel level,
    String source,
    String message, {
    String? detail,
  }) {
    final entry = LogEntry(
      at: DateTime.now(),
      level: level,
      source: source,
      message: message,
      detail: detail,
    );
    _tail = (_tail ?? Future<void>.value()).then((_) async {
      await _repo.add(entry);
      if (++_sinceTrim >= 64) {
        _sinceTrim = 0;
        await _repo.trim(keep: _keepEntries);
      }
      // A failed write is swallowed on purpose: the log is diagnostics, never
      // a precondition for the action being logged.
    }).catchError((_) {});
  }

  /// Awaits every queued write. Used by the export and by tests.
  Future<void> flush() => _tail ?? Future<void>.value();
}

AppLog? _log() => getIt.isRegistered<AppLog>() ? getIt<AppLog>() : null;

/// Records something the app did (tool started, step confirmed, model cached).
void logAction(String source, String message, {String? detail}) =>
    _log()?.write(LogLevel.info, source, message, detail: detail);

/// Records a degraded-but-handled outcome (cancelled run, agent gave up).
void logWarning(String source, String message, {String? detail}) =>
    _log()?.write(LogLevel.warn, source, message, detail: detail);

/// Records a failure the user saw. [error]/[stack] are folded into the detail.
void logError(
  String source,
  String message, {
  Object? error,
  StackTrace? stack,
  String? detail,
}) =>
    _log()?.write(
      LogLevel.error,
      source,
      message,
      detail: _detailOf(detail, error, stack),
    );

String? _detailOf(String? detail, Object? error, StackTrace? stack) {
  final parts = <String>[
    if (detail != null && detail.isNotEmpty) detail,
    if (error != null) '$error',
    if (stack != null) _headOf(stack),
  ];
  return parts.isEmpty ? null : parts.join('\n');
}

String _headOf(StackTrace stack) {
  final lines = stack.toString().split('\n');
  return lines.take(_maxStackLines).join('\n');
}

/// Writes the whole log to a shareable `.txt` in the outputs directory.
///
/// Throws [ToolException] when no log is available (nothing registered yet), so
/// the UI can report it like any other failure.
Future<OutputFile> exportLog() async {
  if (!getIt.isRegistered<LogRepository>()) {
    throw const ToolException('The app log is not available yet.');
  }
  await _log()?.flush();
  final entries = await getIt<LogRepository>().recent(limit: _keepEntries);
  final now = DateTime.now();
  final body = formatLogExport(entries, generatedAt: now);
  final name = 'anvil-log-${_stamp(now)}.txt';
  final file = await getIt<FileService>().writeString(name, body);
  return OutputFile(path: file.path, name: name, mimeType: 'text/plain');
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}'
      '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
}
