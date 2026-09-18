/// Host tests for attachment ingestion: text read + truncation, PDF/xlsx text
/// extraction through stub tools, image bytes vs. OCR by model vision, and
/// rejection of unsupported formats. Tools are stubbed via a getIt-registered
/// fake registry.
library;

import 'dart:io';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/agent/attachment_ingest.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';

/// A stub tool that yields a fixed [ToolResult].
class _StubTool extends BaseToolModule {
  _StubTool(this._meta, this._result);
  final ToolMeta _meta;
  final ToolResult _result;

  @override
  ToolMeta get meta => _meta;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield ToolSucceeded(_result);
  }
}

ToolMeta _meta(ToolCategory category, String id) => ToolMeta(
      id: id,
      category: category,
      label: id,
      icon: Icons.build,
      description: id,
      tinywowSlug: id,
      acceptedExtensions: const [],
    );

late Directory _tmp;

Future<InputFile> _write(String name, String content) async {
  final f = File('${_tmp.path}/$name');
  await f.writeAsString(content);
  return InputFile(path: f.path, name: name);
}

Future<InputFile> _writeBytes(String name, List<int> bytes) async {
  final f = File('${_tmp.path}/$name');
  await f.writeAsBytes(bytes);
  return InputFile(path: f.path, name: name);
}

void _registerTools(List<ToolModule> tools) {
  getIt.registerSingleton<ToolRegistry>(ToolRegistry(tools));
}

void main() {
  setUp(() async {
    _tmp = await Directory.systemTemp.createTemp('ingest_test');
  });

  tearDown(() async {
    await getIt.reset();
    await _tmp.delete(recursive: true);
  });

  test('a text file is read and truncated at the char budget', () async {
    _registerTools(const []);
    final file = await _write('big.txt', 'x' * 9000);
    final r = await ingestAttachment(file, modelSupportsImage: false);
    final text = (r as IngestedText).content;
    expect(text.endsWith('…[truncated]'), isTrue);
    expect(text.length, lessThan(9000));
    expect(text.startsWith('xxxx'), isTrue);
  });

  test('a PDF routes through pdf/extract-text', () async {
    _registerTools([
      _StubTool(_meta(ToolCategory.pdf, 'extract-text'),
          const ToolResult(files: [], text: 'the pdf body')),
    ]);
    final file = await _writeBytes('doc.pdf', const [1, 2, 3]);
    final r = await ingestAttachment(file, modelSupportsImage: false);
    expect((r as IngestedText).content, 'the pdf body');
  });

  test('a long PDF body is truncated so it cannot overflow the context',
      () async {
    // Regression: an un-truncated deployment-guide PDF pushed the prompt past
    // the model's 4096-token window (INVALID_ARGUMENT: token ids too long).
    _registerTools([
      _StubTool(_meta(ToolCategory.pdf, 'extract-text'),
          ToolResult(files: const [], text: 'p' * 9000)),
    ]);
    final file = await _writeBytes('guide.pdf', const [1, 2, 3]);
    final r = await ingestAttachment(file, modelSupportsImage: false);
    final text = (r as IngestedText).content;
    expect(text.endsWith('…[truncated]'), isTrue);
    expect(text.length, lessThan(9000));
  });

  test('an empty PDF is rejected as scanned', () async {
    _registerTools([
      _StubTool(_meta(ToolCategory.pdf, 'extract-text'),
          const ToolResult(files: [], text: '')),
    ]);
    final file = await _writeBytes('scan.pdf', const [0]);
    final r = await ingestAttachment(file, modelSupportsImage: false);
    expect(r, isA<IngestRejected>());
    expect((r as IngestRejected).reason, contains('scanned'));
  });

  test('a PNG becomes image bytes for a vision model', () async {
    _registerTools(const []);
    final file = await _writeBytes('shot.png', const [9, 8, 7, 6]);
    final r = await ingestAttachment(file, modelSupportsImage: true);
    expect((r as IngestedImage).bytes, [9, 8, 7, 6]);
  });

  test('a PNG is OCR-ed to text for a non-vision model', () async {
    _registerTools([
      _StubTool(_meta(ToolCategory.image, 'to-text'),
          const ToolResult(files: [], text: 'text in the photo')),
    ]);
    final file = await _writeBytes('shot.png', const [1]);
    final r = await ingestAttachment(file, modelSupportsImage: false);
    expect((r as IngestedText).content, 'text in the photo');
  });

  test('an xlsx routes through converter/excel-to-csv', () async {
    _registerTools([
      _StubTool(_meta(ToolCategory.converter, 'excel-to-csv'),
          const ToolResult(files: [], text: 'a,b\n1,2')),
    ]);
    final file = await _writeBytes('sheet.xlsx', const [1]);
    final r = await ingestAttachment(file, modelSupportsImage: false);
    expect((r as IngestedText).content, 'a,b\n1,2');
  });

  test('an unsupported format is rejected with a clear note', () async {
    _registerTools(const []);
    final file = await _writeBytes('paper.docx', const [1]);
    final r = await ingestAttachment(file, modelSupportsImage: false);
    expect(r, isA<IngestRejected>());
    expect((r as IngestRejected).reason, contains('.docx'));
  });
}
