import 'package:anvil/tools/video/ffmpeg_cmd.dart' as cmd;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('codec policy (LGPL full flavor — no x264/x265/AV1)', () {
    test('mp4/mov/mkv use mpeg4 + aac; avi uses mp3 audio', () {
      for (final ext in ['mp4', 'mov', 'mkv']) {
        final (v, a) = cmd.codecsFor(ext);
        expect(v, ['-c:v', 'mpeg4', '-q:v', '4']);
        expect(a, ['-c:a', 'aac']);
      }
      final (v, a) = cmd.codecsFor('avi');
      expect(v, ['-c:v', 'mpeg4', '-q:v', '4']);
      expect(a, ['-c:a', 'libmp3lame', '-q:a', '3']);
    });

    test('webm uses vp9 + opus', () {
      final (v, a) = cmd.codecsFor('webm');
      expect(v, ['-c:v', 'libvpx-vp9', '-b:v', '0', '-crf', '33']);
      expect(a, ['-c:a', 'libopus']);
    });

    test('unknown container throws', () {
      expect(() => cmd.codecsFor('wmv'), throwsArgumentError);
    });

    test('audio targets map to LGPL-safe encoders', () {
      expect(cmd.audioCodecFor('mp3'), ['-c:a', 'libmp3lame', '-q:a', '3']);
      expect(cmd.audioCodecFor('wav'), ['-c:a', 'pcm_s16le']);
      expect(cmd.audioCodecFor('flac'), ['-c:a', 'flac']);
      expect(cmd.audioCodecFor('ogg'), ['-c:a', 'libvorbis', '-q:a', '4']);
      expect(cmd.audioCodecFor('m4a'), ['-c:a', 'aac', '-b:a', '192k']);
      // m4r needs the explicit ipod muxer.
      expect(cmd.audioCodecFor('m4r'),
          ['-c:a', 'aac', '-b:a', '192k', '-f', 'ipod']);
    });
  });

  group('builders', () {
    test('extractAudio drops video and encodes the target', () {
      expect(cmd.extractAudio('in.mp4', 'out.mp3', 'mp3'), [
        '-y', '-i', 'in.mp4', '-vn', '-c:a', 'libmp3lame', '-q:a', '3',
        'out.mp3',
      ]);
    });

    test('audioCopyToMp4 remuxes without re-encoding', () {
      expect(cmd.audioCopyToMp4('in.m4a', 'out.mp4'),
          ['-y', '-i', 'in.m4a', '-vn', '-c:a', 'copy', 'out.mp4']);
    });

    test('toGif builds the single-pass palettegen filter', () {
      final args = cmd.toGif('in.mp4', 'out.gif', fps: 10, width: 320);
      expect(args.first, '-y');
      expect(args.last, 'out.gif');
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('fps=10'));
      expect(filter, contains('scale=320:-2'));
      expect(filter, contains('palettegen'));
      expect(filter, contains('paletteuse'));
    });
    test('cut seeks before input and stream-copies', () {
      final args =
          cmd.cut('in.mp4', 'out.mp4', startSeconds: 5, durationSeconds: 10);
      expect(args.indexOf('-ss'), lessThan(args.indexOf('-i')));
      expect(args, containsAllInOrder(['-ss', '5', '-i', 'in.mp4']));
      expect(args, containsAllInOrder(['-t', '10']));
      expect(args, containsAllInOrder(['-c', 'copy']));
    });

    test('mute copies video and drops audio', () {
      expect(cmd.mute('in.mp4', 'out.mp4'),
          ['-y', '-i', 'in.mp4', '-c:v', 'copy', '-an', 'out.mp4']);
    });

    test('compress downscales to even height and keeps container codecs', () {
      final args =
          cmd.compress('in.mp4', 'out.mp4', 'mp4', height: 719, quality: 8);
      final vf = args[args.indexOf('-vf') + 1];
      expect(vf, contains('718')); // odd heights round down to even
      expect(args, containsAllInOrder(['-c:v', 'mpeg4', '-q:v', '8']));
    });

    test('videoConvert from gif forces even dimensions', () {
      final args = cmd.videoConvert('in.gif', 'out.mov', 'mov', evenDims: true);
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('trunc'));
    });
  });
}
