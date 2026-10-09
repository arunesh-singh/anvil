/// Contract for `lib/core/guides/`: the authoring rules in `tool_guide.dart`
/// are only advice unless something enforces them. A guide keyed by a typo'd
/// id is silently dead (`guideFor` returns null), and a `Not for:` pointing at
/// a non-existent function sends a 2B model to a tool it cannot call.
library;

import 'package:anvil/core/fn_schema.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_guide.dart';
import 'package:anvil/core/tool_vocab.dart';
import 'package:flutter_test/flutter_test.dart';

final _keyword = RegExp(r'^[a-z0-9]{2,}$');
final _notFor = RegExp(r'Not for: [^.]*? - use ([a-z0-9_]+)');

void main() {
  final tools = ToolRegistry(buildTools()).all;
  final byId = {for (final t in tools) t.meta.qualifiedId: t};
  final fnNames = {for (final t in tools) fnNameFor(t.meta)};

  test('every guide is keyed by a registered tool', () {
    final orphans = toolGuides.keys.where((k) => !byId.containsKey(k));
    expect(orphans, isEmpty);
  });

  test('every agent-callable tool has a guide', () {
    final missing = [
      for (final t in tools)
        if (t.meta.agentCallable && guideFor(t.meta.qualifiedId) == null)
          t.meta.qualifiedId,
    ];
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('hints follow H1 and H3', () {
    final bad = <String>[];
    for (final MapEntry(:key, :value) in toolGuides.entries) {
      final h = value.hint;
      if (!h.startsWith('Use for: ')) bad.add('$key: must start "Use for: "');
      if (h.length > 220) bad.add('$key: ${h.length} chars > 220');
      for (final m in _notFor.allMatches(h)) {
        if (!fnNames.contains(m[1])) bad.add('$key: Not for names ${m[1]}');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('keywords follow K1-K3', () {
    final bad = <String>[];
    for (final MapEntry(:key, :value) in toolGuides.entries) {
      final meta = byId[key]?.meta;
      if (meta == null) continue;
      if (value.keywords.length > 8) bad.add('$key: > 8 keywords');
      final idWords = meta.id.split('-').toSet();
      for (final k in value.keywords) {
        if (!_keyword.hasMatch(k)) bad.add('$key: "$k" is not [a-z0-9]{2,}');
        if (toolStopWords.contains(k)) bad.add('$key: "$k" is a stop word');
        if (k == meta.category.name) bad.add('$key: "$k" is the category');
        if (meta.acceptedExtensions.contains(k)) {
          bad.add('$key: "$k" is an accepted extension');
        }
        if (idWords.contains(k)) bad.add('$key: "$k" is already an id word');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
