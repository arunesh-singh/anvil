/// Widget tests for the unified Ask tab: the model gate disables Send and the
/// in-flight assistant bubble streams. No getIt, no engine — the notifier is
/// faked and every watched provider overridden.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/core/chat_repository.dart';
import 'package:anvil/engines/llm_engine.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/ui/agent/chat_controller.dart';
import 'package:anvil/ui/agent/chat_screen.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/theme.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Seeds a state without touching getIt/repositories.
class _FakeChatNotifier extends ChatController {
  _FakeChatNotifier(this._initial);
  final ChatUiState _initial;

  @override
  ChatUiState build() => _initial;
}

Widget _app(
  ModelStatus status, {
  ChatUiState? seed,
  _FakeChatNotifier? notifier,
  LlmStatus? llm,
}) => ProviderScope(
  overrides: [
    modelStatusProvider(ChatSession.defaultModelTaskId)
        .overrideWith((_) => Future.value(status)),
    availableModelsProvider.overrideWith((_) => Future.value(const [])),
    if (llm != null) llmStatusProvider.overrideWith((_) => Stream.value(llm)),
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

  testWidgets('a loading model is named in the bubble, not called thinking', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ModelStatus.cached,
        seed: const ChatUiState(busy: true),
        llm: LlmStatus(
          LlmPhase.loading,
          taskId: 'agent.llm',
          since: DateTime.now().subtract(const Duration(seconds: 7)),
        ),
      ),
    );
    // Spinner animates forever — pump, don't settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Loading Gemma 4 E2B'), findsOneWidget);
    expect(find.textContaining('7s'), findsOneWidget);
    expect(find.text('Thinking\u2026'), findsNothing);
  });
}
