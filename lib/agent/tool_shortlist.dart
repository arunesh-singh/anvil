/// Deterministic lexical pre-filter for the agent's tool list.
///
/// 219 tool declarations cannot go into one prompt, and a 2B-class model
/// degrades badly with a long list (R3). This ranks the registry against the
/// user's request and hands the model a handful of candidates. Pure and
/// host-tested — the same request always produces the same prompt.
library;

import 'package:anvil/core/tool_module.dart';
import 'package:anvil/core/tool_vocab.dart';
import 'package:anvil/ui/widgets/slab.dart' show categoryLabel;

/// Ranks [tools] against a natural-language [request] and returns at most
/// [limit] candidates whose declarations go into the model's tool list.
List<ToolModule> shortlistTools(
  List<ToolModule> tools,
  String request, {
  int limit = 10,
  Set<String> attachmentExts = const {},
}) {
  final tokens = <String>{
    for (final t in request.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
      if (t.length >= 3 && !toolStopWords.contains(t)) t,
  };
  // Expand with vocabulary synonyms (short trigger words like 'bw' are kept
  // even though they fall under the length filter above).
  for (final w in request.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
    final mapped = toolSynonyms[w];
    if (mapped != null) tokens.addAll(mapped);
  }
  if (tokens.isEmpty && attachmentExts.isEmpty) return const [];

  final scored = <(int, ToolModule)>[];
  for (final tool in tools) {
    if (!tool.meta.agentCallable) continue;
    final meta = tool.meta;
    final idWords = meta.id.split('-');
    final label = meta.label.toLowerCase();
    final category = categoryLabel(meta.category).toLowerCase();
    final description = meta.description.toLowerCase();
    var score = 0;
    for (final token in tokens) {
      if (idWords.contains(token)) score += 4;
      if (meta.keywords.contains(token)) score += 4;
      if (label.contains(token)) score += 3;
      if (category.contains(token)) score += 2;
      if (description.contains(token)) score += 1;
      if (meta.acceptedExtensions.contains(token)) score += 2;
    }
    // An attached file's type is a strong signal for tools that accept it
    // (a .pdf attached → surface the PDF tools even on a vague request).
    for (final ext in attachmentExts) {
      if (meta.acceptedExtensions.contains(ext)) score += 3;
    }
    // A file is attached → the user wants to act ON it. Demote zero-input
    // generators (create/from-url/text-to-image) so file-consuming tools rank up.
    if (attachmentExts.isNotEmpty && !meta.requiresInput) score -= 3;
    if (score > 0) scored.add((score, tool));
  }

  scored.sort((a, b) {
    final byScore = b.$1.compareTo(a.$1);
    return byScore != 0
        ? byScore
        : a.$2.meta.qualifiedId.compareTo(b.$2.meta.qualifiedId);
  });
  final matchedCats = {for (final e in scored) e.$2.meta.category};
  final chosen = [for (final e in scored.take(limit)) e.$2];
  if (chosen.length < limit && matchedCats.isNotEmpty) {
    final have = {for (final t in chosen) t.meta.qualifiedId};
    final siblings = [
      for (final t in tools)
        if (t.meta.agentCallable &&
            matchedCats.contains(t.meta.category) &&
            !have.contains(t.meta.qualifiedId))
          t,
    ]..sort((a, b) => a.meta.qualifiedId.compareTo(b.meta.qualifiedId));
    for (final t in siblings) {
      if (chosen.length >= limit) break;
      chosen.add(t);
    }
  }
  return chosen;
}
