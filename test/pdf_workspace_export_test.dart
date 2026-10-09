/// Host test for the PDF workspace's single Export (`pdf/workspace`): a plan
/// that drops, reorders, rotates, crops, annotates and splits must come out as
/// real PDFs with the planned structure. Runs against the real [PdfEngine]
/// (Rust native asset), like pdf_engine_test.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/tools/pdf/pdf_tools.dart';
import 'package:anvil/tools/pdf/pdf_workspace_plan.dart';

class _FakeFileService implements FileService {
  _FakeFileService(this.dir);
  final Directory dir;

  @override
  Future<List<int>> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<File> writeBytes(String fileName, List<int> b) async {
    final f = File(p.join(dir.path, fileName));
    await f.writeAsBytes(b);
    return f;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ToolResult> _run(ToolInput input) async {
  final tool = ToolRegistry(
    const [],
    internal: [buildPdfWorkspaceTool()],
  ).byId('pdf/workspace')!;
  ToolResult? out;
  await for (final prog in tool.run(input)) {
    if (prog is ToolSucceeded) out = prog.result;
  }
  return out!;
}

void main() {
  // 8×8 solid-red PNG (the stamp decoder rejects 1×1 images).
  final solidPng = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR42mO4IyKCFTEMLQkAmD9BAeEqE6gAAAAASUVORK5CYII=',
    ),
  );

  late Directory tempDir;
  late PdfEngine engine;
  late List<InputFile> files;

  setUp(() async {
    await getIt.reset();
    tempDir = await Directory.systemTemp.createTemp('anvil_pdf_ws');
    engine = PdfEngine();
    getIt
      ..registerSingleton<FileService>(_FakeFileService(tempDir))
      ..registerSingleton<PdfEngine>(engine);
    final pdf = await engine.imagesToPdf([solidPng, solidPng, solidPng]);
    final pdfPath = p.join(tempDir.path, 'in.pdf');
    final pngPath = p.join(tempDir.path, 'sig.png');
    await File(pdfPath).writeAsBytes(pdf);
    await File(pngPath).writeAsBytes(solidPng);
    files = [
      InputFile(path: pdfPath, name: 'report.pdf'),
      InputFile(path: pngPath, name: 'sig.png'),
    ];
  });

  tearDown(() async {
    await engine.dispose();
    await getIt.reset();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  WorkspacePlan plan({int splitEvery = 0, bool empty = false}) => WorkspacePlan(
    name: 'report.pdf',
    splitEvery: splitEvery,
    pages: empty
        ? const []
        : const [
            WorkspacePlanPage(
              source: 0,
              page: 2,
              rotate: 90,
              crop: (l: 1, t: 1, r: 1, b: 1),
              texts: [
                WorkspacePlanText(
                  text: 'Confidential',
                  family: 'Times',
                  bold: true,
                  italic: false,
                  size: 4,
                  x: 1,
                  y: 2,
                  color: '#CC0000',
                ),
              ],
              stamps: [
                WorkspacePlanStamp(image: 1, x: 0, y: 0, width: 2, height: 2),
              ],
            ),
            WorkspacePlanPage(source: 0, page: 0),
          ],
  );

  ToolInput input(WorkspacePlan pl) =>
      ToolInput(files: files, params: {'planJson': jsonEncode(pl.toJson())});

  test('applies order, drop, rotation, crop and annotations', () async {
    final result = await _run(input(plan()));
    expect(result.files, hasLength(1));
    expect(result.files.single.name, 'report.pdf');
    final out = Uint8List.fromList(
      await File(result.files.single.path).readAsBytes(),
    );
    expect(await engine.pageCount(out), 2);
    final infos = await engine.pageInfos(out);
    expect(infos[0].rotation, 90);
    expect(infos[1].rotation, 0);
  });

  test('splitEvery produces one numbered file per chunk', () async {
    final result = await _run(input(plan(splitEvery: 1)));
    expect(
      [for (final f in result.files) f.name],
      ['report_1.pdf', 'report_2.pdf'],
    );
    for (final f in result.files) {
      final b = Uint8List.fromList(await File(f.path).readAsBytes());
      expect(await engine.pageCount(b), 1);
    }
  });

  test('an empty page list is rejected', () async {
    expect(
      () => _run(input(plan(empty: true))),
      throwsA(
        isA<ToolException>().having(
          (e) => e.message,
          'message',
          'Cannot delete every page of the PDF.',
        ),
      ),
    );
  });
}
