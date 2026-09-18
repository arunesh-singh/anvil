/// Host test for the agent path of `pdf/create`: called with a page count (no
/// editor JSON), it must produce a real blank PDF the next chain step can use.
/// Runs against the real [PdfEngine] (Rust native asset), like pdf_engine_test.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/tools/pdf/pdf_tools.dart';
import 'package:anvil/engines/pdf_engine.dart';

class _FakeFileService implements FileService {
  _FakeFileService(this.dir);
  final Directory dir;

  @override
  Future<Directory> outputsDir() async => dir;

  @override
  Future<File> writeBytes(String fileName, List<int> b) async {
    final f = File(p.join(dir.path, fileName));
    await f.writeAsBytes(b);
    return f;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ToolResult> _run(ToolModule tool, ToolInput input) async {
  ToolResult? out;
  await for (final prog in tool.run(input)) {
    if (prog is ToolSucceeded) out = prog.result;
    if (prog is ToolFailed) fail(prog.message);
  }
  return out!;
}

ToolModule _tool() => ToolRegistry(buildPdfTools()).byId('pdf/create')!;

void main() {
  late Directory tempDir;
  late PdfEngine engine;

  setUp(() async {
    await getIt.reset();
    tempDir = await Directory.systemTemp.createTemp('anvil_pdf_create');
    engine = PdfEngine();
    getIt
      ..registerSingleton<FileService>(_FakeFileService(tempDir))
      ..registerSingleton<PdfEngine>(engine);
  });

  tearDown(() async {
    await engine.dispose();
    await getIt.reset();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('agent call with a page count produces a blank multi-page PDF', () async {
    final result = await _run(
      _tool(),
      const ToolInput(files: [], params: {'pages': 2}),
    );
    expect(result.files.single.mimeType, 'application/pdf');
    final bytes = await File(result.files.single.path).readAsBytes();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(await engine.pageCount(Uint8List.fromList(bytes)), 2);
  });

  test('agent call with no params defaults to a single A4 page', () async {
    final result = await _run(
      _tool(),
      const ToolInput(files: []),
    );
    final bytes = await File(result.files.single.path).readAsBytes();
    expect(await engine.pageCount(Uint8List.fromList(bytes)), 1);
  });
}
