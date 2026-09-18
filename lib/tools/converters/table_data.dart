import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel_community/excel_community.dart';
import 'package:xml/xml.dart';

import 'package:anvil/core/tool_io.dart';

/// Canonical tabular representation shared by every csv/excel/xml-table
/// converter. Keeping one model collapses the N×N format matrix into
/// parse-source → encode-target.
///
/// Values are always strings (no type coercion), consistent with csv→json.
/// [rows] entries may be shorter than [headers] (ragged input → trailing nulls
/// on read; missing cells encode as empty).
class TableData {
  final List<String> headers;
  final List<List<String?>> rows;
  const TableData(this.headers, this.rows);

  String cell(int row, int col) {
    final r = rows[row];
    return (col < r.length ? r[col] : null) ?? '';
  }

  // ── CSV ──────────────────────────────────────────────────────────────────

  static TableData parseCsv(String csv) {
    final raw = const CsvDecoder(
      fieldDelimiter: ',',
      dynamicTyping: false,
      skipEmptyLines: true,
    ).convert(csv);
    if (raw.isEmpty) {
      throw const ToolException('The CSV file is empty.');
    }
    return _fromRaw([for (final row in raw) [for (final c in row) c?.toString()]]);
  }

  String toCsv() {
    final out = <List<String>>[
      headers,
      for (var r = 0; r < rows.length; r++)
        [for (var c = 0; c < headers.length; c++) cell(r, c)],
    ];
    return const CsvEncoder(fieldDelimiter: ',', lineDelimiter: '\n').convert(out);
  }

  // ── Excel (.xlsx) ──────────────────────────────────────────────────────────

  /// Parses the FIRST worksheet only; formulas/styles are not preserved.
  static TableData parseExcel(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.where((s) => s.rows.isNotEmpty).firstOrNull;
    if (sheet == null) {
      throw const ToolException('The spreadsheet has no data.');
    }
    final raw = [
      for (final row in sheet.rows)
        [for (final data in row) _cellText(data?.value)],
    ];
    return _fromRaw(raw);
  }

  List<int> toExcelBytes() {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? excel.sheets.keys.first;
    final sheet = excel[sheetName];
    sheet.appendRow([for (final h in headers) TextCellValue(h)]);
    for (var r = 0; r < rows.length; r++) {
      sheet.appendRow([
        for (var c = 0; c < headers.length; c++) TextCellValue(cell(r, c)),
      ]);
    }
    final bytes = excel.encode();
    if (bytes == null) {
      throw const ToolException('Could not build the spreadsheet.');
    }
    return bytes;
  }

  // ── XML table ──────────────────────────────────────────────────────────────

  /// Reads `<table><row><field name="H">v</field>…</row></table>`. Lenient: also
  /// accepts direct child elements as columns (`<row><H>v</H></row>`), and any
  /// repeated element name as the row tag.
  static TableData parseXmlTable(String xml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on XmlException {
      throw const ToolException('The XML file is not well-formed.');
    }
    final root = doc.rootElement;
    var rowEls = root.findElements('row').toList();
    if (rowEls.isEmpty) rowEls = root.childElements.toList();
    if (rowEls.isEmpty) {
      throw const ToolException('The XML file has no rows.');
    }
    final maps = <Map<String, String>>[];
    for (final rowEl in rowEls) {
      final map = <String, String>{};
      final fields = rowEl.findElements('field').toList();
      if (fields.isNotEmpty) {
        for (final f in fields) {
          map[f.getAttribute('name') ?? f.localName] = f.innerText;
        }
      } else {
        for (final c in rowEl.childElements) {
          map[c.localName] = c.innerText;
        }
      }
      maps.add(map);
    }
    final headers = <String>[];
    for (final m in maps) {
      for (final k in m.keys) {
        if (!headers.contains(k)) headers.add(k);
      }
    }
    final rows = [
      for (final m in maps) [for (final h in headers) m[h]],
    ];
    return TableData(headers, rows);
  }

  String toXmlTable() {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('table', nest: () {
      for (var r = 0; r < rows.length; r++) {
        builder.element('row', nest: () {
          for (var c = 0; c < headers.length; c++) {
            builder.element('field', nest: () {
              builder.attribute('name', headers[c]);
              builder.text(cell(r, c));
            });
          }
        });
      }
    });
    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  // ── JSON records (array of objects) ──────────────────────────────────────

  String toJsonRecords() {
    final records = <Map<String, String?>>[
      for (var r = 0; r < rows.length; r++)
        {
          for (var c = 0; c < headers.length; c++)
            headers[c]: c < rows[r].length ? rows[r][c] : null,
        },
    ];
    return const JsonEncoder.withIndent('  ').convert(records);
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  /// First raw row = headers; the rest = data rows.
  static TableData _fromRaw(List<List<String?>> raw) {
    final headers = [for (final h in raw.first) h ?? ''];
    final rows = [for (final r in raw.skip(1)) r];
    return TableData(headers, rows);
  }

  static String _cellText(CellValue? v) => switch (v) {
    null => '',
    TextCellValue(:final value) => value.text ?? '',
    IntCellValue(:final value) => value.toString(),
    DoubleCellValue(:final value) => value.toString(),
    BoolCellValue(:final value) => value.toString(),
    FormulaCellValue(:final formula) => formula,
    DateCellValue() => v.toString(),
    TimeCellValue() => v.toString(),
    DateTimeCellValue() => v.toString(),
  };
}
