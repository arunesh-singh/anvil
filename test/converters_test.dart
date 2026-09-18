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
    test('rowsPerFile=2 over 5 rows -> 3 files, header repeated', () {
      final parts = splitCsv(five, 2);
      expect(parts, hasLength(3));
      for (final p in parts) {
        expect(p.startsWith('Name,N'), isTrue);
      }
      expect(records(parts[0]).map((m) => m['Name']), ['a', 'b']);
      expect(records(parts[1]).map((m) => m['Name']), ['c', 'd']);
      expect(records(parts[2]).map((m) => m['Name']), ['e']);
    });

    test('rowsPerFile < 1 throws', () {
      expect(() => splitCsv(five, 0), throwsA(isA<ToolException>()));
    });
  });

  group('split-excel', () {
    test('chunks rows and stays readable as excel', () {
      final bytes = csvToExcel('Name,N\na,1\nb,2\nc,3');
      final parts = splitExcel(bytes, 2);
      expect(parts, hasLength(2));
      expect(records(excelToCsv(parts[0])).map((m) => m['Name']), ['a', 'b']);
      expect(records(excelToCsv(parts[1])).map((m) => m['Name']), ['c']);
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
