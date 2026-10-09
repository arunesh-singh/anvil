/// Converter tool guides (CSV/JSON/XML/Excel transforms).
library;

import 'package:anvil/core/tool_guide.dart';

/// Converter guides, keyed by qualified tool id.
const converterToolGuides = <String, ToolGuide>{
  'converter/csv-to-json': ToolGuide(
    'Use for: csv to json, comma separated rows as json objects, '
    'export table as json array.',
    keywords: ['comma', 'objects', 'array'],
  ),
  'converter/csv-to-xml': ToolGuide(
    'Use for: csv to xml, comma separated rows as xml, table as xml markup.',
    keywords: ['comma', 'markup'],
  ),
  'converter/csv-to-excel': ToolGuide(
    'Use for: csv to excel, open csv as spreadsheet, save csv as workbook.',
    keywords: ['spreadsheet', 'workbook', 'xlsx', 'sheet'],
  ),
  'converter/xml-to-csv': ToolGuide(
    'Use for: xml to csv, flatten xml table to comma separated rows.',
    keywords: ['comma', 'flatten', 'rows'],
  ),
  'converter/xml-to-excel': ToolGuide(
    'Use for: xml to excel, open xml table as spreadsheet, xml to xlsx.',
    keywords: ['spreadsheet', 'workbook', 'xlsx', 'sheet'],
  ),
  'converter/xml-to-json': ToolGuide(
    'Use for: xml to json, parse xml document into json.',
    keywords: ['parse', 'markup'],
  ),
  'converter/json-to-xml': ToolGuide(
    'Use for: json to xml, serialize json object as xml markup.',
    keywords: ['markup', 'serialize'],
  ),
  'converter/excel-to-csv': ToolGuide(
    'Use for: excel to csv, spreadsheet to comma separated, xlsx to csv. '
    'Converts only the first sheet.',
    keywords: ['spreadsheet', 'workbook', 'comma', 'sheet'],
  ),
  'converter/excel-to-xml': ToolGuide(
    'Use for: excel to xml, spreadsheet to xml, xlsx to xml. '
    'Converts only the first sheet.',
    keywords: ['spreadsheet', 'workbook', 'sheet', 'markup'],
  ),
  'converter/split-csv': ToolGuide(
    'Use for: split csv into parts, break large csv into chunks, '
    'csv by row count. Set `rowsPerFile` from the number of rows per part '
    '(default 100).',
    keywords: ['chunks', 'parts', 'divide', 'rows', 'batches'],
  ),
  'converter/split-excel': ToolGuide(
    'Use for: split excel into parts, break large spreadsheet into chunks, '
    'xlsx by row count. Set `rowsPerFile` from the number of rows per part '
    '(default 100).',
    keywords: ['spreadsheet', 'chunks', 'parts', 'divide', 'rows', 'batches'],
  ),
};
