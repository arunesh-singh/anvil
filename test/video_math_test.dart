import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/engines/ffmpeg_engine.dart';
import 'package:anvil/ui/tool/editors/video_math.dart';
import 'package:anvil/ui/tool/editors/video_stage.dart';

void main() {
  group('clock labels', () {
    test('clock is m:ss, h:mm:ss from an hour, never negative', () {
      expect(clock(0), '0:00');
      expect(clock(42999), '0:42');
      expect(clock(138000), '2:18');
      expect(clock(3723000), '1:02:03');
      expect(clock(-5), '0:00');
    });

    test('clockTenths rounds to the tenth and carries into the minute', () {
      expect(clockTenths(38200), '0:38.2');
      expect(clockTenths(79740), '1:19.7');
      expect(clockTenths(59960), '1:00.0');
    });

    test('secondsLabel', () => expect(secondsLabel(41500), '41.5 s'));

    test('compactBytes: one decimal under 10, whole above', () {
      expect(compactBytes(6.2 * 1048576 ~/ 1), '6.2 MB');
      expect(compactBytes(58 * 1048576), '58 MB');
      expect(compactBytes(412 * 1048576), '412 MB');
      expect(compactBytes(500), '500 B');
    });

    test('savingsLabel', () {
      expect(savingsLabel(412, 58), '−86%');
      expect(savingsLabel(100, 112), '+12%');
      expect(savingsLabel(0, 5), '');
    });
  });

  group('estimates', () {
    test('trim size scales the source by the kept share', () {
      // 412 MB over 2:18, keep 41.5 s → ~124 MB.
      final est = trimEstimateBytes(
        sizeBytes: 412 * 1048576,
        durationMs: 138000,
        selectionMs: 41500,
      );
      expect(est, (412 * 1048576 * 41500 / 138000).round());
      expect(
        trimEstimateBytes(sizeBytes: 100, durationMs: 0, selectionMs: 5),
        0,
      );
      expect(
        trimEstimateBytes(sizeBytes: 100, durationMs: 10, selectionMs: 20),
        100,
      );
    });

    test('sampleWindow centres the sample in the window', () {
      expect(sampleWindow(durationMs: 138000, maxSampleMs: 2000), (
        68000,
        2000,
      ));
      expect(
        sampleWindow(
          durationMs: 138000,
          maxSampleMs: 1500,
          windowStartMs: 72000,
          windowMs: 4000,
        ),
        (73250, 1500),
      );
      // Window shorter than the sample: encode all of it.
      expect(sampleWindow(durationMs: 1200, maxSampleMs: 2000), (0, 1200));
      // Window running past the end is clipped to the video.
      expect(
        sampleWindow(
          durationMs: 5000,
          maxSampleMs: 2000,
          windowStartMs: 4000,
          windowMs: 4000,
        ),
        (4000, 1000),
      );
    });

    test('extrapolateBytes scales the sample to the total', () {
      expect(
        extrapolateBytes(sampleBytes: 850000, sampleMs: 2000, totalMs: 138000),
        58650000,
      );
      expect(extrapolateBytes(sampleBytes: 10, sampleMs: 0, totalMs: 100), 10);
    });

    test('target-size estimate lands just under the target', () {
      final est = targetEstimateBytes(
        targetMb: 25,
        durationMs: 138000,
        hasAudio: true,
      );
      expect(est, lessThanOrEqualTo(25 * 1048576));
      expect(est, greaterThan(23 * 1048576));
    });
  });

  group('compress presets', () {
    test('presets map to (short side, quality, targetMb)', () {
      expect(
        presetSettings(CompressPreset.whatsapp, 1080),
        const CompressSettings(shortSide: 720, quality: 6),
      );
      expect(
        presetSettings(CompressPreset.email, 1080),
        const CompressSettings(shortSide: 720, quality: 6, targetMb: 25),
      );
      expect(
        presetSettings(CompressPreset.instagram, 2160),
        const CompressSettings(shortSide: 1080, quality: 4),
      );
      expect(
        presetSettings(CompressPreset.keep, 1080),
        const CompressSettings(shortSide: 0, quality: 3),
      );
    });

    test('presets never upscale a small source', () {
      expect(presetSettings(CompressPreset.instagram, 1080).shortSide, 0);
      expect(presetSettings(CompressPreset.whatsapp, 480).shortSide, 0);
    });

    test('presetFor recognises a preset and drops it after a tweak', () {
      final s = presetSettings(CompressPreset.email, 1080);
      expect(presetFor(s, 1080), CompressPreset.email);
      expect(presetFor(s.copyWith(quality: 9, targetMb: 0), 1080), isNull);
    });

    test('resolution options: source first, only smaller steps', () {
      expect(resolutionOptions(1080), [0, 720, 480]);
      expect(resolutionOptions(2160), [0, 1080, 720, 480]);
      expect(resolutionOptions(360), [0]);
      expect(resolutionLabel(0, 1080), '1080p');
      expect(resolutionLabel(720, 1080), '720p');
    });

    test('heightParamFor treats "720p" as the short side', () {
      expect(heightParamFor(720, 1920, 1080), 720);
      expect(heightParamFor(720, 1080, 1920), 1280);
      expect(heightParamFor(480, 1081, 1920), 852); // kept even
      expect(heightParamFor(0, 1920, 1080), 0);
    });

    test('qualityName stops', () {
      expect(qualityName(2), 'High');
      expect(qualityName(6), 'Good');
      expect(qualityName(12), 'Small');
      expect(qualityName(24), 'Smallest');
    });
  });

  group('VideoProbe.fromFfprobe', () {
    test('reads duration, size, bitrate and audio', () {
      final p = VideoProbe.fromFfprobe(
        {'duration': '138.04', 'size': '432013312', 'bit_rate': '25036000'},
        [
          {'codec_type': 'video', 'width': 1920, 'height': 1080},
          {'codec_type': 'audio'},
        ],
      );
      expect(p.durationMs, 138040);
      expect((p.width, p.height), (1920, 1080));
      expect(p.sizeBytes, 432013312);
      expect(p.bitRate, 25036000);
      expect(p.hasAudio, isTrue);
      expect(p.shortSide, 1080);
    });

    test('rotated phone clips report the display size', () {
      final legacy = VideoProbe.fromFfprobe(
        {'duration': '5'},
        [
          {
            'codec_type': 'video',
            'width': 1920,
            'height': 1080,
            'tags': {'rotate': '90'},
          },
        ],
        fileBytes: 77,
      );
      expect((legacy.width, legacy.height), (1080, 1920));
      expect(legacy.sizeBytes, 77);
      expect(legacy.hasAudio, isFalse);
      final matrix = VideoProbe.fromFfprobe(
        {'duration': '5'},
        [
          {
            'codec_type': 'video',
            'width': 1920,
            'height': 1080,
            'side_data_list': [
              {'side_data_type': 'Display Matrix', 'rotation': -90},
            ],
          },
        ],
      );
      expect((matrix.width, matrix.height), (1080, 1920));
    });
  });

  group('SizeEstimator', () {
    test('a newer request supersedes a slow one', () async {
      final e = SizeEstimator(delay: Duration.zero);
      e.request((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return 1;
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
      e.request((_) async => 2);
      expect(e.busy, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(e.value, 2);
      expect(e.busy, isFalse);
      e.dispose();
    });

    test('set() overrides a pending measurement', () async {
      final e = SizeEstimator(delay: const Duration(milliseconds: 10));
      e.request((_) async => 1);
      e.set(42);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(e.value, 42);
      e.dispose();
    });
  });
}
