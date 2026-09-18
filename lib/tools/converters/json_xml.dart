import 'dart:convert';

import 'package:xml/xml.dart';

import 'package:anvil/core/tool_io.dart';

/// Generic (non-tabular) JSON ↔ XML conversion for arbitrary trees.
///
/// Convention (Badgerfish-lite):
/// - object key `@name` → attribute, `#text` → element text;
/// - any other key → child element; a list value repeats that element;
/// - a top-level array or list value uses `<item>` element per entry.

String jsonToXml(String json) {
  final dynamic data;
  try {
    data = jsonDecode(json);
  } on FormatException {
    throw const ToolException('The file is not valid JSON.');
  }
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element('root', nest: () => _writeChildren(builder, data));
  return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
}

void _writeNamed(XmlBuilder b, String name, Object? value) {
  if (value is List) {
    for (final e in value) {
      _writeNamed(b, name, e);
    }
    return;
  }
  b.element(name, nest: () => _writeChildren(b, value));
}

void _writeChildren(XmlBuilder b, Object? value) {
  switch (value) {
    case Map():
      for (final entry in value.entries) {
        final k = entry.key;
        if (k is String && k.startsWith('@')) {
          b.attribute(k.substring(1), entry.value?.toString() ?? '');
        }
      }
      for (final entry in value.entries) {
        final k = entry.key;
        if (k is String && k.startsWith('@')) continue;
        if (k == '#text') {
          b.text(entry.value?.toString() ?? '');
          continue;
        }
        _writeNamed(b, k.toString(), entry.value);
      }
    case List():
      for (final e in value) {
        _writeNamed(b, 'item', e);
      }
    case null:
      break;
    default:
      b.text(value.toString());
  }
}

String xmlToJson(String xml) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException {
    throw const ToolException('The XML file is not well-formed.');
  }
  final root = doc.rootElement;
  final result = {root.localName: _elementToJson(root)};
  return const JsonEncoder.withIndent('  ').convert(result);
}

Object? _elementToJson(XmlElement el) {
  final map = <String, Object?>{};
  for (final a in el.attributes) {
    map['@${a.localName}'] = a.value;
  }
  final children = el.childElements.toList();
  if (children.isEmpty) {
    final text = el.innerText;
    if (map.isEmpty) return text; // pure scalar element
    if (text.trim().isNotEmpty) map['#text'] = text;
    return map;
  }
  for (final c in children) {
    final key = c.localName;
    final val = _elementToJson(c);
    final existing = map[key];
    if (existing == null && !map.containsKey(key)) {
      map[key] = val;
    } else if (existing is List) {
      existing.add(val);
    } else {
      map[key] = [existing, val];
    }
  }
  return map;
}
