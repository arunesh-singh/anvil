/// Pure text helpers for the ASR/OCR video tools: SRT subtitle rendering,
/// frequency-based extractive summarization, and frame-OCR de-duplication.
/// No Flutter/plugin imports — host-unit-testable (test/srt_test.dart).
library;

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/asr_engine.dart' show AsrSegment;

String _ts(int ms) {
  final h = ms ~/ 3600000;
  final m = (ms ~/ 60000) % 60;
  final s = (ms ~/ 1000) % 60;
  final f = ms % 1000;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)},${f.toString().padLeft(3, '0')}';
}

/// Renders segments as an SRT document (1-based cues, CRLF-free).
String srtFrom(List<AsrSegment> segments) {
  if (segments.isEmpty) {
    throw const ToolException('No speech found to subtitle.');
  }
  final b = StringBuffer();
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    b
      ..writeln(i + 1)
      ..writeln('${_ts(s.startMs)} --> ${_ts(s.endMs)}')
      ..writeln(s.text.trim())
      ..writeln();
  }
  return b.toString();
}

final _sentenceEnd = RegExp(r'(?<=[.!?])\s+');
final _word = RegExp(r"[a-zA-Z']{3,}");
const _stopWords = {
  'the', 'and', 'that', 'this', 'with', 'for', 'was', 'are', 'but', 'not',
  'you', 'your', 'have', 'has', 'had', 'they', 'them', 'their', 'from',
  'were', 'been', 'being', 'what', 'when', 'where', 'which', 'who', 'how',
  'all', 'can', 'could', 'would', 'should', 'there', 'here', 'about', 'into',
  'than', 'then', 'out', 'just', 'like', 'get', 'got', 'one', 'two', 'also',
  'because', 'over', 'very', 'really', 'going', 'know', 'think', 'well',
  'yeah', 'okay', 'right', 'dont', "don't", 'its', "it's", 'thats', "that's",
};

/// Frequency-based extractive summary: scores sentences by their content-word
/// frequencies and returns the top [maxSentences] in original order.
/// Deterministic — no model. (Phase 3 upgrades podcasts to Gemma.)
String extractiveSummary(String text, {int maxSentences = 5}) {
  final sentences = text
      .split(_sentenceEnd)
      .map((s) => s.trim())
      .where((s) => s.length > 20)
      .toList();
  if (sentences.length <= maxSentences) return sentences.join(' ');

  final freq = <String, int>{};
  for (final m in _word.allMatches(text.toLowerCase())) {
    final w = m.group(0)!;
    if (!_stopWords.contains(w)) {
      freq[w] = (freq[w] ?? 0) + 1;
    }
  }
  final scored = <(int, double)>[];
  for (var i = 0; i < sentences.length; i++) {
    var score = 0.0;
    var words = 0;
    for (final m in _word.allMatches(sentences[i].toLowerCase())) {
      score += (freq[m.group(0)!] ?? 0).toDouble();
      words++;
    }
    scored.add((i, words == 0 ? 0 : score / words));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  final keep = (scored.take(maxSentences).map((e) => e.$1).toList())..sort();
  return [for (final i in keep) sentences[i]].join(' ');
}

/// Merges per-frame OCR outputs: drops empty frames and consecutive
/// duplicates (a still slide OCRs identically across many frames).
String dedupeFrameTexts(List<String> frames) {
  final out = <String>[];
  for (final frame in frames) {
    final t = frame.trim();
    if (t.isEmpty) continue;
    if (out.isNotEmpty && out.last == t) continue;
    out.add(t);
  }
  if (out.isEmpty) {
    throw const ToolException('No readable text found in the video frames.');
  }
  return out.join('\n\n');
}
