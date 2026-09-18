/// Behaviour of the app log: writes are ordered and levelled, a failing log
/// never breaks its caller, tool runs are recorded through [JobNotifier], and
/// the export renders a readable file.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/log_repository.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tool/job_controller.dart';

class _FakeLogRepo implements LogRepository {
  final List<LogEntry> added = [];
  int trims = 0;
  bool failWrites = false;

  @override
  Future<int> add(LogEntry e) async {
    if (failWrites) throw StateError('disk full');
    added.add(e);
    return added.length;
  }

  @override
  Future<List<LogEntry>> recent({int limit = 500, LogLevel? minLevel}) async => [
        for (final e in added.reversed)
          if (minLevel == null || e.level.index >= minLevel.index) e,
      ].take(limit).toList();

  @override
  Future<({int errors, int total})> counts() async => (
        total: added.length,
        errors: added.where((e) => e.level == LogLevel.error).length,
      );

  @override
  Future<void> clear() async => added.clear();

  @override
  Future<void> trim({int keep = 2000}) async => trims++;
}

class _FakeHistoryRepo implements HistoryRepository {
  @override
  Future<int> add(HistoryRecord r) async => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTool extends BaseToolModule {
  _FakeTool(this._stream);
  final Stream<ToolProgress> Function() _stream;

  @override
  ToolMeta get meta => const ToolMeta(
        id: 'csv-to-json',
        category: ToolCategory.converter,
        label: 'CSV to JSON',
        icon: Icons.abc,
        description: 'convert',
        tinywowSlug: 'csv-to-json',
        acceptedExtensions: ['csv'],
      );

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) => _stream();
}

const _input = ToolInput(
  files: [InputFile(path: '/tmp/rows.csv', name: 'rows.csv')],
  params: {'rowsPerFile': 100},
);

Future<void> _settle(ProviderContainer c) async {
  for (var i = 0; i < 50; i++) {
    if (c.read(jobProvider) is! JobRunning) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  late _FakeLogRepo repo;
  late AppLog log;

  setUp(() async {
    await getIt.reset();
    repo = _FakeLogRepo();
    log = AppLog(repo);
    getIt
      ..registerSingleton<LogRepository>(repo)
      ..registerSingleton<AppLog>(log)
      ..registerSingleton<HistoryRepository>(_FakeHistoryRepo());
  });

  tearDown(() async => getIt.reset());

  test('helpers record level, source, and detail in call order', () async {
    logAction(logSourceTool, 'Run pdf/compress', detail: 'a.pdf');
    logWarning(logSourceApp, 'Run stopped by the user');
    logError(logSourceModel, 'Download failed',
        error: StateError('404'), stack: StackTrace.current);
    await log.flush();

    expect(repo.added.map((e) => e.level),
        [LogLevel.info, LogLevel.warn, LogLevel.error]);
    expect(repo.added.map((e) => e.source),
        [logSourceTool, logSourceApp, logSourceModel]);
    expect(repo.added.first.detail, 'a.pdf');
    // error + stack are folded into one detail blob.
    expect(repo.added.last.detail, contains('404'));
    expect(repo.added.last.detail!.split('\n').length, greaterThan(1));
  });

  test('a stack trace is truncated so one frame cannot bloat the row', () async {
    logError(logSourceApp, 'boom',
        stack: StackTrace.fromString(
            List.generate(80, (i) => '#$i frame').join('\n')));
    await log.flush();
    expect(repo.added.single.detail!.split('\n'), hasLength(12));
  });

  test('a failing log write never throws into the caller', () async {
    repo.failWrites = true;
    logAction(logSourceApp, 'still fine');
    await log.flush();
    expect(repo.added, isEmpty);

    // The queue survives the failure: the next write lands.
    repo.failWrites = false;
    logAction(logSourceApp, 'second');
    await log.flush();
    expect(repo.added.single.message, 'second');
  });

  test('writes are trimmed once past the retention batch', () async {
    for (var i = 0; i < 64; i++) {
      logAction(logSourceApp, 'entry $i');
    }
    await log.flush();
    expect(repo.added, hasLength(64));
    expect(repo.trims, 1);
  });

  test('no registered log means logging is a silent no-op', () async {
    await getIt.reset();
    expect(() => logAction(logSourceApp, 'dropped'), returnsNormally);
  });

  test('a tool run logs its start and its outputs', () async {
    final tool = _FakeTool(() async* {
      yield const ToolRunning(message: 'go');
      yield const ToolSucceeded(ToolResult(
        files: [OutputFile(path: '/tmp/out.json', name: 'out.json')],
      ));
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(jobProvider, (_, _) {}, fireImmediately: true);

    await container.read(jobProvider.notifier).start(tool, _input);
    await _settle(container);
    await log.flush();

    final messages = repo.added.map((e) => e.message).toList();
    expect(messages.first, 'Run converter/csv-to-json');
    expect(messages.last, contains('finished'));
    // Input names and params are recorded; file contents never are.
    expect(repo.added.first.detail, contains('rows.csv'));
    expect(repo.added.first.detail, contains('rowsPerFile=100'));
    expect(repo.added.every((e) => e.level == LogLevel.info), isTrue);
  });

  test('a failing tool run is logged as an error with its message', () async {
    final tool = _FakeTool(() async* {
      throw const ToolException('That file is not valid CSV.');
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(jobProvider, (_, _) {}, fireImmediately: true);

    await container.read(jobProvider.notifier).start(tool, _input);
    await _settle(container);
    await log.flush();

    final failure =
        repo.added.singleWhere((e) => e.level == LogLevel.error);
    expect(failure.source, logSourceTool);
    expect(failure.message, 'converter/csv-to-json failed');
    expect(failure.detail, contains('That file is not valid CSV.'));
  });

  test('the export renders a header, one line per entry, and detail',
      () async {
    final body = formatLogExport(
      [
        LogEntry(
          at: DateTime.utc(2026, 8, 21, 9, 15, 30),
          level: LogLevel.error,
          source: logSourceTool,
          message: 'pdf/compress failed',
          detail: 'Password protected\n#0 main',
        ),
        LogEntry(
          at: DateTime.utc(2026, 8, 21, 9, 15),
          level: LogLevel.info,
          source: logSourceApp,
          message: 'App started',
        ),
      ],
      generatedAt: DateTime.utc(2026, 8, 21, 10),
    );

    expect(body, contains('Anvil app log'));
    expect(body, contains('Entries: 2 \u00b7 Errors: 1'));
    expect(body, contains('2026-08-21T09:15:30.000Z  ERROR  tool    '
        'pdf/compress failed'));
    // Detail lines are indented under their entry.
    expect(body, contains('\n    Password protected\n    #0 main\n'));
    expect(body, contains('INFO   app     App started'));
  });
}
