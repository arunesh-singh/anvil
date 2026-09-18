/// Recall gate for the agent's tool shortlist: the model cannot call a tool it
/// never saw, so every request in this corpus MUST surface its tool inside the
/// six declarations the Ask tab actually ships (`_agentToolLimit`).
///
/// A miss here is a whole class of "the agent doesn't work" reports. Fix it by
/// adding `keywords:` at the tool's own meta, or a query-side entry in
/// `_synonyms` when the word should boost a family; never by lowering the bar.
library;

import 'package:anvil/agent/tool_shortlist.dart';
import 'package:anvil/core/registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// One corpus row: a request as a user would type it, the extensions of what
/// they attached, and the tool(s) that must be offered. Several accepted ids
/// mean the request is genuinely ambiguous and either tool serves the user.
class _Row {
  final String request;
  final Set<String> exts;
  final Set<String> accepted;
  const _Row(this.request, this.exts, this.accepted);
}

const _corpus = <_Row>[
  _Row('make this pdf smaller', {'pdf'}, {'pdf/compress'}),
  _Row('combine these two pdfs into one', {'pdf'}, {'pdf/merge'}),
  _Row('split this pdf into separate pages', {'pdf'}, {'pdf/split'}),
  _Row('password protect this pdf', {'pdf'}, {'pdf/protect'}),
  _Row('remove the password from this pdf', {'pdf'}, {'pdf/unlock'}),
  _Row('add a watermark that says draft', {'pdf'}, {'pdf/watermark'}),
  _Row('rotate the pages of this pdf', {'pdf'}, {'pdf/rotate'}),
  _Row('get the text out of this pdf', {'pdf'}, {'pdf/extract-text'}),
  _Row('turn this pdf table into a spreadsheet', {'pdf'}, {'pdf/to-csv'}),
  _Row('summarize this pdf', {'pdf'}, {'pdf/summarizer'}),
  _Row('delete page 3 from this pdf', {'pdf'}, {'pdf/delete'}),
  _Row('make this photo black and white', {'jpg'}, {'image/grayscale'}),
  _Row('resize this image to 800 pixels wide', {'png'}, {'image/resize'}),
  // "shrink" is ambiguous between fewer bytes and fewer pixels; both leave the
  // user with a smaller photo.
  _Row('shrink this photo', {'jpg'}, {'image/compress', 'image/resize'}),
  _Row('cut out the background', {'png'}, {'image/remove-bg'}),
  _Row('make this picture sharper and bigger', {'jpg'}, {'image/upscale'}),
  _Row('read the text in this screenshot', {'png'}, {'image/to-text'}),
  _Row('what is in this photo', {'jpg'}, {'image/identify'}),
  _Row('pixelate the faces in this picture', {'jpg'}, {'image/pixelate'}),
  _Row('add a border around this photo', {'jpg'}, {'image/border'}),
  _Row('colorize this old photo', {'jpg'}, {'image/colorize-photo'}),
  _Row('turn this video into a gif', {'mp4'}, {'video/to-gif'}),
  _Row('remove the sound from this video', {'mp4'}, {'video/mute'}),
  _Row('extract the audio from this video', {'mp4'}, {'video/extract-audio'}),
  _Row('trim this video', {'mp4'}, {'video/cutter'}),
  _Row('convert this csv to json', {'csv'}, {'converter/csv-to-json'}),
  _Row('turn this excel file into a csv', {'xlsx'}, {'converter/excel-to-csv'}),
  _Row('translate this text to spanish', {}, {'write/translate'}),
  _Row('count the words in this', {}, {'write/word-counter'}),
];

void main() {
  test('every corpus request shortlists its tool in the shipped top 6', () {
    final all = ToolRegistry(buildTools()).all;
    final known = {for (final t in all) t.meta.qualifiedId};
    final misses = <String>[];
    for (final row in _corpus) {
      for (final id in row.accepted) {
        expect(known, contains(id), reason: 'corpus names a missing tool');
      }
      final got = shortlistTools(
        all,
        row.request,
        limit: 6,
        attachmentExts: row.exts,
      ).map((t) => t.meta.qualifiedId).toList();
      if (!got.any(row.accepted.contains)) {
        misses.add(
          '"${row.request}" [${row.exts.join(',')}] '
          'wanted one of ${row.accepted.join('|')}, got ${got.join(', ')}',
        );
      }
    }
    expect(misses, isEmpty, reason: misses.join('\n'));
  });
}
