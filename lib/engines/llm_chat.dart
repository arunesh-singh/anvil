/// The plugin-free function-calling contract the Phase-3 agent talks to.
///
/// Lives in `engines/` (not `agent/`) so the dependency direction stays
/// agent → engine, like every tool: only [LlmEngine] imports `flutter_gemma`,
/// and `lib/agent/` stays host-testable with a scripted [LlmChat].
library;

import 'dart:typed_data';

/// One streamed turn: zero or more thinking/text deltas, then exactly one
/// terminal event — an [LlmToolCall] (a call turn) or an [LlmTurnDone] (a text
/// turn). On a call turn we stop at the first call (D6: one tool per step).
sealed class LlmEvent {
  const LlmEvent();
}

/// A chunk of the model's `<think>` content.
class LlmThinkingDelta extends LlmEvent {
  final String text;
  const LlmThinkingDelta(this.text);
}

/// A chunk of the visible answer.
class LlmTextDelta extends LlmEvent {
  final String text;
  const LlmTextDelta(this.text);
}

/// The turn resolved to a single tool call (D6: first call only).
class LlmToolCall extends LlmEvent {
  final String name;
  final Map<String, dynamic> args;
  const LlmToolCall({required this.name, required this.args});
}

/// The turn resolved to plain text. [text] is the full accumulated answer.
class LlmTurnDone extends LlmEvent {
  final String text;
  const LlmTurnDone(this.text);
}

/// One function-calling conversation. Implemented by the flutter_gemma adapter
/// in `llm_engine.dart`; faked in host tests of the agent loop.
abstract interface class LlmChat {
  Stream<LlmEvent> send(String text, {List<Uint8List> images});
  Stream<LlmEvent> sendToolResult({
    required String toolName,
    required Map<String, dynamic> response,
  });
  Future<void> close();
}
