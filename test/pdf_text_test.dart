import 'package:anvil/core/tool_io.dart';
import 'package:anvil/tools/pdf/pdf_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePageList', () {
    test('singles and ranges become sorted 0-based indices', () {
      expect(parsePageList('2,4-6,9', 10), [1, 3, 4, 5, 8]);
    });

    test('duplicates and overlaps collapse', () {
      expect(parsePageList('1,1,2-3,3', 5), [0, 1, 2]);
    });

    test('out-of-range page names the bound', () {
      expect(
        () => parsePageList('7', 5),
        throwsA(isA<ToolException>()
            .having((e) => e.message, 'message', contains('5 pages'))),
      );
    });

    test('garbage tokens throw', () {
      expect(() => parsePageList('a-b', 5), throwsA(isA<ToolException>()));
      expect(() => parsePageList('3-1', 5), throwsA(isA<ToolException>()));
      expect(() => parsePageList('', 5), throwsA(isA<ToolException>()));
    });
  });

  group('pdfTextToCsv', () {
    test('splits columns on wide gaps and tabs, pads ragged rows', () {
      final csv = pdfTextToCsv('Name   Age  City\nAlice\t30\nBob   25  Berlin');
      expect(csv.split('\n'), [
        'Name,Age,City',
        'Alice,30,',
        'Bob,25,Berlin',
      ]);
    });

    test('single spaces stay inside a cell', () {
      expect(pdfTextToCsv('New York   9000000'), 'New York,9000000');
    });

    test('cells containing commas are quoted', () {
      expect(pdfTextToCsv('a,b   c'), '"a,b",c');
    });

    test('blank text throws', () {
      expect(() => pdfTextToCsv('  \n \n'), throwsA(isA<ToolException>()));
    });
  });
}
