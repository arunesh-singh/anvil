/// Deterministic tabular/markup converters (csv, xlsx, xml, json) plus the
/// two table splitters. Pure transforms are top-level so they run through
/// [runOffThread] and stay host-tested; [buildConverters] is the single
/// registration list for the category.
library;

import 'dart:math' show min;

import 'package:flutter/material.dart' show IconData, Icons;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/isolate_runner.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/tools/converters/json_xml.dart';
import 'package:anvil/tools/converters/table_data.dart';

// ── MIME types ──────────────────────────────────────────────────────────────
const _csvMime = 'text/csv';
const _xmlMime = 'application/xml';
const _jsonMime = 'application/json';
const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

// ── Pure transforms (unit-tested cores; isolate-safe top-level functions) ────
String csvToJson(String s) => TableData.parseCsv(s).toJsonRecords();
String csvToXml(String s) => TableData.parseCsv(s).toXmlTable();
List<int> csvToExcel(String s) => TableData.parseCsv(s).toExcelBytes();
String xmlToCsv(String s) => TableData.parseXmlTable(s).toCsv();
List<int> xmlToExcel(String s) => TableData.parseXmlTable(s).toExcelBytes();
String excelToCsv(List<int> b) => TableData.parseExcel(b).toCsv();
String excelToXml(List<int> b) => TableData.parseExcel(b).toXmlTable();

/// How a split cuts a table. [files] > 0 wins over [rowsPerFile] and cuts
/// into that many near-equal files (earlier files take the remainder rows,
/// clamped to one file per row). [repeatHeader] false keeps the header row
/// in the FIRST file only; later files hold data rows only, so concatenating
/// the files reproduces the source.
class SplitSpec {
  const SplitSpec({
    this.rowsPerFile = 100,
    this.files = 0,
    this.repeatHeader = true,
  });

  final int rowsPerFile;
  final int files;
  final bool repeatHeader;

  /// Reads the split tools' params; anything missing or out of range keeps
  /// the default, so an agent call naming only `rowsPerFile` behaves as before.
  factory SplitSpec.fromParams(Map<String, dynamic> p) => SplitSpec(
    rowsPerFile: switch (p['rowsPerFile']) {
      final int v when v > 0 => v,
      _ => _splitRowsParam.defaultValue,
    },
    files: switch (p['files']) {
      final int v when v > 0 => v,
      _ => 0,
    },
    repeatHeader: p['header'] != 'no',
  );
}

/// Data-row count of each output file for a table of [rowCount] rows. Always
/// at least one file (an empty table still yields its header-only file).
List<int> splitPlan(int rowCount, SplitSpec spec) {
  if (spec.files > 0) {
    final n = min(spec.files, rowCount < 1 ? 1 : rowCount);
    final base = rowCount ~/ n;
    final extra = rowCount % n;
    return [for (var i = 0; i < n; i++) base + (i < extra ? 1 : 0)];
  }
  if (spec.rowsPerFile < 1) {
    throw const ToolException('Rows per file must be at least 1.');
  }
  if (rowCount == 0) return const [0];
  return [
    for (var i = 0; i < rowCount; i += spec.rowsPerFile)
      min(spec.rowsPerFile, rowCount - i),
  ];
}

List<TableData> _chunk(TableData t, SplitSpec spec) {
  final chunks = <TableData>[];
  var start = 0;
  for (final n in splitPlan(t.rows.length, spec)) {
    chunks.add(TableData(t.headers, t.rows.sublist(start, start + n)));
    start += n;
  }
  return chunks;
}

List<String> splitCsv(String s, [SplitSpec spec = const SplitSpec()]) {
  final chunks = _chunk(TableData.parseCsv(s), spec);
  return [
    for (var i = 0; i < chunks.length; i++)
      chunks[i].toCsv(header: spec.repeatHeader || i == 0),
  ];
}

List<List<int>> splitExcel(List<int> b, [SplitSpec spec = const SplitSpec()]) {
  final chunks = _chunk(TableData.parseExcel(b), spec);
  return [
    for (var i = 0; i < chunks.length; i++)
      chunks[i].toExcelBytes(header: spec.repeatHeader || i == 0),
  ];
}

// ── Generic tool shapes ──────────────────────────────────────────────────────

String _outName(String input, String ext, {int? index}) {
  final dot = input.lastIndexOf('.');
  final base = dot <= 0 ? input : input.substring(0, dot);
  return index == null ? '$base.$ext' : '${base}_${index + 1}.$ext';
}

class _TextToText extends BaseToolModule {
  _TextToText(this.meta, this._fn, this._ext, this._mime);
  @override
  final ToolMeta meta;
  final String Function(String) _fn;
  final String _ext;
  final String _mime;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading file…');
    final f = input.files.single;
    final content = await getIt<FileService>().readString(f.path);
    yield const ToolRunning(fraction: 0.4, message: 'Converting…');
    final fn = _fn;
    final out = await runOffThread(() => fn(content));
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(f.name, _ext);
    final file = await getIt<FileService>().writeString(name, out);
    yield ToolSucceeded(
      ToolResult(
        files: [OutputFile(path: file.path, name: name, mimeType: _mime)],
      ),
    );
  }
}

class _TextToBytes extends BaseToolModule {
  _TextToBytes(this.meta, this._fn, this._ext, this._mime);
  @override
  final ToolMeta meta;
  final List<int> Function(String) _fn;
  final String _ext;
  final String _mime;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading file…');
    final f = input.files.single;
    final content = await getIt<FileService>().readString(f.path);
    yield const ToolRunning(fraction: 0.4, message: 'Converting…');
    final fn = _fn;
    final out = await runOffThread(() => fn(content));
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(f.name, _ext);
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(
      ToolResult(
        files: [OutputFile(path: file.path, name: name, mimeType: _mime)],
      ),
    );
  }
}

class _BytesToText extends BaseToolModule {
  _BytesToText(this.meta, this._fn, this._ext, this._mime);
  @override
  final ToolMeta meta;
  final String Function(List<int>) _fn;
  final String _ext;
  final String _mime;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading file…');
    final f = input.files.single;
    final content = await getIt<FileService>().readBytes(f.path);
    yield const ToolRunning(fraction: 0.4, message: 'Converting…');
    final fn = _fn;
    final out = await runOffThread(() => fn(content));
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(f.name, _ext);
    final file = await getIt<FileService>().writeString(name, out);
    yield ToolSucceeded(
      ToolResult(
        files: [OutputFile(path: file.path, name: name, mimeType: _mime)],
      ),
    );
  }
}

class _TextToManyText extends BaseToolModule {
  _TextToManyText(this.meta, this._fn, this._ext, this._mime);
  @override
  final ToolMeta meta;
  final List<String> Function(String, SplitSpec) _fn;
  final String _ext;
  final String _mime;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading file…');
    final f = input.files.single;
    final content = await getIt<FileService>().readString(f.path);
    final spec = SplitSpec.fromParams(input.params);
    yield const ToolRunning(fraction: 0.4, message: 'Splitting…');
    final fn = _fn;
    final parts = await runOffThread(() => fn(content, spec));
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final files = <OutputFile>[];
    for (var i = 0; i < parts.length; i++) {
      final name = _outName(f.name, _ext, index: i);
      final file = await getIt<FileService>().writeString(name, parts[i]);
      files.add(OutputFile(path: file.path, name: name, mimeType: _mime));
    }
    yield ToolSucceeded(ToolResult(files: files));
  }
}

class _BytesToManyBytes extends BaseToolModule {
  _BytesToManyBytes(this.meta, this._fn, this._ext, this._mime);
  @override
  final ToolMeta meta;
  final List<List<int>> Function(List<int>, SplitSpec) _fn;
  final String _ext;
  final String _mime;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading file…');
    final f = input.files.single;
    final content = await getIt<FileService>().readBytes(f.path);
    final spec = SplitSpec.fromParams(input.params);
    yield const ToolRunning(fraction: 0.4, message: 'Splitting…');
    final fn = _fn;
    final parts = await runOffThread(() => fn(content, spec));
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final files = <OutputFile>[];
    for (var i = 0; i < parts.length; i++) {
      final name = _outName(f.name, _ext, index: i);
      final file = await getIt<FileService>().writeBytes(name, parts[i]);
      files.add(OutputFile(path: file.path, name: name, mimeType: _mime));
    }
    yield ToolSucceeded(ToolResult(files: files));
  }
}

// ── Registration ─────────────────────────────────────────────────────────────

ToolMeta _meta(
  String id,
  String label,
  IconData icon,
  String description,
  List<String> accepts, {
  List<ToolParam> params = const [],
}) => ToolMeta(
  id: id,
  category: ToolCategory.converter,
  label: label,
  icon: icon,
  description: description,
  tinywowSlug: id,
  acceptedExtensions: accepts,
  params: params,
);

const _splitRowsParam = ToolParam(
  key: 'rowsPerFile',
  label: 'Rows per file',
  defaultValue: 100,
  min: 1,
);

const _splitFilesParam = ToolParam(
  key: 'files',
  label: 'Number of files',
  helperText: '0 = cut by rows per file instead',
);

const _splitHeaderParam = ToolParam(
  key: 'header',
  label: 'Repeat header in every file',
  type: ToolParamType.choice,
  choices: ['yes', 'no'],
  defaultText: 'yes',
  helperText: 'no = only the first file keeps the header row',
);

const _splitParams = [_splitRowsParam, _splitFilesParam, _splitHeaderParam];

/// Every converter tool. The single registration list for this category.
List<ToolModule> buildConverters() => [
  _TextToText(
    _meta(
      'csv-to-json',
      'CSV to JSON',
      Icons.data_object,
      'Convert a CSV file into a JSON array of objects.',
      ['csv'],
    ),
    csvToJson,
    'json',
    _jsonMime,
  ),
  _TextToText(
    _meta(
      'csv-to-xml',
      'CSV to XML',
      Icons.code,
      'Convert a CSV file into an XML table.',
      ['csv'],
    ),
    csvToXml,
    'xml',
    _xmlMime,
  ),
  _TextToBytes(
    _meta(
      'csv-to-excel',
      'CSV to Excel',
      Icons.table_chart,
      'Convert a CSV file into an Excel (.xlsx) spreadsheet.',
      ['csv'],
    ),
    csvToExcel,
    'xlsx',
    _xlsxMime,
  ),
  _TextToText(
    _meta(
      'xml-to-csv',
      'XML to CSV',
      Icons.grid_on,
      'Convert an XML table into a CSV file.',
      ['xml'],
    ),
    xmlToCsv,
    'csv',
    _csvMime,
  ),
  _TextToBytes(
    _meta(
      'xml-to-excel',
      'XML to Excel',
      Icons.table_chart,
      'Convert an XML table into an Excel (.xlsx) spreadsheet.',
      ['xml'],
    ),
    xmlToExcel,
    'xlsx',
    _xlsxMime,
  ),
  _TextToText(
    _meta(
      'xml-to-json',
      'XML to JSON',
      Icons.data_object,
      'Convert an XML document into JSON.',
      ['xml'],
    ),
    xmlToJson,
    'json',
    _jsonMime,
  ),
  _TextToText(
    _meta(
      'json-to-xml',
      'JSON to XML',
      Icons.code,
      'Convert a JSON document into XML.',
      ['json'],
    ),
    jsonToXml,
    'xml',
    _xmlMime,
  ),
  _BytesToText(
    _meta(
      'excel-to-csv',
      'Excel to CSV',
      Icons.grid_on,
      'Convert the first sheet of an Excel file into CSV.',
      ['xlsx'],
    ),
    excelToCsv,
    'csv',
    _csvMime,
  ),
  _BytesToText(
    _meta(
      'excel-to-xml',
      'Excel to XML',
      Icons.code,
      'Convert the first sheet of an Excel file into an XML table.',
      ['xlsx'],
    ),
    excelToXml,
    'xml',
    _xmlMime,
  ),
  _TextToManyText(
    _meta(
      'split-csv',
      'Split CSV',
      Icons.call_split,
      'Split a CSV file into smaller files by row count or file count.',
      ['csv'],
      params: _splitParams,
    ),
    splitCsv,
    'csv',
    _csvMime,
  ),
  _BytesToManyBytes(
    _meta(
      'split-excel',
      'Split Excel',
      Icons.call_split,
      'Split an Excel file into smaller files by row count or file count.',
      ['xlsx'],
      params: _splitParams,
    ),
    splitExcel,
    'xlsx',
    _xlsxMime,
  ),
];
