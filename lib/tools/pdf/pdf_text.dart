/// Pure helpers for the PDF tools: page-list parsing and text→CSV heuristics.
/// No Flutter/plugin imports — host-unit-testable (test/pdf_text_test.dart).
library;

import 'package:csv/csv.dart';

import 'package:anvil/core/tool_io.dart';

/// Parses a 1-based page-list string like `2,4-6,9` into sorted, de-duplicated
/// 0-based indices. [pageCount] bounds the input; out-of-range pages throw a
/// user-facing [ToolException].
List<int> parsePageList(String spec, int pageCount) {
  final out = <int>{};
  for (final part in spec.split(',')) {
    final token = part.trim();
    if (token.isEmpty) continue;
    final range = token.split('-');
    final int from;
    final int to;
    if (range.length == 1) {
      from = to = int.tryParse(range[0].trim()) ?? -1;
    } else if (range.length == 2) {
      from = int.tryParse(range[0].trim()) ?? -1;
      to = int.tryParse(range[1].trim()) ?? -1;
    } else {
      from = to = -1;
    }
    if (from < 1 || to < from) {
      throw ToolException(
          "Invalid page selection '$token' — use pages like 2,4-6,9.");
    }
    if (to > pageCount) {
      throw ToolException(
          'Page $to is out of range — this PDF has $pageCount pages.');
    }
    for (var p = from; p <= to; p++) {
      out.add(p - 1);
    }
  }
  if (out.isEmpty) {
    throw const ToolException('Select at least one page (e.g. 2,4-6,9).');
  }
  return out.toList()..sort();
}

/// Converts extracted PDF text into CSV: each non-empty line becomes a row;
/// columns split on tabs or runs of 2+ spaces. Ragged rows are padded so every
/// row has the same column count.
String pdfTextToCsv(String text) {
  final splitter = RegExp(r'\t+| {2,}');
  final rows = <List<String>>[
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty)
        [for (final c in line.trim().split(splitter)) c.trim()],
  ];
  if (rows.isEmpty) {
    throw const ToolException('No extractable text found in this PDF.');
  }
  var width = 0;
  for (final r in rows) {
    if (r.length > width) width = r.length;
  }
  for (final r in rows) {
    while (r.length < width) {
      r.add('');
    }
  }
  return const CsvEncoder(fieldDelimiter: ',', lineDelimiter: '\n')
      .convert(rows);
}
