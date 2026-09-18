/// Host test for the composite `pdf/photo-caption` tool: a PNG in + a caption
/// param out a real one-page PDF. Uses a fake [FileService] and passes a PNG
/// (which `_toPdfReadyImage` hands through untouched), so no native PDF engine
/// or platform channel is exercised.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/tools/pdf/pdf_tools.dart';

class _FakeFileService implements FileService {
  _FakeFileService(this.dir);
  final Directory dir;
  Uint8List bytes = Uint8List(0);

  @override
  Future<Directory> outputsDir() async => dir;

  @override
  Future<List<int>> readBytes(String path) async => bytes;

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

Uint8List _tinyPng() {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(200, 120, 60));
  return Uint8List.fromList(img.encodePng(image));
}

Future<ToolResult> _run(ToolModule tool, ToolInput input) async {
  ToolResult? out;
  await for (final prog in tool.run(input)) {
    if (prog is ToolSucceeded) out = prog.result;
    if (prog is ToolFailed) fail(prog.message);
  }
  return out!;
}

ToolModule _tool() => ToolRegistry(buildPdfTools()).byId('pdf/photo-caption')!;

void main() {
  late Directory tempDir;

  setUp(() async {
    await getIt.reset();
    tempDir = await Directory.systemTemp.createTemp('anvil_photo_caption');
    getIt.registerSingleton<FileService>(
      _FakeFileService(tempDir)..bytes = _tinyPng(),
    );
  });

  tearDown(() async {
    await getIt.reset();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('composes a single-page PDF from an image and a caption', () async {
    final result = await _run(
      _tool(),
      const ToolInput(
        files: [InputFile(path: '/tmp/in.png', name: 'in.png')],
        params: {'caption': 'Taco'},
      ),
    );
    expect(result.files.single.name, endsWith('.pdf'));
    expect(result.files.single.mimeType, 'application/pdf');
    final bytes = await File(result.files.single.path).readAsBytes();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('centers the image with no caption when none is given', () async {
    final result = await _run(
      _tool(),
      const ToolInput(files: [InputFile(path: '/tmp/in.png', name: 'in.png')]),
    );
    expect(result.files.single.mimeType, 'application/pdf');
    final bytes = await File(result.files.single.path).readAsBytes();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
