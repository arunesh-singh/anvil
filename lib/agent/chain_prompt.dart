/// Pure helpers for multi-step tool chains in the Ask tab.
///
/// No Flutter imports so the chain's prompt shaping and shortlist query are
/// host-testable. Each continuation step rebuilds a fresh chat, so the model
/// is re-seeded with the original request plus a log of what already ran.
library;

/// Rough token estimate (~4 chars/token) for keeping the prompt within the KV
/// budget.
int estimateTokens(String s) => (s.length / 4).ceil();

/// Returns the prefix of [blocks] (attached-file content) whose combined
/// estimated tokens fit [budgetTokens]; the first block that would overflow is
/// included truncated with a "\n…[truncated]" marker. Empty when budget <= 0.
List<String> fitTextBlocks(List<String> blocks, int budgetTokens) {
  if (budgetTokens <= 0) return const [];
  final out = <String>[];
  var used = 0;
  for (final b in blocks) {
    final t = estimateTokens(b);
    if (used + t <= budgetTokens) {
      out.add(b);
      used += t;
      continue;
    }
    final remainChars = (budgetTokens - used) * 4;
    if (remainChars > 32) {
      final cut = remainChars.clamp(0, b.length);
      out.add('${b.substring(0, cut)}\n…[truncated]');
    }
    break;
  }
  return out;
}

/// One completed tool step in a chain.
class ChainStep {
  final String toolLabel;
  final String? outputName;
  final String? outputPath;

  /// Qualified id (`<category>/<slug>`) of the tool that produced this step.
  /// Used by the chain loop to detect a single-input tool being re-applied to
  /// its own fresh output — a degenerate no-op loop the 2B model falls into.
  final String? toolId;

  /// Inline text a step produced (OCR, image labels, a translation). Carried
  /// so a following step can use it — e.g. an identified name as a caption.
  final String? resultText;
  const ChainStep({
    required this.toolLabel,
    this.outputName,
    this.outputPath,
    this.toolId,
    this.resultText,
  });
}

/// Prompt seeding a fresh chat to continue a chain: original request + a log of
/// completed steps (with output paths so the model can pass them to the next
/// tool), then instructions to call the next tool or finish with a summary.
String continuationPrompt(String request, List<ChainStep> steps) {
  final b = StringBuffer()
    ..writeln('You are continuing a multi-step task on this device.')
    ..writeln('Original request: $request')
    ..writeln('Steps done so far:');
  for (final s in steps) {
    b.writeln(
      '- ${s.toolLabel}: produced "${s.outputName ?? 'a result'}"'
      '${s.outputPath != null ? ' at ${s.outputPath}' : ''}'
      '${_stepText(s.resultText)}',
    );
  }
  b
    ..writeln(
      'Call the next tool to continue the request, using an output path '
      'above as the input file when a step needs the previous result.',
    )
    ..write(
      'If the request is now fully satisfied, reply with a one-sentence '
      'summary instead of calling a tool.',
    );
  return b.toString();
}

/// Renders a step's inline result text for the continuation log, truncated so
/// a long OCR dump cannot crowd out the rest of the prompt. Empty when absent.
String _stepText(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return '';
  final clipped = t.length <= 300 ? t : '${t.substring(0, 300)}…';
  return '\n  Result text: $clipped';
}

/// Shortlist query for a continuation step: the original request plus the labels
/// of completed steps, nudging ranking toward what remains.
String chainShortlistQuery(String request, List<ChainStep> steps) =>
    steps.isEmpty
    ? request
    : '$request ${[for (final s in steps) s.toolLabel].join(' ')}';
