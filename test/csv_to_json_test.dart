import 'dart:convert';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/tools/converters/converter_tools.dart';
import 'package:flutter_test/flutter_test.dart';

List<dynamic> decode(String csv) => jsonDecode(csvToJson(csv)) as List;

void main() {
  test('basic rows, values kept as strings', () {
    final out = decode('Name,Age\nAlice,30\nBob,25');
    expect(out, [
      {'Name': 'Alice', 'Age': '30'},
      {'Name': 'Bob', 'Age': '25'},
    ]);
    // Assert strings, not numbers (shouldParseNumbers/dynamicTyping == false).
    expect((out.first as Map)['Age'], isA<String>());
  });

  test('quoted field with embedded comma', () {
    final out = decode('a,b\n"x,y",z');
    expect(out.first, {'a': 'x,y', 'b': 'z'});
  });

  test('ragged short row pads missing cells with null', () {
    final out = decode('a,b,c\n1,2');
    expect(out.first, {'a': '1', 'b': '2', 'c': null});
  });

  test('CRLF parses identically to LF', () {
    expect(
      decode('Name,Age\r\nAlice,30\r\nBob,25'),
      decode('Name,Age\nAlice,30\nBob,25'),
    );
  });

  test('empty input throws ToolException', () {
    expect(
      () => csvToJson(''),
      throwsA(
        isA<ToolException>().having(
          (e) => e.message,
          'message',
          'The CSV file is empty.',
        ),
      ),
    );
  });

  test('blank-lines-only input throws ToolException', () {
    expect(() => csvToJson('\n\n'), throwsA(isA<ToolException>()));
  });
}
