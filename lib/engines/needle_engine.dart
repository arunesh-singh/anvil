/// Maps Needle 3's JSON envelope onto the plugin-free [LlmChat] seam.
///
/// Needle is a grammar-constrained function caller with NO free-text
/// generation: a turn is one non-streaming call that returns either a routed
/// function call or a refusal. That fits [LlmChat] exactly — each stream here
/// yields exactly one terminal event — so `AgentSession`, `validateCall`, the
/// repair budget and the chain loop run unchanged against it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/llm_chat.dart';
import 'package:anvil/engines/needle_ffi.dart';

/// The answer a needle turn ends on. Needle emits no prose: after a tool
/// result it replies `{"type":"respond","function_calls":[]}`, and an empty
/// string there would be read as a failed turn and nudged.
const String kNeedleDone = 'Done.';

/// User-facing translation of [kNeedleUnsupportedAbi]: Needle publishes no
/// x86_64 Android engine, so `libneedle_ffi.so` is absent on an emulator.
const String kNeedleUnsupportedDevice =
    'The offline assistant needs an ARM64/ARMv7 phone; this device is not '
    'supported.';

/// Turns a transport failure into the message the user should see.
ToolException needleFailure(Object error) {
  final message = error is NeedleException ? error.message : '$error';
  return ToolException(
    message == kNeedleUnsupportedAbi
        ? kNeedleUnsupportedDevice
        : 'The offline assistant failed: $message',
  );
}

class NeedleChat implements LlmChat {
  NeedleChat({required this.transport, required int maxOutputTokens})
    : // Needle's own default is 512; below 128 a multi-argument call gets
      // cut off mid-envelope.
      _maxNewTokens = maxOutputTokens.clamp(128, 512);

  final NeedleTransport transport;
  final int _maxNewTokens;
  bool _closed = false;

  /// [images] is ignored: Needle is text-only and its manifest variant sets
  /// `supportsImage: false`, so the controller never produces any.
  @override
  Stream<LlmEvent> send(String text, {List<Uint8List> images = const []}) =>
      _turn(text);

  /// Needle treats a turn whose text parses as JSON as a tool result, which is
  /// exactly the shape `AgentSession` sends for both results and `{'error':…}`
  /// repairs.
  @override
  Stream<LlmEvent> sendToolResult({
    required String toolName,
    required Map<String, dynamic> response,
  }) => _turn(jsonEncode(response));

  /// Marks the conversation closed. The engine keeps no per-chat state (a new
  /// chat re-`init`s) and has no cancel API, so a turn already in flight is
  /// awaited by the transport queue and its result dropped here.
  @override
  Future<void> close() async {
    _closed = true;
  }

  Stream<LlmEvent> _turn(String input) async* {
    if (_closed) return;
    final String raw;
    try {
      raw = await transport.complete(input, maxNewTokens: _maxNewTokens);
    } catch (e) {
      throw needleFailure(e);
    }
    if (_closed) return;
    yield _mapEnvelope(raw);
  }

  LlmEvent _mapEnvelope(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      logWarning(
        logSourceAgent,
        'Needle envelope did not parse',
        detail: _clip(raw, 400),
      );
      return const LlmTurnDone('');
    }
    if (decoded is! Map) {
      logWarning(
        logSourceAgent,
        'Needle envelope was not an object',
        detail: _clip(raw, 400),
      );
      return const LlmTurnDone('');
    }
    final envelope = decoded.cast<String, dynamic>();
    final calls = envelope['function_calls'];
    // D6 / `_GemmaLlmChat._drive`: one tool per step, the first call only.
    if (calls is List && calls.isNotEmpty && calls.first is Map) {
      final call = (calls.first as Map).cast<String, dynamic>();
      final name = call['name'];
      if (name is String && name.isNotEmpty) {
        final args = call['arguments'];
        logAction(
          logSourceAgent,
          'Needle call: $name',
          detail:
              'confidence: ${envelope['confidence']}\n'
              'reasoning: ${envelope['reasoning']}\n'
              'arguments: ${jsonEncode(args)}',
        );
        return LlmToolCall(
          name: name,
          args: args is Map ? args.cast<String, dynamic>() : const {},
        );
      }
    }
    if (envelope['type'] == 'respond') return const LlmTurnDone(kNeedleDone);
    // A `call` envelope with no calls is Needle's refusal (everything it
    // considered is parked in `suppressed_calls`), and so is any type we do
    // not know. An empty turn drives AgentSession's existing recovery: one
    // nudge, then AgentStuck, then the controller's fallback proposal.
    logWarning(
      logSourceAgent,
      'Needle refused',
      detail:
          'reasoning: ${envelope['reasoning']}\n'
          'suppressed: ${jsonEncode(envelope['suppressed_calls'])}',
    );
    return const LlmTurnDone('');
  }
}

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';
