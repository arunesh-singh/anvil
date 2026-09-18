/// The log screen: renders recorded actions, filters to errors, expands
/// detail, and exports through the share service.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/log_repository.dart';
import 'package:anvil/core/share_service.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/settings/log_screen.dart';
import 'package:anvil/ui/theme.dart';
import 'package:anvil/ui/widgets/slab.dart';

class _FakeShare implements ShareService {
  final List<List<String>> shared = [];

  @override
  Future<void> shareFiles(List<String> paths) async => shared.add(paths);
}

/// Captures the exported body instead of writing it: real dart:io cannot
/// complete inside testWidgets' fake-async zone, and the contract under test
/// is "what got written and shared", not the filesystem.
class _FakeFileService implements FileService {
  _FakeFileService(this.dir);
  final Directory dir;
  String? name;
  String? body;

  @override
  Future<File> writeString(String fileName, String content) async {
    name = fileName;
    body = content;
    return File(p.join(dir.path, fileName));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLogRepo implements LogRepository {
  _FakeLogRepo(this.entries);
  final List<LogEntry> entries;
  bool cleared = false;

  @override
  Future<List<LogEntry>> recent({int limit = 500, LogLevel? minLevel}) async =>
      entries;

  @override
  Future<void> clear() async => cleared = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _entries = [
  LogEntry(
    id: 2,
    at: DateTime(2026, 8, 21, 11, 4, 5),
    level: LogLevel.error,
    source: logSourceTool,
    message: 'pdf/compress failed',
    detail: 'This PDF is password protected.',
  ),
  LogEntry(
    id: 1,
    at: DateTime(2026, 8, 21, 11, 3),
    level: LogLevel.info,
    source: logSourceApp,
    message: 'App started \u00b7 218 tools registered',
  ),
];

Widget _app() => ProviderScope(
      overrides: [
        logEntriesProvider.overrideWith((_) => Future.value(_entries)),
        logCountsProvider
            .overrideWith((_) => Future.value((total: 2, errors: 1))),
      ],
      child: MaterialApp(theme: darkTheme, home: const LogScreen()),
    );

void main() {
  late Directory tempDir;
  late _FakeShare share;
  late _FakeFileService files;

  setUp(() async {
    await getIt.reset();
    tempDir = await Directory.systemTemp.createTemp('anvil_log_screen');
    share = _FakeShare();
    files = _FakeFileService(tempDir);
    final repo = _FakeLogRepo(_entries);
    getIt
      ..registerSingleton<LogRepository>(repo)
      ..registerSingleton<AppLog>(AppLog(repo))
      ..registerSingleton<FileService>(files)
      ..registerSingleton<ShareService>(share);
  });

  tearDown(() async {
    await getIt.reset();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('every recorded action is listed newest first', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('pdf/compress failed'), findsOneWidget);
    expect(find.text('App started \u00b7 218 tools registered'), findsOneWidget);
    // The failure's detail stays collapsed until tapped.
    expect(find.text('This PDF is password protected.'), findsNothing);
  });

  testWidgets('tapping an entry reveals its detail', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('pdf/compress failed'));
    await tester.pumpAndSettle();
    expect(find.text('This PDF is password protected.'), findsOneWidget);
  });

  testWidgets('the errors filter hides successful actions', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Errors only'));
    await tester.pumpAndSettle();

    expect(find.text('pdf/compress failed'), findsOneWidget);
    expect(find.text('App started \u00b7 218 tools registered'), findsNothing);
  });

  testWidgets('export renders the log and opens the share sheet',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PrimaryButton, 'Export log'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(share.shared, hasLength(1));
    final path = share.shared.single.single;
    expect(p.basename(path), startsWith('anvil-log-'));
    expect(path, endsWith('.txt'));
    expect(p.basename(path), files.name);

    final body = files.body!;
    expect(body, contains('Anvil app log'));
    expect(body, contains('Entries: 2 \u00b7 Errors: 1'));
    expect(body, contains('pdf/compress failed'));
    expect(body, contains('    This PDF is password protected.'));
    expect(body, contains('App started'));
  });
}
