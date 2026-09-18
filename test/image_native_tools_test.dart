import 'dart:io';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/image_engine.dart';
import 'package:anvil/tools/image/image_native_tools.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every channel call and returns canned bytes/maps.
class _FakeChannel {
  final calls = <MethodCall>[];
  final out = Uint8List.fromList([9, 9, 9]);

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    return switch (call.method) {
      'split' => <Object?>[out, out, out, out],
      'metadataRead' => <String, Object?>{'Width': 3, 'Make': 'anvil'},
      _ => out,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeChannel fake;
  final src = Uint8List.fromList([1, 2, 3]);

  setUp(() {
    fake = _FakeChannel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('anvil/image'), fake.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('anvil/image'), null);
  });

  group('ImageEngine wrappers pass op + args over the channel', () {
    final engine = ImageEngine();

    test('convert', () async {
      final out = await engine.convert(src, format: 'jpg', quality: 80);
      expect(out, fake.out);
      final call = fake.calls.single;
      expect(call.method, 'convert');
      final args = Map<String, Object?>.from(call.arguments as Map);
      expect(args['format'], 'jpg');
      expect(args['quality'], 80);
      expect(args['src'], src);
    });

    test('resize/crop/border carry their geometry', () async {
      await engine.resize(src, width: 100, height: 0, format: 'png');
      await engine.crop(src, x: 1, y: 2, width: 3, height: 4);
      await engine.border(src, sizePx: 5, color: '#80FF0000');
      final [resize, crop, border] = fake.calls;
      expect(resize.method, 'resize');
      expect((resize.arguments as Map)['width'], 100);
      expect((crop.arguments as Map)['height'], 4);
      expect((border.arguments as Map)['color'], '#80FF0000');
    });

    test('split returns every tile', () async {
      final tiles = await engine.split(src, rows: 2, cols: 2);
      expect(tiles, hasLength(4));
      expect(fake.calls.single.method, 'split');
    });

    test('metadataRead returns the map', () async {
      final meta = await engine.metadataRead(src);
      expect(meta['Make'], 'anvil');
    });

    test('composite carries layers with per-layer geometry', () async {
      await engine.composite(src, [
        {
          'overlay': src,
          'x': 10,
          'y': 20,
          'width': 50,
          'height': 60,
          'rotation': 15.0,
        },
      ]);
      final call = fake.calls.single;
      expect(call.method, 'composite');
      final args = Map<String, Object?>.from(call.arguments as Map);
      expect(args['src'], src);
      final layers = (args['layers'] as List).cast<Map>();
      expect(layers, hasLength(1));
      final l = Map<String, Object?>.from(layers.first);
      expect(l['overlay'], src);
      expect(l['x'], 10);
      expect(l['y'], 20);
      expect(l['width'], 50);
      expect(l['height'], 60);
      expect(l['rotation'], 15.0);
    });

    test('platform errors surface as ToolException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('anvil/image'),
              (call) async {
        throw PlatformException(code: 'image_op', message: 'boom');
      });
      expect(
        () => ImageEngine().convert(src, format: 'png'),
        throwsA(isA<ToolException>()
            .having((e) => e.message, 'message', 'boom')),
      );
    });
  });

  group('native image tools', () {
    test('all 21 native slugs registered under the image category', () {
      const expected = {
        'add-images', 'border', 'collage-maker', 'combine-maker', 'compress',
        'crop', 'crop-circle', 'flip', 'grayscale', 'heic-to-jpg',
        'heic-to-png', 'jpg-to-png', 'jpg-to-webp', 'metadata', 'pixelate',
        'png-to-jpg', 'png-to-webp', 'resize', 'split', 'webp-to-jpg',
        'webp-to-png',
      };
      final tools = buildImageNativeTools();
      expect(tools.map((t) => t.meta.id).toSet(), expected);
      expect(
          tools.every((t) => t.meta.category == ToolCategory.image), isTrue);
      expect(tools.every((t) => t.engine == EngineKind.image), isTrue);
    });

    test('grayscale tool streams to ToolSucceeded and writes output',
        () async {
      await getIt.reset();
      getIt
        ..registerLazySingleton<FileService>(_TempFileService.new)
        ..registerLazySingleton<ImageEngine>(ImageEngine.new);

      final tool = buildImageNativeTools()
          .firstWhere((t) => t.meta.id == 'grayscale');
      final inFile =
          await getIt<FileService>().writeBytes('in.png', [1, 2, 3]);

      final events = await tool
          .run(ToolInput(files: [
            InputFile(path: inFile.path, name: 'in.png', mimeType: 'image/png')
          ]))
          .toList();
      expect(events.whereType<ToolRunning>(), isNotEmpty);
      final result = (events.last as ToolSucceeded).result;
      expect(result.files.single.name, 'in.png');
      expect(await File(result.files.single.path).readAsBytes(), fake.out);
      expect(fake.calls.any((c) => c.method == 'grayscale'), isTrue);
      await getIt.reset();
    });

    test('add-images composites overlays at the editor geometry', () async {
      await getIt.reset();
      getIt
        ..registerLazySingleton<FileService>(_TempFileService.new)
        ..registerLazySingleton<ImageEngine>(ImageEngine.new);
      final tool = buildImageNativeTools()
          .firstWhere((t) => t.meta.id == 'add-images');
      final base = await getIt<FileService>().writeBytes('a.png', [1, 2, 3]);
      final ov = await getIt<FileService>().writeBytes('b.png', [4, 5, 6]);

      final events = await tool.run(ToolInput(files: [
        InputFile(path: base.path, name: 'a.png'),
        InputFile(path: ov.path, name: 'b.png'),
      ], params: {
        'layers': [
          {'fileIndex': 1, 'x': 10, 'y': 20, 'width': 50, 'height': 60,
              'rotation': 15.0},
        ],
      })).toList();

      final call = fake.calls.firstWhere((c) => c.method == 'composite');
      final layers = ((call.arguments as Map)['layers'] as List).cast<Map>();
      expect(layers, hasLength(1));
      expect(layers.first['x'], 10);
      expect(layers.first['width'], 50);
      final result = (events.last as ToolSucceeded).result;
      expect(result.files.single.name, endsWith('.png'));
      await getIt.reset();
    });

    test('add-images with no layers stacks each overlay at native size',
        () async {
      await getIt.reset();
      getIt
        ..registerLazySingleton<FileService>(_TempFileService.new)
        ..registerLazySingleton<ImageEngine>(ImageEngine.new);
      final tool = buildImageNativeTools()
          .firstWhere((t) => t.meta.id == 'add-images');
      final base = await getIt<FileService>().writeBytes('a.png', [1, 2, 3]);
      final ov = await getIt<FileService>().writeBytes('b.png', [4, 5, 6]);

      final events = await tool.run(ToolInput(files: [
        InputFile(path: base.path, name: 'a.png'),
        InputFile(path: ov.path, name: 'b.png'),
      ])).toList();

      final call = fake.calls.firstWhere((c) => c.method == 'composite');
      final layers = ((call.arguments as Map)['layers'] as List).cast<Map>();
      expect(layers, hasLength(1));
      expect(layers.first['width'], 0);
      expect((events.last as ToolSucceeded).result.files.single.name,
          endsWith('.png'));
      await getIt.reset();
    });
  });
}

/// FileService sandboxed into a per-run temp directory (no path_provider).
class _TempFileService extends FileService {
  final Directory _dir = Directory.systemTemp.createTempSync('anvil_test');
  @override
  Future<Directory> outputsDir() async => _dir;
}
