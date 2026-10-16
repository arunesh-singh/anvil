import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/llm_engine.dart';
import 'package:anvil/models/manifest.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/ui/theme.dart';
import 'package:anvil/ui/tool/editors/write_tool_screen.dart';
import 'package:anvil/ui/widgets/slab.dart';

final _variant = ModelVariant(
  id: 'gemma-test',
  tier: ModelTier.quality,
  url: 'https://example.test/gemma.litertlm',
  sha256: 'b' * 64,
  sizeBytes: 2048,
  runtime: ModelRuntime.task,
  minRamGb: 6,
  accelerator: 'gpu',
  version: '1',
);

/// Answers "Attempt N" and records every prompt.
class _FakeLlmEngine implements LlmEngine {
  final prompts = <String>[];

  @override
  Future<void> ensureLoaded(
    String modelPath, {
    bool supportImage = false,
    ModelFamily family = ModelFamily.gemma4,
    int maxTokens = 4096,
    String? taskId,
  }) async {}

  @override
  Future<String> generate(String p) async {
    prompts.add(p);
    return 'Attempt ${prompts.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeModelManager implements ModelManager {
  @override
  Future<LoadedModel> ensureReady(
    ModelSpec spec, {
    void Function(int received, int total)? onProgress,
  }) async => LoadedModel(
    taskId: spec.taskId,
    variant: _variant,
    filePath: '/tmp/${spec.taskId}.litertlm',
  );

  @override
  Future<ModelStatus> status(String taskId) async => ModelStatus.cached;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Never touches disk: the screen shows `ToolResult.text`, not the file.
class _FakeFileService implements FileService {
  @override
  Future<File> writeString(String fileName, String content) async =>
      File('/tmp/$fileName');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHistory implements HistoryRepository {
  final added = <HistoryRecord>[];

  @override
  Future<int> add(HistoryRecord r) async {
    added.add(r);
    return added.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeLlmEngine llm;
  late _FakeHistory history;

  setUp(() async {
    await getIt.reset();
    llm = _FakeLlmEngine();
    history = _FakeHistory();
    getIt
      ..registerSingleton<LlmEngine>(llm)
      ..registerSingleton<ModelManager>(_FakeModelManager())
      ..registerSingleton<FileService>(_FakeFileService())
      ..registerSingleton<HistoryRepository>(history);
  });

  tearDown(() => getIt.reset());

  Future<void> pump(WidgetTester tester, String id) async {
    final tool = ToolRegistry(buildTools()).byId(id)!;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: darkTheme,
          home: WriteToolScreen(tool: tool),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PrimaryButton run(WidgetTester tester) =>
      tester.widget<PrimaryButton>(find.byType(PrimaryButton));

  // A rerun first awaits cancelling the previous run's finished stream
  // subscription, which only settles on the real event loop.
  Future<void> tapRun(WidgetTester tester, Finder f) async {
    await tester.runAsync(() async {
      await tester.tap(f);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('tone-of-voice: result lands inline, Try again pages to 2 of 2', (
    tester,
  ) async {
    await pump(tester, 'write/tone-of-voice');
    expect(run(tester).label, 'Rewrite');
    // Nothing to rewrite yet.
    expect(run(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'cant make it');
    await tester.tap(find.text('Shorter'));
    await tester.tap(find.text('Longer'));
    await tester.pump();
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();

    // Inline result, still on this screen.
    expect(find.byType(WriteToolScreen), findsOneWidget);
    expect(find.text('Attempt 1'), findsOneWidget);
    expect(find.text('1 of 1'), findsNothing);
    expect(history.added, hasLength(1));
    // The chip and length reached the prompt.
    expect(llm.prompts.single, startsWith('Condense'));
    expect(llm.prompts.single, contains('Make it longer'));

    await tester.ensureVisible(find.text('Try again'));
    await tapRun(tester, find.text('Try again'));
    expect(find.text('Attempt 2'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(llm.prompts[1], llm.prompts[0]);

    // Page back to the first attempt.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('Attempt 1'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);

    // Compare shows the original above the result.
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('cant make it'), findsNWidgets(2));

    // A fresh Run starts a new set of attempts.
    await tapRun(tester, find.byType(PrimaryButton));
    expect(find.text('Attempt 3'), findsOneWidget);
    expect(find.textContaining(' of '), findsNothing);
  });

  testWidgets('custom tone pill sends the typed tone', (tester) async {
    await pump(tester, 'write/tone-of-voice');
    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.ensureVisible(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    // Custom with no tone typed cannot run.
    expect(run(tester).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Custom tone'),
      'wry',
    );
    await tester.pump();
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(llm.prompts.single, contains('in a wry tone'));
  });

  testWidgets('word-counter shows its report inline without model pills', (
    tester,
  ) async {
    await pump(tester, 'write/word-counter');
    expect(run(tester).label, 'Count');
    await tester.enterText(find.byType(TextField).first, 'one two three.');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byType(PrimaryButton));
      // The counter runs off-thread (a real isolate).
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Words: 3'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(llm.prompts, isEmpty);
  });
}
