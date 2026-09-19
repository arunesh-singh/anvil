/// Pure host tests for the Phase-3 agent core: arg validation (the mandatory
/// pre-execution gate, R3), the deterministic tool shortlist, and the tool-call
/// loop. No getIt, no plugin, no device.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/agent/agent_session.dart';
import 'package:anvil/agent/arg_validator.dart';
import 'package:anvil/agent/chain_prompt.dart';
import 'package:anvil/agent/tool_shortlist.dart';
import 'package:anvil/core/fn_schema.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/llm_chat.dart';

/// A scripted chat: each turn is a list of [LlmEvent]s streamed by one
/// send/sendToolResult call; records everything sent.
class _FakeChat implements LlmChat {
  _FakeChat(this._turns);
  final List<List<LlmEvent>> _turns;

  final List<String> sent = [];
  final List<(String, Map<String, dynamic>)> toolResults = [];
  bool closed = false;

  Stream<LlmEvent> _emit() async* {
    final turn = _turns.removeAt(0);
    for (final e in turn) {
      yield e;
    }
  }

  @override
  Stream<LlmEvent> send(String text, {List<Uint8List> images = const []}) {
    sent.add(text);
    return _emit();
  }

  @override
  Stream<LlmEvent> sendToolResult({
    required String toolName,
    required Map<String, dynamic> response,
  }) {
    toolResults.add((toolName, response));
    return _emit();
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// A stand-in tool: no engine, never run in these tests.
class _StubTool extends BaseToolModule {
  _StubTool(this.meta);
  @override
  final ToolMeta meta;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolSucceeded(ToolResult(files: []));
  }
}

ToolMeta _meta({
  String id = 'compress',
  ToolCategory category = ToolCategory.pdf,
  List<String> accepts = const ['pdf'],
  List<ToolParam> params = const [],
  bool acceptsMultiple = false,
  bool requiresInput = true,
}) => ToolMeta(
  id: id,
  category: category,
  label: 'Compress PDF',
  icon: Icons.compress,
  description: 'Shrink a PDF.',
  tinywowSlug: id,
  acceptedExtensions: accepts,
  params: params,
  acceptsMultiple: acceptsMultiple,
  requiresInput: requiresInput,
);

bool _always(String _) => true;
bool _never(String _) => false;

void main() {
  group('validateCall', () {
    final tool = _StubTool(
      _meta(
        params: const [
          ToolParam(key: 'imageQuality', label: 'Quality', defaultValue: 60),
          ToolParam(key: 'note', label: 'Note', type: ToolParamType.text),
        ],
      ),
    );

    test('rejects an unknown argument key', () {
      expect(
        () => validateCall(tool, {
          'file': '/a.pdf',
          'quality': 3,
        }, fileExists: _always),
        throwsA(
          isA<InvalidCallException>().having(
            (e) => e.message,
            'message',
            contains("Unknown argument 'quality'"),
          ),
        ),
      );
    });

    test('rejects a missing file argument', () {
      expect(
        () => validateCall(tool, const {}, fileExists: _always),
        throwsA(
          isA<InvalidCallException>().having(
            (e) => e.message,
            'message',
            contains("needs 'file'"),
          ),
        ),
      );
    });

    test('rejects a path that does not exist', () {
      expect(
        () => validateCall(tool, {'file': '/nope.pdf'}, fileExists: _never),
        throwsA(
          isA<InvalidCallException>().having(
            (e) => e.message,
            'message',
            contains('File not found'),
          ),
        ),
      );
    });

    test('rejects a wrong extension', () {
      expect(
        () => validateCall(tool, {'file': '/a.png'}, fileExists: _always),
        throwsA(
          isA<InvalidCallException>().having(
            (e) => e.message,
            'message',
            contains('accepts pdf'),
          ),
        ),
      );
    });

    test("coerces a stringified integer ('3' -> 3)", () {
      final call = validateCall(tool, {
        'file': '/a.pdf',
        'imageQuality': '3',
      }, fileExists: _always);
      expect(call.input.params['imageQuality'], 3);
    });

    test('rejects a non-string text param', () {
      expect(
        () => validateCall(tool, {
          'file': '/a.pdf',
          'note': 7,
        }, fileExists: _always),
        throwsA(
          isA<InvalidCallException>().having(
            (e) => e.message,
            'message',
            contains('must be a string'),
          ),
        ),
      );
    });

    test('omitted params are absent so tool defaults apply', () {
      final call = validateCall(tool, {'file': '/a.pdf'}, fileExists: _always);
      expect(call.input.params, isEmpty);
      expect(call.input.files.single.name, 'a.pdf');
    });

    test('a multi-file tool rejects an empty files list', () {
      final merge = _StubTool(_meta(id: 'merge', acceptsMultiple: true));
      expect(
        () => validateCall(merge, {'files': <String>[]}, fileExists: _always),
        throwsA(
          isA<InvalidCallException>().having(
            (e) => e.message,
            'message',
            contains("needs 'files'"),
          ),
        ),
      );
    });

    test('rejects an integer outside the declared min/max', () {
      final bounded = _StubTool(
        _meta(
          params: const [
            ToolParam(
              key: 'q',
              label: 'Quality',
              min: 1,
              max: 100,
              helperText: 'lower = smaller',
            ),
          ],
        ),
      );
      expect(
        () => validateCall(bounded, {
          'file': '/a.pdf',
          'q': 0,
        }, fileExists: _always),
        throwsA(
          isA<InvalidCallException>().having(
            (e) => e.message,
            'message',
            contains('1'),
          ),
        ),
      );
      expect(
        () => validateCall(bounded, {
          'file': '/a.pdf',
          'q': 500,
        }, fileExists: _always),
        throwsA(isA<InvalidCallException>()),
      );
      final ok = validateCall(bounded, {
        'file': '/a.pdf',
        'q': 50,
      }, fileExists: _always);
      expect(ok.input.params['q'], 50);
    });

    test('a tool needing a PDF + an image rejects a lone image', () {
      // Logged failure: the agent called pdf_add_images with only a photo,
      // the call validated, the user confirmed, and the run then died on
      // "Select one PDF and one PNG/JPG image."
      final addImages = buildTools()
          .firstWhere((t) => t.meta.qualifiedId == 'pdf/add-images');
      expect(
        () => validateCall(
          addImages,
          {
            'files': ['/cache/IMG-0004.jpg'],
          },
          fileExists: _always,
        ),
        throwsA(
          isA<InvalidCallException>().having(
            (e) => e.message,
            'message',
            contains('one PDF and one PNG/JPG image'),
          ),
        ),
      );
      final ok = validateCall(
        addImages,
        {
          'files': ['/cache/doc.pdf', '/cache/IMG-0004.jpg'],
        },
        fileExists: _always,
      );
      expect(ok.input.files.length, 2);
    });
  });

  group('fnSchemaFor', () {
    test('surfaces param bounds and helper text to the model', () {
      final meta = _meta(
        params: const [
          ToolParam(
            key: 'q',
            label: 'Quality',
            min: 1,
            max: 100,
            helperText: 'lower = smaller file',
          ),
        ],
      );
      final props =
          (fnSchemaFor(meta)['parameters'] as Map)['properties'] as Map;
      final q = props['q'] as Map;
      expect(q['minimum'], 1);
      expect(q['maximum'], 100);
      expect(q['description'], contains('lower = smaller file'));
    });

    test('every registered tool exposes a grammar-safe name (no slash)', () {
      // The on-device tool-call grammar accepts only [A-Za-z0-9_-]; a '/' made
      // every call unparseable. Guard the whole registry against regression.
      final safe = RegExp(r'^[A-Za-z0-9_]+$');
      for (final t in buildTools()) {
        final name = fnSchemaFor(t.meta)['name'] as String;
        expect(
          safe.hasMatch(name),
          isTrue,
          reason: '${t.meta.qualifiedId} -> "$name" is not grammar-safe',
        );
      }
    });

    test('fnNameFor is category-prefixed with hyphens collapsed', () {
      final meta = _meta(id: 'add-images', category: ToolCategory.pdf);
      expect(fnNameFor(meta), 'pdf_add_images');
    });
  });

  group('shortlistTools', () {
    final all = buildTools();

    test("'compress this pdf' surfaces pdf/compress within the limit", () {
      final picked = shortlistTools(all, 'compress this pdf');
      expect(picked.length, lessThanOrEqualTo(10));
      expect(picked.map((t) => t.meta.qualifiedId), contains('pdf/compress'));
    });

    test("'convert to grayscale' surfaces image/grayscale", () {
      final picked = shortlistTools(all, 'convert to grayscale');
      expect(
        picked.map((t) => t.meta.qualifiedId),
        contains('image/grayscale'),
      );
    });

    test('a request matching nothing returns empty', () {
      expect(shortlistTools(all, 'zzzz'), isEmpty);
    });

    test("a filler-only request ('use the tool') surfaces nothing", () {
      expect(shortlistTools(all, 'use the tool'), isEmpty);
    });

    test('the same request yields an identical order', () {
      final a = shortlistTools(all, 'compress this pdf and make it grayscale');
      final b = shortlistTools(all, 'compress this pdf and make it grayscale');
      expect(
        a.map((t) => t.meta.qualifiedId).toList(),
        b.map((t) => t.meta.qualifiedId).toList(),
      );
    });

    test("a synonym ('shrink') surfaces pdf/compress", () {
      final picked = shortlistTools(all, 'shrink this pdf');
      expect(picked.map((t) => t.meta.qualifiedId), contains('pdf/compress'));
    });

    test('an attached file type surfaces tools that accept it', () {
      final picked = shortlistTools(all, 'zzzz', attachmentExts: {'pdf'});
      expect(picked, isNotEmpty);
      expect(
        picked.every((t) => t.meta.acceptedExtensions.contains('pdf')),
        isTrue,
      );
    });

    test("'write ... below' surfaces pdf/add-text", () {
      final picked = shortlistTools(
        all,
        'create pdf and write the details below',
      );
      expect(picked.map((t) => t.meta.qualifiedId), contains('pdf/add-text'));
    });

    test('a matched category fills siblings up to the limit', () {
      final picked = shortlistTools(all, 'compress this pdf');
      final pdfCount = picked
          .where((t) => t.meta.qualifiedId.startsWith('pdf/'))
          .length;
      expect(pdfCount, greaterThan(1));
      expect(picked.length, lessThanOrEqualTo(10));
    });

    test('WYSIWYG-only tools (edit, crop) are never offered to the agent', () {
      // pdf/edit and pdf/crop need editor-supplied JSON (overlay maps, crop
      // margins) the model cannot produce, so they must never be shortlisted.
      final picked = shortlistTools(all, 'edit and crop this pdf',
          attachmentExts: {'pdf'});
      final ids = picked.map((t) => t.meta.qualifiedId).toSet();
      expect(ids, isNot(contains('pdf/edit')));
      expect(ids, isNot(contains('pdf/crop')));
    });

    test('pdf/create IS offered to the agent (blank-PDF primitive)', () {
      final picked = shortlistTools(all, 'create a blank pdf');
      expect(picked.map((t) => t.meta.qualifiedId), contains('pdf/create'));
    });

    test("'create a pdf, place the image in the center' surfaces "
        'pdf/photo-caption', () {
      final picked = shortlistTools(
        all,
        'create a pdf file, place the image in the center of it',
        attachmentExts: {'heic'},
      );
      expect(
        picked.map((t) => t.meta.qualifiedId),
        contains('pdf/photo-caption'),
      );
    });
    test('an attached file demotes zero-input generators (#3)', () {
      final picked = shortlistTools(all, 'add the image on the pdf',
          attachmentExts: {'pdf', 'jpg'});
      final ids = picked.map((t) => t.meta.qualifiedId).toSet();
      expect(ids, contains('pdf/add-images'));
      expect(ids, isNot(contains('image/text-to-image')));
    });

  });

  group('AgentSession', () {
    final compress = _StubTool(_meta());
    final grayscale = _StubTool(
      _meta(
        id: 'grayscale',
        category: ToolCategory.image,
        accepts: const ['png', 'pdf'],
      ),
    );

    AgentSession session(
      List<List<LlmEvent>> turns, {
      int maxRepairs = 2,
      _FakeChat? out,
    }) => AgentSession(
      chat: out ?? _FakeChat(turns),
      tools: [compress, grayscale],
      maxRepairs: maxRepairs,
      fileExists: _always,
    );

    test('thinking + text deltas precede the confirm', () async {
      final chat = _FakeChat([
        const [
          LlmThinkingDelta('let me compress it'),
          LlmTextDelta('Compressing'),
          LlmToolCall(name: 'pdf_compress', args: {'file': '/in.pdf'}),
        ],
      ]);
      final events = await session(const [], out: chat).start('go').toList();

      expect(
        events.whereType<AgentThinking>().single.text,
        'let me compress it',
      );
      expect(events.whereType<AgentText>().single.text, 'Compressing');
      expect(events.last, isA<AgentToolCall>());
    });

    test('a single valid call awaits confirmation', () async {
      final chat = _FakeChat([
        const [
          LlmToolCall(name: 'pdf_compress', args: {'file': '/in.pdf'}),
        ],
      ]);
      final events = await session(
        const [],
        out: chat,
      ).start('compress this pdf').toList();

      expect(chat.sent.single, 'compress this pdf');
      final confirm = events.last as AgentToolCall;
      expect(confirm.step, 1);
      expect(confirm.call.tool.meta.qualifiedId, 'pdf/compress');
      expect(confirm.call.input.files.single.path, '/in.pdf');
    });

    test('a hallucinated function name is fed back, not executed', () async {
      final chat = _FakeChat([
        const [
          LlmToolCall(name: 'shrink_pdf', args: {'file': '/in.pdf'}),
        ],
        const [
          LlmToolCall(name: 'pdf_compress', args: {'file': '/in.pdf'}),
        ],
      ]);
      final events = await session(
        const [],
        out: chat,
      ).start('shrink it').toList();

      expect(chat.toolResults, hasLength(1));
      expect(chat.toolResults.single.$1, 'shrink_pdf');
      expect(
        chat.toolResults.single.$2['error'],
        contains("Unknown function 'shrink_pdf'"),
      );
      expect(events.last, isA<AgentToolCall>());
    });

    test('exhausting the repair budget gives up instead of running', () async {
      final chat = _FakeChat([
        const [
          LlmToolCall(name: 'pdf_compress', args: {'file': '/in.png'}),
        ],
        const [
          LlmToolCall(name: 'nope', args: {'file': '/in.pdf'}),
        ],
      ]);
      final events = await session(
        const [],
        maxRepairs: 1,
        out: chat,
      ).start('go').toList();

      expect(chat.toolResults, hasLength(1));
      expect(
        (events.last as AgentStuck).message,
        contains("Unknown function 'nope'"),
      );
    });

    test('a plain text turn finishes the turn', () async {
      final events = await session([
        const [LlmTurnDone('  Done.  ')],
      ]).start('hi').toList();
      expect((events.last as AgentDone).answer, 'Done.');
    });

    test('a blank turn is retried, then reports stuck if it stays blank',
        () async {
      final chat = _FakeChat([
        const [LlmTurnDone('   ')],
        const [LlmTurnDone('')],
      ]);
      final events =
          await session(const [], maxRepairs: 1, out: chat).start('hi').toList();
      // Original send + one nudge before giving up.
      expect(chat.sent, hasLength(2));
      expect(events.last, isA<AgentStuck>());
      expect((events.last as AgentStuck).message, contains('could not answer'));
    });

    test('a blank turn is retried and a following call is executed', () async {
      final chat = _FakeChat([
        const [LlmTurnDone('')],
        const [LlmToolCall(name: 'pdf_compress', args: {'file': '/in.pdf'})],
      ]);
      final events = await session(const [], out: chat).start('go').toList();
      expect(chat.sent, hasLength(2));
      expect(events.last, isA<AgentToolCall>());
    });

    // Gemma 4 E2B emits the OpenAI `tool_calls` shape, which flutter_gemma's
    // gemmaIt JSON format misparses into the text channel (log: pdf_create /
    // image_text_image_generator surfaced as "Answered"). The loop recovers it.
    test('an OpenAI tool_calls wrapper leaked as text is recovered', () async {
      const leaked =
          '{"role":"assistant","tool_calls":[{"type":"function","function":'
          '{"name":"pdf_compress","arguments":{"file":"/in.pdf"}}}]}';
      final events = await session([
        const [LlmTurnDone(leaked)],
      ]).start('compress this pdf').toList();
      final confirm = events.last as AgentToolCall;
      expect(confirm.call.tool.meta.qualifiedId, 'pdf/compress');
      expect(confirm.call.input.files.single.path, '/in.pdf');
    });

    test('a leaked call with stringified arguments is recovered', () async {
      const leaked =
          '{"tool_calls":[{"function":{"name":"pdf_compress",'
          '"arguments":"{\\"file\\":\\"/in.pdf\\"}"}}]}';
      final events = await session([
        const [LlmTurnDone(leaked)],
      ]).start('compress this pdf').toList();
      final confirm = events.last as AgentToolCall;
      expect(confirm.call.input.files.single.path, '/in.pdf');
    });

    test('a fenced flat-json call is recovered', () async {
      const leaked =
          '```json\n{"name": "image_grayscale", '
          '"parameters": {"file": "/in.png"}}\n```';
      final events = await session([
        const [LlmTurnDone(leaked)],
      ]).start('grayscale this').toList();
      expect(
        (events.last as AgentToolCall).call.tool.meta.qualifiedId,
        'image/grayscale',
      );
    });

    test('a plain answer containing json is not mistaken for a call', () async {
      const answer = 'Here is the data: {"status": "ok"}';
      final events = await session([
        const [LlmTurnDone(answer)],
      ]).start('hi').toList();
      expect((events.last as AgentDone).answer, answer);
    });

    test('close forwards to the chat', () async {
      final chat = _FakeChat(const []);
      await session(const [], out: chat).close();
      expect(chat.closed, isTrue);
    });
    test('an omitted file arg is filled from availableFiles (#2)', () async {
      final chat = _FakeChat([
        const [LlmToolCall(name: 'pdf_compress', args: {})],
      ]);
      final s = AgentSession(
        chat: chat,
        tools: [compress, grayscale],
        availableFiles: const [InputFile(path: '/in.pdf', name: 'in.pdf')],
        fileExists: _always,
      );
      final events = await s.start('compress it').toList();
      expect((events.last as AgentToolCall).call.input.files.single.path,
          '/in.pdf');
      // Filled deterministically — no repair round-trip.
      expect(chat.toolResults, isEmpty);
    });

    test('continueAfterToolError feeds the error back and drives a new call '
        '(#4)', () async {
      final chat = _FakeChat([
        const [LlmToolCall(name: 'pdf_compress', args: {'file': '/in.pdf'})],
        const [LlmToolCall(name: 'image_grayscale', args: {'file': '/in.pdf'})],
      ]);
      final s = session(const [], out: chat);
      final first = await s.start('go').toList();
      expect((first.last as AgentToolCall).call.tool.meta.qualifiedId,
          'pdf/compress');
      final recovered = await s
          .continueAfterToolError(toolName: 'pdf_compress', error: 'boom')
          .toList();
      expect((recovered.last as AgentToolCall).call.tool.meta.qualifiedId,
          'image/grayscale');
      expect(chat.toolResults, hasLength(1));
      expect(chat.toolResults.single.$1, 'pdf_compress');
      expect(chat.toolResults.single.$2['error'], contains('boom'));
    });

    test('continueAfterToolError with no repairs left gives up (#4)', () async {
      final chat = _FakeChat(const []);
      final s = session(const [], maxRepairs: 0, out: chat);
      final events = await s
          .continueAfterToolError(toolName: 'pdf_compress', error: 'boom')
          .toList();
      expect(events.single, isA<AgentStuck>());
      expect(chat.toolResults, isEmpty);
    });

  });

  group('chain_prompt', () {
    const step = ChainStep(
      toolLabel: 'Add Image',
      outputName: 'a.pdf',
      outputPath: '/x/a.pdf',
    );

    test('continuationPrompt logs the request and completed steps', () {
      final p = continuationPrompt('req', const [step]);
      expect(p, contains('req'));
      expect(p, contains('Add Image'));
      expect(p, contains('/x/a.pdf'));
    });

    test('chainShortlistQuery appends completed step labels', () {
      final q = chainShortlistQuery('req', const [step]);
      expect(q, contains('Add Image'));
    });

    test('continuationPrompt carries a step result text for the next step', () {
      final p = continuationPrompt('req', const [
        ChainStep(
          toolLabel: 'Identify Photo',
          outputName: 'labels.txt',
          resultText: 'taco, food, dish',
        ),
      ]);
      expect(p, contains('taco, food, dish'));
    });

    test('chainShortlistQuery with no steps is just the request', () {
      expect(chainShortlistQuery('req', const []), 'req');
    });
    test('estimateTokens is ~4 chars per token', () {
      expect(estimateTokens('x' * 400), 100);
    });

    test('fitTextBlocks truncates the first overflowing block', () {
      final out = fitTextBlocks(['a' * 4000], 100);
      expect(out, hasLength(1));
      expect(out.single, endsWith('…[truncated]'));
      expect(out.single.length, lessThan(4000));
    });

    test('fitTextBlocks with a zero budget keeps nothing', () {
      expect(fitTextBlocks(['a' * 40], 0), isEmpty);
    });

  });
}
