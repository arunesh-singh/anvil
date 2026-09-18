import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/asr_engine.dart' show AsrSegment;
import 'package:anvil/tools/video/srt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('srtFrom', () {
    test('renders numbered cues with SRT timestamps', () {
      final srt = srtFrom(const [
        AsrSegment(startMs: 0, endMs: 15000, text: 'hello world'),
        AsrSegment(startMs: 15000, endMs: 30500, text: 'second cue'),
      ]);
      expect(srt, contains('1\n00:00:00,000 --> 00:00:15,000\nhello world\n'));
      expect(srt, contains('2\n00:00:15,000 --> 00:00:30,500\nsecond cue\n'));
    });

    test('hour rollover formats correctly', () {
      final srt = srtFrom(const [
        AsrSegment(startMs: 3661001, endMs: 3675999, text: 'x'),
      ]);
      expect(srt, contains('01:01:01,001 --> 01:01:15,999'));
    });

    test('empty segments throw', () {
      expect(() => srtFrom(const []), throwsA(isA<ToolException>()));
    });
  });

  group('extractiveSummary', () {
    test('short text passes through', () {
      const text = 'Only one meaningful sentence here today.';
      expect(extractiveSummary(text), text);
    });

    test('keeps the highest-frequency sentences in original order', () {
      final text = [
        'Rockets need staged combustion to reach orbit efficiently.',
        'My cat sleeps all day on the warm windowsill blanket.',
        'Staged combustion engines burn propellant in a preburner first.',
        'The weather yesterday was mildly disappointing to everyone.',
        'Combustion efficiency decides how much propellant a rocket needs.',
        'Someone mentioned lunch plans in the middle of the show.',
      ].join(' ');
      final summary = extractiveSummary(text, maxSentences: 2);
      expect(summary, contains('combustion'));
      expect(summary, isNot(contains('cat')));
      // Original order preserved when both sentences survive.
      if (summary.contains('Rockets') && summary.contains('Staged')) {
        expect(summary.indexOf('Rockets'), lessThan(summary.indexOf('Staged')));
      }
    });
  });

  group('dedupeFrameTexts', () {
    test('drops blanks and consecutive duplicates, keeps changes', () {
      final out = dedupeFrameTexts(
          ['Slide 1', 'Slide 1', '', 'Slide 2', 'Slide 2', 'Slide 1']);
      expect(out.split('\n\n'), ['Slide 1', 'Slide 2', 'Slide 1']);
    });

    test('all-empty frames throw', () {
      expect(() => dedupeFrameTexts(['', '  ']), throwsA(isA<ToolException>()));
    });
  });
}
