import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/image_engine.dart';
import 'package:anvil/tools/image/image_native_tools.dart';

/// FileService sandboxed into a per-run temp directory (no path_provider).
class _TempFileService extends FileService {
  final Directory _dir = Directory.systemTemp.createTempSync('anvil_border');
  @override
  Future<Directory> outputsDir() async => _dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('anvil/image');
  final calls = <MethodCall>[];
  final out = Uint8List.fromList([9, 9, 9]);

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return out;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await getIt.reset();
  });

  test('ImageEngine.border sends style over the channel', () async {
    await ImageEngine().border(
      Uint8List.fromList([1]),
      sizePx: 12,
      color: '#FFD9C7A8',
      style: 'polaroid',
    );
    final args = Map<String, Object?>.from(calls.single.arguments as Map);
    expect(calls.single.method, 'border');
    expect(args['style'], 'polaroid');
    expect(args['sizePx'], 12);
    expect(args['color'], '#FFD9C7A8');
  });

  test('the border tool forwards the screen params to the engine', () async {
    getIt
      ..registerLazySingleton<FileService>(_TempFileService.new)
      ..registerLazySingleton<ImageEngine>(ImageEngine.new);
    final tool = buildImageNativeTools().firstWhere(
      (t) => t.meta.qualifiedId == 'image/border',
    );
    final src = await getIt<FileService>().writeBytes('in.png', [1, 2, 3]);

    final events = await tool
        .run(
          ToolInput(
            files: [InputFile(path: src.path, name: 'in.png')],
            params: const {
              'sizePx': 48,
              'color': '#FF1A1B1E',
              'style': 'square',
            },
          ),
        )
        .toList();

    expect(events.last, isA<ToolSucceeded>());
    final call = calls.singleWhere((c) => c.method == 'border');
    final args = Map<String, Object?>.from(call.arguments as Map);
    expect(args['style'], 'square');
    expect(args['sizePx'], 48);
    expect(args['color'], '#FF1A1B1E');
  });
}
