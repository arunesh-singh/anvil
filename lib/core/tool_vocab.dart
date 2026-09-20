/// The lexical vocabulary the agent uses to reach a tool, and the Needle 3
/// trigger regexes derived from it.
///
/// Two consumers, one table on purpose: `agent/tool_shortlist.dart` scores the
/// user's request against [toolSynonyms]/[toolStopWords] to pick candidates,
/// and [needleTriggersFor] inverts the same table into the per-tool `triggers`
/// Needle matches the request against. Splitting them would let the two drift
/// — "make it smaller" would shortlist `pdf/compress` and then fail to route
/// to it.
///
/// Lives in `core/` because `core/fn_schema.dart` emits the triggers as part
/// of the one function schema every backend reads; the layering is
/// core ← engines/tools ← agent/ui, never the reverse.
library;

import 'dart:convert';

import 'package:anvil/core/tool_module.dart';

/// Words that carry no tool signal; they would otherwise score every tool.
const toolStopWords = {
  'the',
  'and',
  'this',
  'that',
  'for',
  'with',
  'from',
  'into',
  'please',
  'can',
  'you',
  'file',
  'make',
  'turn',
  // Generic filler that surfaced unrelated tools on vague asks like
  // "use the tool" (logged: write/* shortlisted for an image request).
  'use',
  'tool',
  'tools',
};

/// Maps common user phrasings onto the vocabulary that actually appears in
/// tool ids/labels, so a request the lexical scorer would miss still surfaces
/// the right tool (missing the tool from the list is the worst failure — the
/// model cannot call what it never saw).
const toolSynonyms = {
  'shrink': ['compress'],
  'smaller': ['compress'],
  'greyscale': ['grayscale'],
  'grayscale': ['grayscale'],
  'bw': ['grayscale'],
  'photo': ['image'],
  'pic': ['image'],
  'picture': ['image'],
  'transcribe': ['audio', 'text'],
  'transcript': ['audio', 'text'],
  'subtitle': ['subtitles'],
  'caption': ['subtitles', 'text'],
  'rotate': ['rotate'],
  'combine': ['merge'],
  'join': ['merge'],
  'write': ['text'],
  'label': ['text'],
  'description': ['text'],
  'describe': ['text'],
  'note': ['text', 'annotate'],
  'place': ['add'],
  'put': ['add'],
  'insert': ['add'],
  'stamp': ['add', 'sign'],
  'find': ['identify'],
  'identify': ['identify'],
  'recognize': ['identify'],
  'recognise': ['identify'],
  'detect': ['identify'],
  'whats': ['identify'],
};

/// Case-insensitive regexes that route a request to [meta]'s tool.
///
/// Needle 3 honours a `triggers` list per declaration and forces a call when
/// one matches. This is decisive, not cosmetic: measured on a 5-tool shortlist
/// and 6 realistic requests, the base model scored 2–3/6 without triggers and
/// 5–6/6 with them ("make this pdf smaller" routed to `pdf_merge` without,
/// `pdf_compress` with).
///
/// Derived from data the registry already carries — the id's words, the
/// shortlist keywords, and the inverse of [toolSynonyms] — so no tool carries
/// hand-written routing. The category name and the accepted extensions are
/// dropped deliberately: a `pdf` trigger on every PDF tool fires them all.
/// Other backends ignore the key.
List<String> needleTriggersFor(ToolMeta meta) {
  final vocab = <String>{
    for (final w in meta.id.split('-'))
      if (w.length >= 3) w,
    ...meta.keywords,
  };
  final words = <String>{...vocab};
  toolSynonyms.forEach((phrase, mapped) {
    if (mapped.any(vocab.contains)) words.add(phrase);
  });
  words.removeAll({meta.category.name, ...meta.acceptedExtensions});
  words.removeWhere((w) => w.length < 2 || toolStopWords.contains(w));
  if (words.isEmpty) return const [];
  final sorted = words.toList()..sort();
  return ['\\b(${sorted.map(RegExp.escape).join('|')})\\b'];
}

/// Needle consumes exactly Anvil's schema shape — `{name, description,
/// parameters, triggers}` — so the tool declarations are the schema list
/// verbatim.
String needleToolsJson(List<Map<String, dynamic>> fnSchemas) =>
    jsonEncode(fnSchemas);
