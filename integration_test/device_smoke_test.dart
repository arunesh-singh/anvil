/// On-device Phase-1 smoke: exercises the REAL native engines (pdf_manipulator
/// Rust, ImageChannel Kotlin, FFmpegKit, flutter_avif FFI) through the same
/// registry → tool → engine → result path the app uses.
///
/// Run: flutter test integration_test -d `device`
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anvil/agent/agent_session.dart';
import 'package:anvil/agent/chain_prompt.dart';
import 'package:anvil/agent/tool_shortlist.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/chat_repository.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/llm_chat.dart';
import 'package:anvil/engines/llm_engine.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/models/manifest.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

// 1×1 transparent PNG.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
  ),
);

/// Release QA runs with `--dart-define=ANVIL_REQUIRE_MODELS=true`, which
/// turns "model unavailable" from a skip into a failure. Unset (developer
/// laptops, no network) the model-backed smokes still skip.
const bool kRequireModels = bool.fromEnvironment('ANVIL_REQUIRE_MODELS');

void _skipOrFail(Object error, String what) {
  if (kRequireModels) {
    fail('$what must pass under ANVIL_REQUIRE_MODELS: $error');
  }
  markTestSkipped('$what skipped (model unavailable/offline): $error');
}

Future<ToolResult> _run(
  ToolRegistry registry,
  String qualifiedId,
  List<File> files,
  Map<String, dynamic> params,
) async {
  final tool = registry.byId(qualifiedId);
  expect(tool, isNotNull, reason: '$qualifiedId must be registered');
  final events = await tool!
      .run(
        ToolInput(
          files: [
            for (final f in files)
              InputFile(path: f.path, name: f.uri.pathSegments.last),
          ],
          params: params,
        ),
      )
      .toList();
  final last = events.last;
  expect(last, isA<ToolSucceeded>(), reason: '$qualifiedId must succeed');
  final result = (last as ToolSucceeded).result;
  for (final out in result.files) {
    expect(
      await File(out.path).length(),
      greaterThan(0),
      reason: '$qualifiedId output ${out.name} must be non-empty',
    );
  }
  return result;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ToolRegistry registry;
  late FileService fs;

  setUpAll(() async {
    await configureDependencies();
    registry = getIt<ToolRegistry>();
    fs = getIt<FileService>();
  });

  testWidgets('PDF block: merge + split + watermark run natively end-to-end', (
    tester,
  ) async {
    final pdfBytes = await getIt<PdfEngine>().imagesToPdf([_png, _png]);
    final a = await fs.writeBytes('a.pdf', pdfBytes);
    final b = await fs.writeBytes('b.pdf', pdfBytes);

    final merged = await _run(registry, 'pdf/merge', [a, b], const {});
    expect(merged.files, hasLength(1));
    final mergedBytes = await File(merged.files.single.path).readAsBytes();
    expect(await getIt<PdfEngine>().pageCount(mergedBytes), 4);

    await _run(registry, 'pdf/split', [a], const {'every': 1});
    await _run(registry, 'pdf/watermark', [a], const {'text': 'SMOKE'});
  });

  testWidgets(
    'image block: grayscale + resize run through the Kotlin channel',
    (tester) async {
      // A visible 8x8 red PNG so bitmap ops have real pixels.
      final im = img.Image(width: 8, height: 8);
      img.fill(im, color: img.ColorRgb8(255, 0, 0));
      final src = await fs.writeBytes('red.png', img.encodePng(im));

      final gray = await _run(registry, 'image/grayscale', [src], const {});
      final decoded = img.decodePng(
        await File(gray.files.single.path).readAsBytes(),
      )!;
      final p = decoded.getPixel(0, 0);
      expect(p.r, p.g, reason: 'grayscale pixel must have R == G');
      expect(p.g, p.b, reason: 'grayscale pixel must have G == B');

      final resized = await _run(
        registry,
        'image/resize',
        [src],
        const {'width': 4, 'height': 0},
      );
      final rDecoded = img.decodePng(
        await File(resized.files.single.path).readAsBytes(),
      );
      // resize keeps aspect: 8x8 -> 4x4 (png out for png in).
      expect((rDecoded!.width, rDecoded.height), (4, 4));
    },
  );

  testWidgets('image convert block: png-to-avif runs the rav1e FFI encoder', (
    tester,
  ) async {
    final im = img.Image(width: 16, height: 16);
    img.fill(im, color: img.ColorRgb8(0, 128, 255));
    final src = await fs.writeBytes('blue.png', img.encodePng(im));
    final avif = await _run(registry, 'image/png-to-avif', [src], const {});
    expect(avif.files.single.name, endsWith('.avif'));
  });

  testWidgets('video block: gif-to-mov runs FFmpegKit natively', (
    tester,
  ) async {
    // Two-frame 16x16 GIF built on-device.
    final base = img.Image(width: 16, height: 16);
    img.fill(base, color: img.ColorRgb8(255, 0, 0));
    final f2 = img.Image(width: 16, height: 16);
    img.fill(f2, color: img.ColorRgb8(0, 255, 0));
    base.addFrame(f2);
    final gif = await fs.writeBytes('anim.gif', img.encodeGif(base));

    final mov = await _run(registry, 'video/gif-to-mov', [gif], const {});
    expect(mov.files.single.name, endsWith('.mov'));
  });

  testWidgets('ML block: remove-bg runs ML Kit subject segmentation natively', (
    tester,
  ) async {
    // A subject (skin-tone disc) on a dark background gives segmentation
    // something to isolate.
    final im = img.Image(width: 64, height: 64);
    img.fill(im, color: img.ColorRgb8(18, 18, 18));
    img.fillCircle(
      im,
      x: 32,
      y: 32,
      radius: 20,
      color: img.ColorRgb8(240, 200, 160),
    );
    final src = await fs.writeBytes('subject.png', img.encodePng(im));

    final out = await _run(registry, 'image/remove-bg', [src], const {});
    expect(out.files, hasLength(1));
    expect(out.files.single.name, endsWith('.png'));
  });

  testWidgets('ML block: to-text OCR reads rendered text natively', (
    tester,
  ) async {
    final canvas = img.Image(width: 220, height: 80);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.drawString(
      canvas,
      'ANVIL',
      font: img.arial24,
      x: 20,
      y: 24,
      color: img.ColorRgb8(0, 0, 0),
    );
    final src = await fs.writeBytes('ocr.png', img.encodePng(canvas));

    // OCR is approximate; assert non-empty recognized text, not an exact match.
    final ocr = await _run(registry, 'image/to-text', [src], const {});
    expect(ocr.text, isNotNull);
    expect(ocr.text!.trim(), isNotEmpty);
  });

  testWidgets('ML block: upscale runs the real ONNX super-resolution model', (
    tester,
  ) async {
    // First run downloads the ~32 MB swin2sr model, so the device needs
    // network; skips only when ANVIL_REQUIRE_MODELS is unset.
    final im = img.Image(width: 16, height: 16);
    img.fill(im, color: img.ColorRgb8(60, 160, 220));
    final src = await fs.writeBytes('small.png', img.encodePng(im));
    try {
      final up = await _run(registry, 'image/upscale', [src], const {});
      final decoded = img.decodePng(
        await File(up.files.single.path).readAsBytes(),
      )!;
      expect(decoded.width, greaterThan(16));
      expect(decoded.height, greaterThan(16));
    } on Exception catch (e) {
      _skipOrFail(e, 'upscale smoke');
    }
  }, timeout: const Timeout(Duration(minutes: 15)));

  testWidgets('LLM block: grammar-fixer generates through Gemma on-device', (
    tester,
  ) async {
    // First run downloads the ~2.6 GB Gemma 4 E2B bundle, so the device needs
    // network and >= 6 GB RAM; skips only when ANVIL_REQUIRE_MODELS is unset.
    try {
      final out = await _run(registry, 'write/grammar-fixer', const [], const {
        'text': 'she dont likes apple.',
      });
      expect(out.files.single.name, endsWith('.txt'));
      expect(out.text, isNotNull);
      expect(out.text!.trim(), isNotEmpty);
    } on Exception catch (e) {
      _skipOrFail(e, 'grammar-fixer smoke');
    }
  }, timeout: const Timeout(Duration(minutes: 45)));

  testWidgets('agent block: a two-step chain yields a tool call per step', (
    tester,
  ) async {
    // The PLAN/D6 acceptance gate: "compress this PDF and convert to
    // grayscale" must resolve to pdf/compress, wait for a confirm, execute,
    // then propose a second image-category step. Needs the real model.
    const request = 'compress this pdf and convert it to grayscale';
    try {
      final loaded = await getIt<ModelManager>().ensureReady(
        const ModelSpec(taskId: 'agent.llm'),
      );
      final engine = getIt<LlmEngine>();
      await engine.ensureLoaded(loaded.filePath, supportImage: false);

      final pdfBytes = await getIt<PdfEngine>().imagesToPdf([_png, _png]);
      final src = await fs.writeBytes('agent.pdf', pdfBytes);

      const sys =
          'You are Anvil\'s assistant. You run fully offline on this '
          'phone.\nPick ONE function per turn from the provided list.\nFile '
          'arguments must be absolute paths copied from "Available files".';
      Future<LlmChat> makeChat(List<ToolModule> tools) => engine.startChat(
        fnSchemas: [for (final t in tools) t.fnSchema],
        systemInstruction: '$sys\nAvailable files:\n- ${src.path}',
        temperature: 0.1,
        topK: 1,
        topP: 1.0,
        maxOutputTokens: 1024,
      );

      // Step 1: fresh chat, step 1, resolves to pdf/compress and confirms.
      final step1Tools = shortlistTools(registry.all, request);
      expect(
        step1Tools.map((t) => t.meta.qualifiedId),
        contains('pdf/compress'),
      );
      final s1 = AgentSession(
        chat: await makeChat(step1Tools),
        tools: step1Tools,
        step: 1,
      );
      final first = (await s1.start(request).toList()).last;
      expect(first, isA<AgentToolCall>());
      final step1 = (first as AgentToolCall).call;
      expect(step1.tool.meta.qualifiedId, 'pdf/compress');

      final events = await step1.tool.run(step1.input).toList();
      expect(events.last, isA<ToolSucceeded>());
      final result = (events.last as ToolSucceeded).result;
      await s1.close();

      // Step 2: re-shortlist against the completed step, fresh chat + a
      // continuation prompt carrying step 1's output path, step 2.
      final done = ChainStep(
        toolLabel: step1.tool.meta.label,
        outputName: result.files.firstOrNull?.name,
        outputPath: result.files.firstOrNull?.path,
      );
      final step2Tools = shortlistTools(
        registry.all,
        chainShortlistQuery(request, [done]),
      );
      final s2 = AgentSession(
        chat: await makeChat(step2Tools),
        tools: step2Tools,
        step: 2,
      );
      final second =
          (await s2.start(continuationPrompt(request, [done])).toList()).last;
      expect(second, isA<AgentToolCall>());
      expect(
        (second as AgentToolCall).call.tool.meta.category,
        ToolCategory.image,
      );
      expect(second.step, 2);
      await s2.close();
    } on Exception catch (e) {
      _skipOrFail(e, 'agent chain smoke');
    }
  }, timeout: const Timeout(Duration(minutes: 45)));

  testWidgets('needle block: Needle 3 routes a request through the FFI', (
    tester,
  ) async {
    // The ONLY coverage for lib/engines/needle_ffi.dart: the vendored engine
    // is linked into libneedle_ffi.so, so the dlopen, the C signatures and
    // the worker protocol cannot be exercised off-device at all.
    try {
      final loaded = await getIt<ModelManager>().ensureReady(
        const ModelSpec(taskId: 'agent.llm.needle'),
      );
      final engine = getIt<LlmEngine>();
      await engine.ensureLoaded(
        loaded.filePath,
        family: ModelFamily.needle3,
        maxTokens: 2048,
        taskId: 'agent.llm.needle',
      );
      expect(engine.status.phase, LlmPhase.loaded);
      expect(engine.loadedTaskId, 'agent.llm.needle');

      final pdfBytes = await getIt<PdfEngine>().imagesToPdf([_png, _png]);
      final src = await fs.writeBytes('needle.pdf', pdfBytes);
      final tools = shortlistTools(
        registry.all,
        'make this pdf smaller',
        limit: 5,
      );
      expect(tools.map((t) => t.meta.qualifiedId), contains('pdf/compress'));

      final session = AgentSession(
        chat: await engine.startChat(
          fnSchemas: [for (final t in tools) t.fnSchema],
          // Needle takes environment facts, not prose rules.
          systemInstruction: 'date: 2026-01-01 Thu 09:00; device: phone',
          temperature: 0.1,
          topK: 1,
          topP: 1.0,
          maxOutputTokens: 512,
          family: ModelFamily.needle3,
        ),
        tools: tools,
        availableFiles: [InputFile(path: src.path, name: 'needle.pdf')],
      );
      final last = (await session
              .start('make this pdf smaller (${src.path})')
              .toList())
          .last;
      expect(last, isA<AgentToolCall>());
      final call = (last as AgentToolCall).call;
      expect(call.tool.meta.qualifiedId, 'pdf/compress');
      // Needle grounds the path out of the request and clips it; the call
      // still has to arrive carrying the real attachment.
      expect(call.input.files.single.path, src.path);
      await session.close();

      // Needle has no text path — the write tools must be refused loudly
      // rather than handed a JSON envelope as prose.
      await expectLater(
        engine.generate('Fix the grammar: he go to school.'),
        throwsA(isA<ToolException>()),
      );
      await engine.unload();
    } on Exception catch (e) {
      _skipOrFail(e, 'needle 3 smoke');
    }
  }, timeout: const Timeout(Duration(minutes: 15)));

  testWidgets('chat block: a session and its messages persist (v3 migration)', (
    tester,
  ) async {
    // Proves the v3 migration + ChatRepository on the real app DB: create a
    // session, add a turn, read it back ordered, then delete it (cascading
    // its messages). No model needed.
    final repo = getIt<ChatRepository>();
    final before = (await repo.sessions()).length;
    final id = await repo.createSession(ChatSession.fresh(DateTime.now()));
    await repo.addMessage(
      ChatMessage(
        sessionId: id,
        role: ChatRole.user,
        kind: ChatMessageKind.text,
        text: 'hello from the smoke test',
        createdAt: DateTime.now(),
      ),
    );
    final msgs = await repo.messages(id);
    expect(msgs.single.text, 'hello from the smoke test');

    await repo.deleteSession(id);
    expect(await repo.messages(id), isEmpty);
    expect((await repo.sessions()).length, before);
  });
}
