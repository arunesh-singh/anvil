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

List<TableData> _chunk(TableData t, int rowsPerFile) {
  if (rowsPerFile < 1) {
    throw const ToolException('Rows per file must be at least 1.');
  }
  if (t.rows.isEmpty) return [TableData(t.headers, const [])];
  return [
    for (var i = 0; i < t.rows.length; i += rowsPerFile)
      TableData(t.headers, t.rows.sublist(i, min(i + rowsPerFile, t.rows.length))),
  ];
}

List<String> splitCsv(String s, int rowsPerFile) =>
    [for (final c in _chunk(TableData.parseCsv(s), rowsPerFile)) c.toCsv()];

List<List<int>> splitExcel(List<int> b, int rowsPerFile) =>
    [for (final c in _chunk(TableData.parseExcel(b), rowsPerFile)) c.toExcelBytes()];

// ── Generic tool shapes ──────────────────────────────────────────────────────

String _outName(String input, String ext, {int? index}) {
  final dot = input.lastIndexOf('.');
  final base = dot <= 0 ? input : input.substring(0, dot);
  return index == null ? '$base.$ext' : '${base}_${index + 1}.$ext';
}

int _rowsPerFile(ToolModule tool, ToolInput input) {
  final v = input.params['rowsPerFile'];
  if (v is int && v > 0) return v;
  return tool.meta.params.isNotEmpty ? tool.meta.params.first.defaultValue : 100;
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
      ToolResult(files: [OutputFile(path: file.path, name: name, mimeType: _mime)]),
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
      ToolResult(files: [OutputFile(path: file.path, name: name, mimeType: _mime)]),
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
      ToolResult(files: [OutputFile(path: file.path, name: name, mimeType: _mime)]),
    );
  }
}

class _TextToManyText extends BaseToolModule {
  _TextToManyText(this.meta, this._fn, this._ext, this._mime);
  @override
  final ToolMeta meta;
  final List<String> Function(String, int) _fn;
  final String _ext;
  final String _mime;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading file…');
    final f = input.files.single;
    final content = await getIt<FileService>().readString(f.path);
    final n = _rowsPerFile(this, input);
    yield const ToolRunning(fraction: 0.4, message: 'Splitting…');
    final fn = _fn;
    final parts = await runOffThread(() => fn(content, n));
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
  final List<List<int>> Function(List<int>, int) _fn;
  final String _ext;
  final String _mime;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading file…');
    final f = input.files.single;
    final content = await getIt<FileService>().readBytes(f.path);
    final n = _rowsPerFile(this, input);
    yield const ToolRunning(fraction: 0.4, message: 'Splitting…');
    final fn = _fn;
    final parts = await runOffThread(() => fn(content, n));
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

const _splitParam = ToolParam(
  key: 'rowsPerFile',
  label: 'Rows per file',
  defaultValue: 100,
);

/// Every converter tool. The single registration list for this category.
List<ToolModule> buildConverters() => [
  _TextToText(
    _meta('csv-to-json', 'CSV to JSON', Icons.data_object,
        'Convert a CSV file into a JSON array of objects.', ['csv']),
    csvToJson, 'json', _jsonMime,
  ),
  _TextToText(
    _meta('csv-to-xml', 'CSV to XML', Icons.code,
        'Convert a CSV file into an XML table.', ['csv']),
    csvToXml, 'xml', _xmlMime,
  ),
  _TextToBytes(
    _meta('csv-to-excel', 'CSV to Excel', Icons.table_chart,
        'Convert a CSV file into an Excel (.xlsx) spreadsheet.', ['csv']),
    csvToExcel, 'xlsx', _xlsxMime,
  ),
  _TextToText(
    _meta('xml-to-csv', 'XML to CSV', Icons.grid_on,
        'Convert an XML table into a CSV file.', ['xml']),
    xmlToCsv, 'csv', _csvMime,
  ),
  _TextToBytes(
    _meta('xml-to-excel', 'XML to Excel', Icons.table_chart,
        'Convert an XML table into an Excel (.xlsx) spreadsheet.', ['xml']),
    xmlToExcel, 'xlsx', _xlsxMime,
  ),
  _TextToText(
    _meta('xml-to-json', 'XML to JSON', Icons.data_object,
        'Convert an XML document into JSON.', ['xml']),
    xmlToJson, 'json', _jsonMime,
  ),
  _TextToText(
    _meta('json-to-xml', 'JSON to XML', Icons.code,
        'Convert a JSON document into XML.', ['json']),
    jsonToXml, 'xml', _xmlMime,
  ),
  _BytesToText(
    _meta('excel-to-csv', 'Excel to CSV', Icons.grid_on,
        'Convert the first sheet of an Excel file into CSV.', ['xlsx']),
    excelToCsv, 'csv', _csvMime,
  ),
  _BytesToText(
    _meta('excel-to-xml', 'Excel to XML', Icons.code,
        'Convert the first sheet of an Excel file into an XML table.', ['xlsx']),
    excelToXml, 'xml', _xmlMime,
  ),
  _TextToManyText(
    _meta('split-csv', 'Split CSV', Icons.call_split,
        'Split a CSV file into smaller files by row count.', ['csv'],
        params: [_splitParam]),
    splitCsv, 'csv', _csvMime,
  ),
  _BytesToManyBytes(
    _meta('split-excel', 'Split Excel', Icons.call_split,
        'Split an Excel file into smaller files by row count.', ['xlsx'],
        params: [_splitParam]),
    splitExcel, 'xlsx', _xlsxMime,
  ),
];
