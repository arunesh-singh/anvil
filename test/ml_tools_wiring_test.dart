import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/asr_engine.dart';
import 'package:anvil/engines/ffmpeg_engine.dart';
import 'package:anvil/engines/mlkit_engine.dart';
import 'package:anvil/engines/onnx_engine.dart';
import 'package:anvil/models/manifest.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/tools/image/image_ml_helpers.dart' as ml;
import 'package:anvil/tools/image/image_ml_tools.dart';
import 'package:anvil/tools/video/video_ml_tools.dart';

// Engine fakes use `implements` (never `extends`): the real OnnxEngine /
// AsrEngine constructors touch native runtimes (OrtEnv.init / sherpa bindings),
// so the tool bodies must resolve fakes through getIt instead.

final _variant = ModelVariant(
  id: 'test-fast',
  tier: ModelTier.fast,
  url: 'https://example.test/model.onnx',
  sha256: 'a' * 64,
  sizeBytes: 1024,
  runtime: ModelRuntime.onnx,
  minRamGb: 2,
  accelerator: 'cpu',
  version: '1',
);

class _FakeFileService implements FileService {
  _FakeFileService(this.dir);
  final Directory dir;
  Uint8List bytes = Uint8List(0);

  /// Per-path contents (e.g. an editor-supplied mask); others read [bytes].
  final Map<String, Uint8List> files = {};

  @override
  Future<Directory> outputsDir() async => dir;

  @override
  Future<List<int>> readBytes(String path) async => files[path] ?? bytes;

  @override
  Future<File> writeBytes(String fileName, List<int> b) async {
    final f = File(p.join(dir.path, fileName));
    await f.writeAsBytes(b);
    return f;
  }

  @override
  Future<File> writeString(String fileName, String content) async {
    final f = File(p.join(dir.path, fileName));
    await f.writeAsString(content);
    return f;
  }

  @override
  Future<File> reserveFile(String fileName) async =>
      File(p.join(dir.path, fileName));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMlKit implements MlKitEngine {
  int subjectMaskCalls = 0;
  String? detected = 'es';
  String translation = 'HOLA';
  final List<String> identified = [];
  final List<(String, String)> translations = [];

  @override
  Future<OcrResult> recognizeText(String path) async => const OcrResult(
    text: 'HELLO',
    blocks: [OcrBlock(text: 'HELLO', left: 1, top: 1, width: 10, height: 8)],
  );

  @override
  Future<SubjectMask> subjectMask(String path, int width, int height) async {
    subjectMaskCalls++;
    return SubjectMask(
      width: width,
      height: height,
      confidence: List<double>.filled(width * height, 1.0),
    );
  }

  @override
  Future<String> translate(
    String text, {
    required String from,
    required String to,
  }) async {
    translations.add((from, to));
    return translation;
  }

  @override
  Future<String?> identifyLanguage(String text) async {
    identified.add(text);
    return detected;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<ImageTag>> labelImage(
    String path, {
    double minConfidence = 0.6,
  }) async => const [
    ImageTag(label: 'Taco', confidence: 0.9),
    ImageTag(label: 'Food', confidence: 0.8),
  ];
}

class _FakeOnnx implements OnnxEngine {
  _FakeOnnx(this.output);
  final ImageTensor output;
  bool enhanceCalled = false;
  bool inpaintCalled = false;

  @override
  Future<ImageTensor> enhance(String modelPath, ImageTensor input) async {
    enhanceCalled = true;
    return output;
  }

  @override
  Future<ImageTensor> inpaint(
    String modelPath,
    ImageTensor image,
    ImageTensor mask,
  ) async {
    inpaintCalled = true;
    return image;
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAsr implements AsrEngine {
  @override
  Future<List<AsrSegment>> transcribeWav(
    String wavPath, {
    required String encoderPath,
    int windowSeconds = 15,
    void Function(double fraction)? onProgress,
  }) async => const [
    AsrSegment(startMs: 0, endMs: 1500, text: 'hello world'),
    AsrSegment(startMs: 1500, endMs: 3000, text: 'second cue'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFfmpeg implements FfmpegEngine {
  @override
  Future<void> run(
    List<String> args, {
    void Function(int outputTimeMs)? onProgress,
    FfmpegHandle? handle,
  }) async {}

  @override
  Future<void> cancelAll() async {}

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
    filePath: '/tmp/${spec.taskId}.onnx',
  );

  @override
  Future<ModelStatus> status(String taskId) async => ModelStatus.cached;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A tiny opaque PNG so `img.decodeImage` succeeds in the tool bodies.
Uint8List _tinyPng() {
  final image = img.Image(width: 4, height: 4);
  img.fill(image, color: img.ColorRgb8(120, 130, 140));
  return Uint8List.fromList(img.encodePng(image));
}

ToolModule _imageTool(String id) => ToolRegistry(buildImageMlTools()).byId(id)!;
ToolModule _videoTool(String id) => ToolRegistry(buildVideoMlTools()).byId(id)!;

Future<ToolResult> _run(ToolModule tool, ToolInput input) async {
  final events = await tool.run(input).toList();
  expect(events.last, isA<ToolSucceeded>());
  return (events.last as ToolSucceeded).result;
}

void main() {
  late Directory tempDir;
  late _FakeFileService fileService;
  late _FakeOnnx onnx;
  late _FakeMlKit mlkit;

  setUp(() async {
    await getIt.reset();
    tempDir = await Directory.systemTemp.createTemp('anvil_ml_wiring');
    fileService = _FakeFileService(tempDir)..bytes = _tinyPng();
    // A 3-channel 8x8 tensor stands in for the model's (upscaled) output.
    onnx = _FakeOnnx(
      ImageTensor(
        Float32List(3 * 8 * 8)..fillRange(0, 3 * 8 * 8, 0.5),
        3,
        8,
        8,
      ),
    );
    getIt
      ..registerSingleton<FileService>(fileService)
      ..registerSingleton<MlKitEngine>(mlkit = _FakeMlKit())
      ..registerSingleton<OnnxEngine>(onnx)
      ..registerSingleton<AsrEngine>(_FakeAsr())
      ..registerSingleton<FfmpegEngine>(_FakeFfmpeg())
      ..registerSingleton<ModelManager>(_FakeModelManager());
  });

  tearDown(() async {
    await getIt.reset();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('image/to-text OCR yields the recognized text as text/plain', () async {
    final tool = _imageTool('image/to-text');
    final result = await _run(
      tool,
      const ToolInput(
        files: [InputFile(path: '/tmp/in.png', name: 'in.png')],
      ),
    );
    expect(result.text, 'HELLO');
    expect(result.files.single.mimeType, 'text/plain');
  });

  test('image/identify names the photo contents as text/plain', () async {
    final tool = _imageTool('image/identify');
    final result = await _run(
      tool,
      const ToolInput(
        files: [InputFile(path: '/tmp/in.png', name: 'in.png')],
      ),
    );
    expect(result.text, 'Taco, Food');
    expect(result.files.single.mimeType, 'text/plain');
  });

  test('image/remove-bg segments and writes one PNG output', () async {
    final tool = _imageTool('remove-bg');
    final result = await _run(
      tool,
      const ToolInput(
        files: [InputFile(path: '/tmp/in.png', name: 'in.png')],
      ),
    );
    expect(result.files, hasLength(1));
    expect(result.files.single.mimeType, 'image/png');
    expect(result.files.single.name, endsWith('.png'));
    expect(await File(result.files.single.path).exists(), isTrue);
  });

  test('image/upscale routes through OnnxEngine.enhance', () async {
    final tool = _imageTool('upscale');
    expect(tool.model, isNotNull);
    final result = await _run(
      tool,
      const ToolInput(
        files: [InputFile(path: '/tmp/in.png', name: 'in.png')],
      ),
    );
    expect(onnx.enhanceCalled, isTrue);
    expect(result.files.single.mimeType, 'image/png');
    // The fake model output is 8x8, so tensorToImage encodes an 8x8 PNG.
    final decoded = img.decodePng(
      await File(result.files.single.path).readAsBytes(),
    )!;
    expect(decoded.width, 8);
    expect(decoded.height, 8);
  });

  test('video/add-subtitles transcribes to an .srt with timestamps', () async {
    final tool = _videoTool('add-subtitles');
    final result = await _run(
      tool,
      const ToolInput(
        files: [InputFile(path: '/tmp/clip.mp4', name: 'clip.mp4')],
      ),
    );
    expect(result.files.single.name, endsWith('.srt'));
    expect(result.files.single.mimeType, 'application/x-subrip');
    final body = await File(result.files.single.path).readAsString();
    expect(body, contains('-->'));
    expect(body, contains('hello world'));
  });

  group('segmentation with an editor-supplied mask', () {
    const input = InputFile(path: '/tmp/in.png', name: 'in.png');

    /// 4×4 mask: left half subject (255), right half background (0).
    Uint8List leftHalfMaskPng({int width = 4, int height = 4}) {
      final mask = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width ~/ 2; x++) {
          mask[y * width + x] = 255;
        }
      }
      return ml.encodeMaskPng(mask, width, height);
    }

    test('uses the mask at maskPath and skips segmentation', () async {
      fileService.files['/tmp/mask.png'] = leftHalfMaskPng();
      final result = await _run(
        _imageTool('image/remove-bg'),
        const ToolInput(
          files: [input],
          params: {maskPathParam: '/tmp/mask.png'},
        ),
      );
      expect(mlkit.subjectMaskCalls, 0);
      final out = img.decodePng(
        await File(result.files.single.path).readAsBytes(),
      )!;
      // The fake segmenter would keep everything; the supplied mask keeps
      // only the left half.
      expect(out.getPixel(0, 0).a, 255);
      expect(out.getPixel(3, 3).a, 0);
    });

    test('without maskPath the tool segments as before', () async {
      final result = await _run(
        _imageTool('image/remove-bg'),
        const ToolInput(files: [input]),
      );
      expect(mlkit.subjectMaskCalls, 1);
      final out = img.decodePng(
        await File(result.files.single.path).readAsBytes(),
      )!;
      expect(out.getPixel(3, 3).a, 255);
    });

    test('a mask of a different size is rejected', () async {
      fileService.files['/tmp/mask.png'] = leftHalfMaskPng(width: 8);
      await expectLater(
        _imageTool('image/change-bg-photo')
            .run(
              const ToolInput(
                files: [input],
                params: {maskPathParam: '/tmp/mask.png'},
              ),
            )
            .toList(),
        throwsA(
          isA<ToolException>().having(
            (e) => e.message,
            'message',
            contains('8×4'),
          ),
        ),
      );
    });
  });

  group('image/translate', () {
    const input = InputFile(path: '/tmp/menu.png', name: 'menu.png');

    test('from=auto translates from the detected language', () async {
      final result = await _run(
        _imageTool('image/translate'),
        const ToolInput(files: [input], params: {'from': 'auto', 'to': 'en'}),
      );
      expect(mlkit.identified, ['HELLO']);
      expect(mlkit.translations, [('es', 'en')]);
      expect(result.text, 'HOLA');
    });

    test('an omitted from auto-detects too (agent default)', () async {
      await _run(
        _imageTool('image/translate'),
        const ToolInput(files: [input]),
      );
      expect(mlkit.translations, [('es', 'en')]);
    });

    test('an explicit from skips detection', () async {
      await _run(
        _imageTool('image/translate'),
        const ToolInput(files: [input], params: {'from': 'FR', 'to': 'de'}),
      );
      expect(mlkit.identified, isEmpty);
      expect(mlkit.translations, [('fr', 'de')]);
    });

    test('undetectable language is a ToolException', () async {
      mlkit.detected = null;
      await expectLater(
        _imageTool(
          'image/translate',
        ).run(const ToolInput(files: [input])).toList(),
        throwsA(isA<ToolException>()),
      );
      expect(mlkit.translations, isEmpty);
    });

    test(
      'a detected language translation lacks is named in the error',
      () async {
        mlkit.detected = 'am';
        await expectLater(
          _imageTool(
            'image/translate',
          ).run(const ToolInput(files: [input])).toList(),
          throwsA(
            isA<ToolException>().having(
              (e) => e.message,
              'message',
              contains('Amharic'),
            ),
          ),
        );
      },
    );

    test('text already in the target language is returned as is', () async {
      mlkit.detected = 'en';
      final result = await _run(
        _imageTool('image/translate'),
        const ToolInput(files: [input], params: {'to': 'en'}),
      );
      expect(mlkit.translations, isEmpty);
      expect(result.text, 'HELLO');
    });

    test('non-Latin output is written as UTF-8', () async {
      mlkit.translation = 'こんにちは';
      final result = await _run(
        _imageTool('image/translate'),
        const ToolInput(files: [input], params: {'to': 'ja'}),
      );
      expect(await File(result.files.single.path).readAsString(), 'こんにちは');
    });
  });
}
