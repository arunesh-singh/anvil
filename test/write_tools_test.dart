import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/llm_chat.dart';
import 'package:anvil/engines/llm_engine.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/models/manifest.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/tools/write/write_tools.dart';

// Engine fakes use `implements` (never `extends`): the real LlmEngine talks to
// flutter_gemma (native LiteRT-LM), and the real PdfEngine to the Rust plugin,
// so the tool bodies must resolve fakes through getIt instead.

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

class _FakeLlmEngine implements LlmEngine {
  String? prompt;
  String? loadedPath;
  String completion = 'She does not like apples.';

  @override
  int get contextTokens => 4096;

  @override
  Future<void> ensureLoaded(String modelPath,
      {bool supportImage = false,
      ModelFamily family = ModelFamily.gemma4,
      int maxTokens = 4096}) async {
    loadedPath = modelPath;
  }

  @override
  Future<String> generate(String p) async {
    prompt = p;
    return completion;
  }

  @override
  Future<LlmChat> startChat({
    required List<Map<String, dynamic>> fnSchemas,
    required String systemInstruction,
    required double temperature,
    required int topK,
    required double topP,
    required int maxOutputTokens,
    bool supportImage = false,
    ModelFamily family = ModelFamily.gemma4,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> dispose() async {}
}

class _FakeModelManager implements ModelManager {
  @override
  Future<LoadedModel> ensureReady(ModelSpec spec,
          {void Function(int received, int total)? onProgress}) async =>
      LoadedModel(
        taskId: spec.taskId,
        variant: _variant,
        filePath: '/tmp/${spec.taskId}.litertlm',
      );

  @override
  Future<ModelStatus> status(String taskId) async => ModelStatus.cached;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFileService implements FileService {
  _FakeFileService(this.dir);
  final Directory dir;
  String contents = '';

  @override
  Future<Directory> outputsDir() async => dir;

  @override
  Future<String> readString(String path) async => contents;

  @override
  Future<List<int>> readBytes(String path) async => const [1, 2, 3];

  @override
  Future<File> writeString(String fileName, String content) async {
    final f = File(p.join(dir.path, fileName));
    await f.writeAsString(content);
    return f;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePdfEngine implements PdfEngine {
  bool extractCalled = false;

  @override
  Future<String> extractText(Uint8List input) async {
    extractCalled = true;
    return 'Quarterly revenue rose 12 percent.';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ToolModule _tool(String qualifiedId) =>
    ToolRegistry(buildWriteTools()).byId(qualifiedId)!;

Future<ToolResult> _run(ToolModule tool, ToolInput input) async {
  final events = await tool.run(input).toList();
  expect(events.last, isA<ToolSucceeded>());
  return (events.last as ToolSucceeded).result;
}

void main() {
  late Directory tempDir;
  late _FakeLlmEngine llm;
  late _FakePdfEngine pdf;
  late _FakeFileService fileService;

  setUp(() async {
    await getIt.reset();
    tempDir = await Directory.systemTemp.createTemp('anvil_write_tools');
    llm = _FakeLlmEngine();
    pdf = _FakePdfEngine();
    fileService = _FakeFileService(tempDir);
    getIt
      ..registerSingleton<FileService>(fileService)
      ..registerSingleton<LlmEngine>(llm)
      ..registerSingleton<PdfEngine>(pdf)
      ..registerSingleton<ModelManager>(_FakeModelManager());
  });

  tearDown(() async {
    await getIt.reset();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('write/grammar-fixer prompts the model and saves a .txt output',
      () async {
    final tool = _tool('write/grammar-fixer');
    expect(tool.engine, EngineKind.llm);
    final result = await _run(
      tool,
      const ToolInput(files: [], params: {'text': 'she dont likes apple.'}),
    );
    expect(result.text, 'She does not like apples.');
    expect(result.files.single.name, endsWith('.txt'));
    expect(result.files.single.mimeType, 'text/plain');
    expect(await File(result.files.single.path).readAsString(),
        'She does not like apples.');
    // The prompt carries both the instruction and the user's text.
    expect(llm.prompt, contains('Fix all grammar'));
    expect(llm.prompt, contains('she dont likes apple.'));
    // The model file resolved through Phase-2 delivery before generating.
    expect(llm.loadedPath, '/tmp/agent.llm.litertlm');
  });

  test('write/tone-of-voice threads its tone param into the prompt', () async {
    await _run(
      _tool('write/tone-of-voice'),
      const ToolInput(files: [], params: {'text': 'hi', 'tone': 'playful'}),
    );
    expect(llm.prompt, contains('playful'));
  });

  test('write/word-counter counts on-device with no model and no output file',
      () async {
    final tool = _tool('write/word-counter');
    expect(tool.engine, EngineKind.dartlib);
    expect(tool.model, isNull);
    final result = await _run(
      tool,
      const ToolInput(files: [], params: {'text': 'one two three.'}),
    );
    expect(result.files, isEmpty);
    expect(result.text, contains('Words: 3'));
    // Never touched the language model.
    expect(llm.prompt, isNull);
  });

  test('pdf/summarizer extracts the PDF text and prompts with it', () async {
    final result = await _run(
      _tool('pdf/summarizer'),
      const ToolInput(
        files: [InputFile(path: '/tmp/report.pdf', name: 'report.pdf')],
      ),
    );
    expect(pdf.extractCalled, isTrue);
    expect(llm.prompt, contains('Quarterly revenue rose 12 percent.'));
    expect(result.files.single.name, 'report.txt');
  });

  test('an empty input is rejected before the model is touched', () async {
    final tool = _tool('write/grammar-fixer');
    await expectLater(
      tool.run(const ToolInput(files: [], params: {})).toList(),
      throwsA(isA<ToolException>().having((e) => e.message, 'message',
          'Enter some text (or pick a text file).')),
    );
    expect(llm.prompt, isNull);
  });
}
