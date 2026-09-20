/// Host tests for the Needle 3 backend's two pure pieces: the envelope →
/// [LlmEvent] mapping and the trigger derivation. No FFI, no device — the
/// chat adapter is driven through a scripted [NeedleTransport], the same way
/// the agent loop is driven through a scripted [LlmChat].
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_vocab.dart';
import 'package:anvil/engines/llm_chat.dart';
import 'package:anvil/engines/needle_engine.dart';
import 'package:anvil/engines/needle_ffi.dart';

/// Replays canned envelopes and records every input the adapter sends.
class _ScriptedTransport implements NeedleTransport {
  _ScriptedTransport(this._envelopes);
  final List<String> _envelopes;

  final List<String> completed = [];

  @override
  Future<void> load(String weightsPath) async {}

  @override
  Future<void> init({
    required String system,
    required String toolsJson,
  }) async {}

  @override
  Future<String> complete(String input, {required int maxNewTokens}) async {
    completed.add(input);
    return _envelopes.removeAt(0);
  }

  @override
  Future<void> reset() async {}

  @override
  Future<void> dispose() async {}
}

/// A real recorded turn (macos-arm64 build of the shipped needle3.cact).
const String _callEnvelope = '''
{"type":"call","success":true,"error":null,"error_code":null,"reason":null,
 "function_calls":[{"name":"pdf_compress",
   "arguments":{"file":"/data/user/0/com.arunesh.anvil/cache/report.pdf"}}],
 "suppressed_calls":[],
 "reasoning":"'compress this PDF' -> file '/…/report.pdf'",
 "confidence":0.6521,"prefill_tps":719.5,"decode_tps":436.0,
 "peak_ram_mb":133.8,"validation":{"ungrounded":[],"negation":false}}
''';

NeedleChat _chat(_ScriptedTransport transport) =>
    NeedleChat(transport: transport, maxOutputTokens: 512);

void main() {
  group('NeedleChat', () {
    test('a call envelope becomes one tool call with its arguments', () async {
      final transport = _ScriptedTransport([_callEnvelope]);
      final events = await _chat(
        transport,
      ).send('make this pdf smaller').toList();
      final call = events.single as LlmToolCall;
      expect(call.name, 'pdf_compress');
      expect(call.args, {
        'file': '/data/user/0/com.arunesh.anvil/cache/report.pdf',
      });
    });

    test('a respond envelope ends the turn with a non-empty answer', () async {
      // Needle emits no prose; an empty answer here would be read as a failed
      // turn and nudged instead of finishing the chain.
      final transport = _ScriptedTransport([
        '{"type":"respond","function_calls":[],"suppressed_calls":[]}',
      ]);
      final events = await _chat(transport).send('done?').toList();
      expect((events.single as LlmTurnDone).text, kNeedleDone);
    });

    test('a refusal ends the turn empty so the agent can recover', () async {
      final transport = _ScriptedTransport([
        '{"type":"call","function_calls":[],"suppressed_calls":'
            '[{"name":"pdf_merge","reason":"ungrounded"}],'
            '"reasoning":"no grounded file"}',
      ]);
      final events = await _chat(transport).send('capital of France?').toList();
      expect((events.single as LlmTurnDone).text, isEmpty);
    });

    test('an unparseable envelope ends the turn empty', () async {
      final transport = _ScriptedTransport(['{"type":"call", trunca']);
      final events = await _chat(transport).send('go').toList();
      expect((events.single as LlmTurnDone).text, isEmpty);
    });

    test('a tool result is handed over as bare JSON', () async {
      final transport = _ScriptedTransport([
        '{"type":"respond","function_calls":[]}',
      ]);
      await _chat(transport)
          .sendToolResult(
            toolName: 'pdf_compress',
            response: {'error': 'no file'},
          )
          .toList();
      expect(transport.completed.single, '{"error":"no file"}');
    });

    test('a transport failure surfaces as a user-facing message', () async {
      final chat = NeedleChat(
        transport: _ScriptedTransport(const []),
        maxOutputTokens: 512,
      );
      // The scripted transport throws RangeError once the script runs out;
      // the adapter must not leak that to the chain.
      await expectLater(chat.send('go').toList(), throwsA(isA<Exception>()));
    });

    test('a closed chat yields nothing', () async {
      final transport = _ScriptedTransport([_callEnvelope]);
      final chat = _chat(transport);
      await chat.close();
      expect(await chat.send('go').toList(), isEmpty);
      expect(transport.completed, isEmpty);
    });
  });

  group('needleTriggersFor', () {
    final registry = ToolRegistry(buildTools());

    test('pdf/compress routes on its synonyms, never on its category', () {
      final trigger = needleTriggersFor(registry.byId('pdf/compress')!.meta);
      expect(trigger, hasLength(1));
      final pattern = RegExp(trigger.single, caseSensitive: false);
      expect(pattern.hasMatch('compress this file'), isTrue);
      expect(pattern.hasMatch('make it shrink'), isTrue);
      expect(pattern.hasMatch('make this smaller'), isTrue);
      // A `pdf` trigger would fire on every PDF tool at once.
      expect(pattern.hasMatch('this pdf'), isFalse);
    });

    test('pdf/merge routes on combine and join', () {
      final pattern = RegExp(
        needleTriggersFor(registry.byId('pdf/merge')!.meta).single,
        caseSensitive: false,
      );
      expect(pattern.hasMatch('combine these'), isTrue);
      expect(pattern.hasMatch('join them'), isTrue);
      expect(pattern.hasMatch('merge'), isTrue);
    });

    test('every agent-callable tool declares at most one usable regex', () {
      for (final tool in registry.all) {
        if (!tool.meta.agentCallable) continue;
        final triggers = needleTriggersFor(tool.meta);
        expect(
          triggers.length,
          lessThanOrEqualTo(1),
          reason: tool.meta.qualifiedId,
        );
        for (final t in triggers) {
          expect(
            () => RegExp(t),
            returnsNormally,
            reason: tool.meta.qualifiedId,
          );
        }
      }
    });
  });

  group('needleToolsJson', () {
    test('carries the triggers through to the engine payload', () {
      final schema = ToolRegistry(buildTools()).byId('pdf/compress')!.fnSchema;
      final decoded = jsonDecode(needleToolsJson([schema])) as List;
      final entry = (decoded.single as Map).cast<String, dynamic>();
      expect(entry['name'], 'pdf_compress');
      expect(entry['triggers'], isNotEmpty);
      expect(entry['parameters'], isA<Map>());
      // Routing metadata, not an argument.
      expect(
        (entry['parameters'] as Map)['properties'],
        isNot(contains('triggers')),
      );
    });
  });
}
