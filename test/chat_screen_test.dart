/// Widget tests for the unified Ask tab: the model gate disables Send, the D6
/// confirm panel is the only path to execution, and the in-flight assistant
/// bubble streams. No getIt, no engine — the notifier is faked and every
/// watched provider overridden.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/agent/agent_session.dart';
import 'package:anvil/agent/arg_validator.dart';
import 'package:anvil/core/chat_repository.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/ui/agent/chat_controller.dart';
import 'package:anvil/ui/agent/chat_screen.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/theme.dart';
import 'package:anvil/ui/widgets/slab.dart';

class _StubTool extends BaseToolModule {
  @override
  ToolMeta get meta => const ToolMeta(
    id: 'grayscale',
    category: ToolCategory.image,
    label: 'Grayscale',
    icon: Icons.filter_b_and_w,
    description: 'Drop the colour.',
    tinywowSlug: 'grayscale',
    acceptedExtensions: ['png'],
  );

  @override
  EngineKind get engine => EngineKind.image;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolSucceeded(ToolResult(files: []));
  }
}

/// Seeds a state and records `confirm()` instead of running a tool. Overrides
/// [build] so no getIt/repository is touched.
class _FakeChatNotifier extends ChatController {
  _FakeChatNotifier(this._initial);
  final ChatUiState _initial;
  int confirms = 0;

  @override
  ChatUiState build() => _initial;

  @override
  Future<void> confirm() async => confirms++;
}

Widget _app(
  ModelStatus status, {
  ChatUiState? seed,
  _FakeChatNotifier? notifier,
}) => ProviderScope(
  overrides: [
    modelStatusProvider('agent.llm').overrideWith((_) => Future.value(status)),
    availableModelsProvider.overrideWith((_) => Future.value(const [])),
    if (notifier != null)
      chatProvider.overrideWith(() => notifier)
    else if (seed != null)
      chatProvider.overrideWith(() => _FakeChatNotifier(seed)),
  ],
  child: MaterialApp(
    theme: darkTheme,
    home: const Scaffold(body: ChatScreen()),
  ),
);

AgentNeedsConfirm _pendingCall() => AgentNeedsConfirm(
  ValidatedCall(
    tool: _StubTool(),
    input: const ToolInput(
      files: [InputFile(path: '/tmp/shot.png', name: 'shot.png')],
      params: {'quality': 80},
    ),
  ),
  1,
);

void main() {
  testWidgets('an incompatible device explains itself and disables Send', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(ModelStatus.incompatible, seed: const ChatUiState()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('more capable device'), findsOneWidget);
    final send = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, 'Send'),
    );
    expect(send.onPressed, isNull);
  });

  testWidgets('a cached model enables Send', (tester) async {
    await tester.pumpWidget(
      _app(ModelStatus.cached, seed: const ChatUiState()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('more capable device'), findsNothing);
    final send = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, 'Send'),
    );
    expect(send.onPressed, isNotNull);
  });

  testWidgets('a pending step shows the confirm gate and Run invokes confirm', (
    tester,
  ) async {
    final notifier = _FakeChatNotifier(ChatUiState(pending: _pendingCall()));
    await tester.pumpWidget(_app(ModelStatus.cached, notifier: notifier));
    await tester.pumpAndSettle();

    expect(find.text('Run this step?'), findsOneWidget);
    expect(find.text('Grayscale'), findsOneWidget);
    expect(find.text('shot.png'), findsOneWidget);
    expect(find.text('quality: 80'), findsOneWidget);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Run'));
    await tester.pump();
    expect(notifier.confirms, 1);
  });

  testWidgets(
    'the in-flight assistant bubble streams text with a Stop button',
    (tester) async {
      await tester.pumpWidget(
        _app(
          ModelStatus.cached,
          seed: const ChatUiState(busy: true, streamingText: 'Working on it'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Working on it'), findsOneWidget);
      expect(find.widgetWithText(SecondaryButton, 'Stop'), findsOneWidget);
      // Streaming in-flight → Send is disabled.
      final send = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Send'),
      );
      expect(send.onPressed, isNull);
    },
  );

  testWidgets('a toolStep message with an output path opens and shares', (
    tester,
  ) async {
    final msg = ChatMessage(
      sessionId: 1,
      role: ChatRole.assistant,
      kind: ChatMessageKind.toolStep,
      text: '',
      toolLabel: 'Add Text to PDF',
      outputName: 'x.pdf',
      outputPath: '/out/x.pdf',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );
    await tester.pumpWidget(
      _app(ModelStatus.cached, seed: ChatUiState(messages: [msg])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add Text to PDF'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
    final row = tester.widget<ToolRow>(find.byType(ToolRow));
    expect(row.onTap, isNotNull);
  });

  testWidgets('a running step shows its live progress line', (tester) async {
    await tester.pumpWidget(
      _app(
        ModelStatus.cached,
        seed: const ChatUiState(busy: true, stepProgress: 'Converting page 1'),
      ),
    );
    // A running step shows a spinner (infinite animation) — pump, don't settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Converting page 1'), findsOneWidget);
    expect(find.widgetWithText(SecondaryButton, 'Stop'), findsOneWidget);
  });
}
