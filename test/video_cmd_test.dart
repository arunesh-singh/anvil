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
      expect(cmd.audioCodecFor('m4r'), [
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        '-f',
        'ipod',
      ]);
    });
  });

  group('builders', () {
    test('extractAudio drops video and encodes the target', () {
      expect(cmd.extractAudio('in.mp4', 'out.mp3', 'mp3'), [
        '-y',
        '-i',
        'in.mp4',
        '-vn',
        '-c:a',
        'libmp3lame',
        '-q:a',
        '3',
        'out.mp3',
      ]);
    });

    test('audioCopyToMp4 remuxes without re-encoding', () {
      expect(cmd.audioCopyToMp4('in.m4a', 'out.mp4'), [
        '-y',
        '-i',
        'in.m4a',
        '-vn',
        '-c:a',
        'copy',
        'out.mp4',
      ]);
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
    test('toGif without a window keeps today\'s args', () {
      expect(cmd.toGif('in.mp4', 'out.gif'), [
        '-y',
        '-i',
        'in.mp4',
        '-filter_complex',
        '[0:v]fps=12,scale=480:-2:flags=lanczos,split[s0][s1];'
            '[s0]palettegen[p];[s1][p]paletteuse[v]',
        '-map',
        '[v]',
        'out.gif',
      ]);
    });

    test('toGif window seeks and limits before the input', () {
      final args = cmd.toGif('in.mp4', 'out.gif', start: 72, duration: 4.25);
      expect(args.sublist(0, 7), [
        '-y',
        '-ss',
        '72',
        '-t',
        '4.250',
        '-i',
        'in.mp4',
      ]);
    });

    test('toGif with only a start reads to the end', () {
      final args = cmd.toGif('in.mp4', 'out.gif', start: 3.5);
      expect(args.sublist(0, 5), ['-y', '-ss', '3.500', '-i', 'in.mp4']);
      expect(args, isNot(contains('-t')));
    });

    test('toAnimatedWebp honours the window and keeps its codec args', () {
      expect(cmd.toAnimatedWebp('in.mp4', 'out.webp'), [
        '-y',
        '-i',
        'in.mp4',
        '-vf',
        'fps=12,scale=480:-2:flags=lanczos',
        '-c:v',
        'libwebp',
        '-lossless',
        '0',
        '-q:v',
        '75',
        '-loop',
        '0',
        '-an',
        'out.webp',
      ]);
      final args = cmd.toAnimatedWebp(
        'in.mp4',
        'out.webp',
        fps: 15,
        width: 320,
        start: 1,
        duration: 2,
      );
      expect(args.sublist(0, 7), ['-y', '-ss', '1', '-t', '2', '-i', 'in.mp4']);
      expect(args, contains('fps=15,scale=320:-2:flags=lanczos'));
    });

    test('cut seeks before input and stream-copies', () {
      final args = cmd.cut(
        'in.mp4',
        'out.mp4',
        startSeconds: 5,
        durationSeconds: 10,
      );
      // Whole seconds keep today's exact arg list (agent calls).
      expect(args, [
        '-y',
        '-ss',
        '5',
        '-i',
        'in.mp4',
        '-t',
        '10',
        '-c',
        'copy',
        'out.mp4',
      ]);
    });

    test('cut keeps fractional seconds to the millisecond', () {
      final args = cmd.cut(
        'in.mp4',
        'out.mp4',
        startSeconds: 38.2,
        durationSeconds: 41.5,
      );
      expect(args, containsAllInOrder(['-ss', '38.200', '-i', 'in.mp4']));
      expect(args, containsAllInOrder(['-t', '41.500']));
      expect(args, isNot(contains('-an')));
    });

    test('cut with mute drops the audio track', () {
      final args = cmd.cut(
        'in.mp4',
        'out.mp4',
        startSeconds: 1,
        durationSeconds: 2,
        mute: true,
      );
      expect(args, containsAllInOrder(['-c', 'copy', '-an', 'out.mp4']));
    });

    test('formatSeconds: integers bare, fractions to 3 places', () {
      expect(cmd.formatSeconds(0), '0');
      expect(cmd.formatSeconds(12.0), '12');
      expect(cmd.formatSeconds(0.1), '0.100');
      expect(cmd.formatSeconds(41.25), '41.250');
    });

    test('mute copies video and drops audio', () {
      expect(cmd.mute('in.mp4', 'out.mp4'), [
        '-y',
        '-i',
        'in.mp4',
        '-c:v',
        'copy',
        '-an',
        'out.mp4',
      ]);
    });

    test('compress downscales to even height and keeps container codecs', () {
      final args = cmd.compress(
        'in.mp4',
        'out.mp4',
        'mp4',
        height: 719,
        quality: 8,
      );
      final vf = args[args.indexOf('-vf') + 1];
      expect(vf, contains('718')); // odd heights round down to even
      expect(args, containsAllInOrder(['-c:v', 'mpeg4', '-q:v', '8']));
    });

    test('compress with defaults keeps today\'s args', () {
      expect(
        cmd.compress('in.mp4', 'out.mp4', 'mp4', height: 720, quality: 6),
        [
          '-y',
          '-i',
          'in.mp4',
          '-vf',
          'scale=-2:720',
          '-c:v',
          'mpeg4',
          '-q:v',
          '6',
          '-c:a',
          'aac',
          'out.mp4',
        ],
      );
    });

    test('compress height 0 keeps the source size (even)', () {
      final args = cmd.compress(
        'in.mp4',
        'out.mp4',
        'mp4',
        height: 0,
        quality: 6,
      );
      expect(
        args[args.indexOf('-vf') + 1],
        'scale=trunc(iw/2)*2:trunc(ih/2)*2',
      );
    });

    test('compress with a target bitrate replaces qscale and pins audio', () {
      final mp4 = cmd.compress(
        'in.mp4',
        'out.mp4',
        'mp4',
        height: 720,
        quality: 6,
        videoBitsPerSec: 1200000,
      );
      expect(mp4, containsAllInOrder(['-c:v', 'mpeg4', '-b:v', '1200000']));
      expect(mp4, isNot(contains('-q:v')));
      expect(mp4, containsAllInOrder(['-c:a', 'aac', '-b:a', '128000']));
      final avi = cmd.compress(
        'in.avi',
        'out.avi',
        'avi',
        height: 720,
        quality: 6,
        videoBitsPerSec: 1200000,
      );
      expect(avi, containsAllInOrder(['-c:a', 'libmp3lame', '-b:a', '128000']));
      expect(avi, isNot(contains('-q:a')));
      final webm = cmd.compress(
        'in.webm',
        'out.webm',
        'webm',
        height: 720,
        quality: 6,
        videoBitsPerSec: 1200000,
      );
      expect(
        webm,
        containsAllInOrder(['-c:v', 'libvpx-vp9', '-b:v', '1200000']),
      );
      expect(webm, isNot(contains('-crf')));
    });

    test('compress webm without a target keeps the VP9 CRF preset', () {
      final args = cmd.compress(
        'in.webm',
        'out.webm',
        'webm',
        height: 480,
        quality: 20,
      );
      expect(args, containsAllInOrder(cmd.vp9Video));
    });

    test('compress sample window goes before the input', () {
      final args = cmd.compress(
        'in.mp4',
        'o.mp4',
        'mp4',
        height: 480,
        quality: 8,
        start: 60,
        duration: 2,
      );
      expect(args.sublist(0, 7), [
        '-y',
        '-ss',
        '60',
        '-t',
        '2',
        '-i',
        'in.mp4',
      ]);
    });

    test('targetVideoBitrate spends 95% of the budget minus audio', () {
      // 25 MiB over 100 s: 25*1048576*8*0.95/100 = 1992294 b/s total.
      expect(
        cmd.targetVideoBitrate(targetBytes: 25 * 1048576, durationMs: 100000),
        1992294 - 128000,
      );
      expect(
        cmd.targetVideoBitrate(
          targetBytes: 25 * 1048576,
          durationMs: 100000,
          audioBitsPerSec: 0,
        ),
        1992294,
      );
    });

    test('targetVideoBitrate floors long clips at a watchable rate', () {
      expect(
        cmd.targetVideoBitrate(targetBytes: 1048576, durationMs: 3600000),
        cmd.minVideoBitsPerSec,
      );
      expect(
        cmd.targetVideoBitrate(targetBytes: 1, durationMs: 0),
        cmd.minVideoBitsPerSec,
      );
    });

    test('thumbnailAt fast-seeks one small frame', () {
      expect(cmd.thumbnailAt('in.mp4', 't.jpg', seconds: 7.5, width: 160), [
        '-y',
        '-ss',
        '7.500',
        '-i',
        'in.mp4',
        '-frames:v',
        '1',
        '-vf',
        'scale=160:-2',
        '-q:v',
        '5',
        't.jpg',
      ]);
    });

    test('thumbnailTimes centres each tile in its slice', () {
      expect(cmd.thumbnailTimes(9000, 3), [1.5, 4.5, 7.5]);
    });

    test('videoConvert from gif forces even dimensions', () {
      final args = cmd.videoConvert('in.gif', 'out.mov', 'mov', evenDims: true);
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('trunc'));
    });
  });
}
