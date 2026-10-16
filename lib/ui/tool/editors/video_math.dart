/// Pure maths and labels behind the video screens (trim, compress, GIF):
/// clock formatting, size estimates, sample windows, and the compress
/// presets. Kept free of widgets and plugins so it is host-unit-testable
/// (test/video_math_test.dart).
library;

import 'package:anvil/tools/video/ffmpeg_cmd.dart' as cmd;

/// `m:ss` (or `h:mm:ss` from an hour up), truncated to the second — the
/// player's "0:42 / 2:18" pill.
String clock(int ms) {
  final s = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// `m:ss.s`, rounded to the tenth — selection handle labels ("0:38.2").
String clockTenths(int ms) {
  final tenths = ((ms < 0 ? 0 : ms) / 100).round();
  final s = tenths ~/ 10;
  final m = s ~/ 60;
  return '$m:${(s % 60).toString().padLeft(2, '0')}.${tenths % 10}';
}

/// `41.5 s` — a selection length.
String secondsLabel(int ms) => '${(ms / 1000).toStringAsFixed(1)} s';

/// Short size for estimates: one decimal below 10 units, whole above
/// (`6.2 MB`, `58 MB`, `412 MB`).
String compactBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v < 10 ? v.toStringAsFixed(1) : v.round()} ${units[i]}';
}

/// `−86%` (or `+12%` when the result is bigger) from [before] to [after].
String savingsLabel(int before, int after) {
  if (before <= 0) return '';
  final pct = ((after - before) * 100 / before).round();
  return pct <= 0 ? '−${-pct}%' : '+$pct%';
}

/// A stream-copy trim keeps the source bit rate, so its size is the source
/// size scaled by the share of the timeline kept.
int trimEstimateBytes({
  required int sizeBytes,
  required int durationMs,
  required int selectionMs,
}) {
  if (durationMs <= 0) return 0;
  final share = (selectionMs / durationMs).clamp(0.0, 1.0);
  return (sizeBytes * share).round();
}

/// The part of a window to encode as a size sample: at most [maxSampleMs],
/// centred in the window [windowStartMs] … +[windowMs] (the whole
/// [durationMs] when [windowMs] is null). Returns (startMs, lengthMs).
(int, int) sampleWindow({
  required int durationMs,
  required int maxSampleMs,
  int windowStartMs = 0,
  int? windowMs,
}) {
  final start = windowStartMs.clamp(0, durationMs);
  final len = (windowMs ?? durationMs - start).clamp(0, durationMs - start);
  final sample = len < maxSampleMs ? len : maxSampleMs;
  return (start + (len - sample) ~/ 2, sample);
}

/// Scales a measured sample of [sampleMs] to [totalMs].
int extrapolateBytes({
  required int sampleBytes,
  required int sampleMs,
  required int totalMs,
}) {
  if (sampleMs <= 0) return sampleBytes;
  return (sampleBytes * totalMs / sampleMs).round();
}

// ── Compress ────────────────────────────────────────────────────────────────

/// Quality slider bounds on mpeg4 qscale (lower = sharper). 1 and 25–31 add
/// size or artefacts without a visible payoff.
const qualityBest = 2;
const qualityWorst = 24;

/// The named stop a qscale value reads as.
String qualityName(int q) => switch (q) {
  <= 3 => 'High',
  <= 7 => 'Good',
  <= 14 => 'Small',
  _ => 'Smallest',
};

/// Destination presets on the compress screen ("Made for").
enum CompressPreset {
  whatsapp('WhatsApp'),
  email('Email · 25 MB'),
  instagram('Instagram'),
  keep('Keep quality');

  const CompressPreset(this.label);
  final String label;
}

/// Size limit the Email preset aims at.
const emailTargetMb = 25;

/// What a compress run will do. [shortSide] is the target short side
/// ("720p"); 0 keeps the source size. [targetMb] > 0 switches to a target
/// size and [quality] no longer applies.
class CompressSettings {
  const CompressSettings({
    required this.shortSide,
    required this.quality,
    this.targetMb = 0,
  });

  final int shortSide;
  final int quality;
  final int targetMb;

  CompressSettings copyWith({int? shortSide, int? quality, int? targetMb}) =>
      CompressSettings(
        shortSide: shortSide ?? this.shortSide,
        quality: quality ?? this.quality,
        targetMb: targetMb ?? this.targetMb,
      );

  @override
  bool operator ==(Object other) =>
      other is CompressSettings &&
      other.shortSide == shortSide &&
      other.quality == quality &&
      other.targetMb == targetMb;

  @override
  int get hashCode => Object.hash(shortSide, quality, targetMb);
}

/// A preset's settings for a source whose short side is [sourceShortSide]:
/// resolutions at or above the source collapse to "keep the source" (0) —
/// compressing never upscales.
CompressSettings presetSettings(CompressPreset p, int sourceShortSide) {
  int cap(int side) => side >= sourceShortSide ? 0 : side;
  return switch (p) {
    CompressPreset.whatsapp => CompressSettings(
      shortSide: cap(720),
      quality: 6,
    ),
    CompressPreset.email => CompressSettings(
      shortSide: cap(720),
      quality: 6,
      targetMb: emailTargetMb,
    ),
    CompressPreset.instagram => CompressSettings(
      shortSide: cap(1080),
      quality: 4,
    ),
    CompressPreset.keep => const CompressSettings(shortSide: 0, quality: 3),
  };
}

/// The preset [s] matches, if any (manual tweaks deselect the pills).
CompressPreset? presetFor(CompressSettings s, int sourceShortSide) {
  for (final p in CompressPreset.values) {
    if (presetSettings(p, sourceShortSide) == s) return p;
  }
  return null;
}

/// Resolution choices for the segmented control, as short sides: the source
/// itself (0) first, then each standard step below it.
List<int> resolutionOptions(int sourceShortSide) => [
  0,
  for (final side in const [1080, 720, 480])
    if (side < sourceShortSide) side,
];

/// Segment label: `1080p` for a step, the source's own `<n>p` for 0.
String resolutionLabel(int shortSide, int sourceShortSide) =>
    '${shortSide == 0 ? sourceShortSide : shortSide}p';

/// The tool's `height` param for a [shortSide] target on a [width]×[height]
/// (display) source: landscape scales by height directly; portrait sets the
/// width to [shortSide], so the height grows by the aspect (kept even).
/// 0 stays 0 (keep the source size).
int heightParamFor(int shortSide, int width, int height) {
  if (shortSide <= 0 || width <= 0 || height <= 0) return 0;
  if (width >= height) return shortSide;
  final h = (shortSide * height / width).round();
  return h - h % 2;
}

/// Size a target-size encode will land near: the bitrate the tool will ask
/// for (see [cmd.targetVideoBitrate]) plus audio, over [durationMs].
int targetEstimateBytes({
  required int targetMb,
  required int durationMs,
  required bool hasAudio,
}) {
  final audio = hasAudio ? cmd.targetAudioBitsPerSec : 0;
  final video = cmd.targetVideoBitrate(
    targetBytes: targetMb * 1024 * 1024,
    durationMs: durationMs,
    audioBitsPerSec: audio,
  );
  return ((video + audio) * durationMs / 8000).round();
}

// ── GIF ─────────────────────────────────────────────────────────────────────

/// "Smoothness" and "Width" choices on the GIF screen.
const gifFpsOptions = [10, 15, 24];
const gifWidthOptions = [320, 480, 720];

/// Default moment length for a GIF.
const gifDefaultWindowMs = 4000;
