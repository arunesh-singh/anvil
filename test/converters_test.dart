import 'dart:convert';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/tools/converters/converter_tools.dart';
import 'package:anvil/tools/converters/json_xml.dart';
import 'package:anvil/tools/converters/table_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records view of a CSV, for format-agnostic comparison.
List<Map<String, String?>> records(String csv) =>
    (jsonDecode(csvToJson(csv)) as List).cast<Map<String, dynamic>>().map((m) {
      return m.map((k, v) => MapEntry(k, v as String?));
    }).toList();

const _sample = 'Name,Age\nAlice,30\nBob,25';

void main() {
  group('tabular round-trips preserve headers + string values', () {
    test('csv -> xml -> csv', () {
      expect(records(xmlToCsv(csvToXml(_sample))), records(_sample));
    });

    test('csv -> excel -> csv', () {
      expect(records(excelToCsv(csvToExcel(_sample))), records(_sample));
    });

    test('csv -> excel -> xml -> csv', () {
      final bytes = csvToExcel(_sample);
      expect(records(xmlToCsv(excelToXml(bytes))), records(_sample));
    });

    test('numeric-looking values stay strings through excel', () {
      final back = records(excelToCsv(csvToExcel(_sample)));
      expect(back.first['Age'], '30');
      expect(back.first['Age'], isA<String>());
    });
  });

  group('xml table parsing', () {
    test('reads element-tag style rows', () {
      const xml =
          '<table><row><Name>Al</Name><Age>9</Age></row>'
          '<row><Name>Bo</Name><Age>8</Age></row></table>';
      final t = TableData.parseXmlTable(xml);
      expect(t.headers, ['Name', 'Age']);
      expect(t.cell(0, 0), 'Al');
      expect(t.cell(1, 1), '8');
    });

    test('malformed xml throws ToolException', () {
      expect(() => xmlToCsv('<table><row>'), throwsA(isA<ToolException>()));
    });
  });

  group('split-csv', () {
    const five = 'Name,N\na,1\nb,2\nc,3\nd,4\ne,5';
    List<String?> names(String csv) => [
      for (final m in records(csv)) m['Name'],
    ];

    test('rowsPerFile=2 over 5 rows -> 3 files, header repeated', () {
      final parts = splitCsv(five, const SplitSpec(rowsPerFile: 2));
      expect(parts, hasLength(3));
      for (final p in parts) {
        expect(p.startsWith('Name,N'), isTrue);
      }
      expect(names(parts[0]), ['a', 'b']);
      expect(names(parts[1]), ['c', 'd']);
      expect(names(parts[2]), ['e']);
    });

    test('default spec is 100 rows per file with headers (regression)', () {
      final rows = [for (var i = 0; i < 250; i++) 'r$i,$i'].join('\n');
      final parts = splitCsv('Name,N\n$rows');
      expect(parts, hasLength(3));
      expect([for (final p in parts) records(p).length], [100, 100, 50]);
      expect(parts.every((p) => p.startsWith('Name,N\n')), isTrue);
      // An agent call naming only rowsPerFile (or nothing) keeps that shape.
      final spec = SplitSpec.fromParams(const {'rowsPerFile': 100});
      expect(splitCsv('Name,N\n$rows', spec), parts);
      expect(SplitSpec.fromParams(const {}).rowsPerFile, 100);
    });

    test('files splits into near-equal parts, remainder first', () {
      final parts = splitCsv(five, const SplitSpec(files: 2));
      expect(parts.map(names), [
        ['a', 'b', 'c'],
        ['d', 'e'],
      ]);
      expect(splitCsv(five, const SplitSpec(files: 5)).map(names), [
        ['a'],
        ['b'],
        ['c'],
        ['d'],
        ['e'],
      ]);
    });

    test('files wins over rowsPerFile and clamps to one file per row', () {
      final parts = splitCsv(five, const SplitSpec(rowsPerFile: 1, files: 9));
      expect(parts, hasLength(5));
      expect(parts.map(names).expand((n) => n), ['a', 'b', 'c', 'd', 'e']);
    });

    test('header no: only the first file keeps the header row', () {
      final parts = splitCsv(
        five,
        SplitSpec.fromParams(const {'rowsPerFile': 2, 'header': 'no'}),
      );
      expect(parts, ['Name,N\na,1\nb,2', 'c,3\nd,4', 'e,5']);
      // Concatenated, the files are the source again.
      expect(parts.join('\n'), five);
    });

    test('rowsPerFile < 1 throws', () {
      expect(
        () => splitCsv(five, const SplitSpec(rowsPerFile: 0)),
        throwsA(isA<ToolException>()),
      );
    });
  });

  group('splitPlan', () {
    test('by rows: last file holds the remainder', () {
      expect(splitPlan(2140, const SplitSpec(rowsPerFile: 500)), [
        500,
        500,
        500,
        500,
        140,
      ]);
      expect(splitPlan(400, const SplitSpec(rowsPerFile: 100)), [
        100,
        100,
        100,
        100,
      ]);
    });

    test('by files: even and uneven remainders', () {
      expect(splitPlan(9, const SplitSpec(files: 3)), [3, 3, 3]);
      expect(splitPlan(11, const SplitSpec(files: 3)), [4, 4, 3]);
      expect(splitPlan(3, const SplitSpec(files: 7)), [1, 1, 1]);
    });

    test('an empty table still yields one header-only file', () {
      expect(splitPlan(0, const SplitSpec()), [0]);
      expect(splitPlan(0, const SplitSpec(files: 4)), [0]);
    });

    test('out-of-range params fall back to defaults', () {
      final s = SplitSpec.fromParams(const {
        'rowsPerFile': -3,
        'files': -1,
        'header': 'yes',
      });
      expect((s.rowsPerFile, s.files, s.repeatHeader), (100, 0, true));
    });
  });

  group('split-excel', () {
    test('chunks rows and stays readable as excel', () {
      final bytes = csvToExcel('Name,N\na,1\nb,2\nc,3');
      final parts = splitExcel(bytes, const SplitSpec(rowsPerFile: 2));
      expect(parts, hasLength(2));
      expect(records(excelToCsv(parts[0])).map((m) => m['Name']), ['a', 'b']);
      expect(records(excelToCsv(parts[1])).map((m) => m['Name']), ['c']);
    });

    test('by file count without repeated header', () {
      final bytes = csvToExcel('Name,N\na,1\nb,2\nc,3');
      final parts = splitExcel(
        bytes,
        const SplitSpec(files: 2, repeatHeader: false),
      );
      expect(parts, hasLength(2));
      expect(TableData.parseExcel(parts[0]).headers, ['Name', 'N']);
      // The continuation file starts with data, not the header.
      final second = TableData.parseExcel(parts[1]);
      expect(second.headers, ['c', '3']);
      expect(second.rows, isEmpty);
    });
  });

  group('generic json <-> xml', () {
    test('json object -> xml emits child elements', () {
      final xml = jsonToXml('{"a":"1","b":{"c":"2"}}');
      expect(xml, contains('<a>1</a>'));
      expect(xml, contains('<c>2</c>'));
    });

    test('xml -> json wraps under root element name', () {
      final json = jsonDecode(xmlToJson('<root><a>1</a></root>'));
      expect(json, {
        'root': {'a': '1'},
      });
    });

    test('json array -> xml repeats element, round-trips back to list', () {
      final xml = jsonToXml('{"items":["x","y"]}');
      final json = jsonDecode(xmlToJson(xml)) as Map;
      expect((json['root'] as Map)['items'], ['x', 'y']);
    });

    test('attribute convention @attr / #text', () {
      final json =
          jsonDecode(xmlToJson('<root><p id="7">hi</p></root>')) as Map;
      expect((json['root'] as Map)['p'], {'@id': '7', '#text': 'hi'});
    });

    test('invalid json throws ToolException', () {
      expect(() => jsonToXml('{not json'), throwsA(isA<ToolException>()));
    });
  });
}
