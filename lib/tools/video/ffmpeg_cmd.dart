/// Pure-Dart FFmpeg argument-list builders for the video/audio tools.
///
/// No Flutter or plugin imports, so every builder is host-unit-testable
/// (test/video_cmd_test.dart). Execution happens in [FfmpegEngine]; this file
/// only decides WHAT to run.
///
/// Codec policy (ffmpeg_kit LGPL "full" flavor — NO x264/x265, NO AV1 encode):
/// - mp4/mov/mkv/avi video → `mpeg4 -q:v 4` (+ aac audio; avi gets mp3 audio)
/// - webm → `libvpx-vp9 -b:v 0 -crf 33` + libopus audio
/// - audio targets → libmp3lame / pcm_s16le / flac / libvorbis / aac
library;

// ── Codec presets (LGPL-safe) ───────────────────────────────────────────────

const mpeg4Video = ['-c:v', 'mpeg4', '-q:v', '4'];
const vp9Video = ['-c:v', 'libvpx-vp9', '-b:v', '0', '-crf', '33'];
const aacAudio = ['-c:a', 'aac'];
const mp3Audio = ['-c:a', 'libmp3lame', '-q:a', '3'];
const opusAudio = ['-c:a', 'libopus'];

/// (video, audio) track encoder args for a target video container extension.
(List<String>, List<String>) codecsFor(String containerExt) =>
    switch (containerExt) {
      'mp4' || 'mov' || 'mkv' => (mpeg4Video, aacAudio),
      // aac-in-avi is poorly supported; mp3 is the conventional avi track.
      'avi' => (mpeg4Video, mp3Audio),
      'webm' => (vp9Video, opusAudio),
      _ => throw ArgumentError.value(
          containerExt, 'containerExt', 'unsupported video container'),
    };

/// Audio encoder args for a target audio extension.
List<String> audioCodecFor(String ext) => switch (ext) {
      'mp3' => mp3Audio,
      'wav' => const ['-c:a', 'pcm_s16le'],
      'flac' => const ['-c:a', 'flac'],
      'ogg' => const ['-c:a', 'libvorbis', '-q:a', '4'],
      'm4a' => const ['-c:a', 'aac', '-b:a', '192k'],
      // .m4r (iPhone ringtone) is an iPod/MPEG-4 container ffmpeg cannot
      // infer from the extension, hence the explicit muxer.
      'm4r' => const ['-c:a', 'aac', '-b:a', '192k', '-f', 'ipod'],
      _ => throw ArgumentError.value(ext, 'ext', 'unsupported audio target'),
    };

// ── Builders ────────────────────────────────────────────────────────────────

/// Generic re-encode/remux: `-y -i input [videoCodec] [audioCodec] [extra] output`.
List<String> convert(
  String input,
  String output, {
  List<String> videoCodec = const [],
  List<String> audioCodec = const [],
  List<String> extraArgs = const [],
}) =>
    ['-y', '-i', input, ...videoCodec, ...audioCodec, ...extraArgs, output];

/// Container-to-container video conversion using the policy codecs for
/// [targetExt]. [evenDims] rounds odd frame sizes down to even — required by
/// mpeg4/yuv420p and needed for GIF sources, which may have odd dimensions.
List<String> videoConvert(
  String input,
  String output,
  String targetExt, {
  bool evenDims = false,
}) {
  final (video, audio) = codecsFor(targetExt);
  return convert(
    input,
    output,
    videoCodec: video,
    audioCodec: audio,
    extraArgs: evenDims
        ? const ['-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2']
        : const [],
  );
}

/// Audio-only conversion/extraction: drops any video stream (`-vn`) and
/// encodes with the policy codec for [targetExt].
List<String> extractAudio(String input, String output, String targetExt) =>
    ['-y', '-i', input, '-vn', ...audioCodecFor(targetExt), output];

/// Remuxes an AAC-family source (`.aac`/`.m4a`) into an audio-only `.mp4`
/// without re-encoding (aac/alac are valid mp4 payloads).
List<String> audioCopyToMp4(String input, String output) =>
    ['-y', '-i', input, '-vn', '-c:a', 'copy', output];

/// Video → animated GIF in one pass: split the filtered stream, generate an
/// optimized 256-color palette from one branch, apply it to the other.
List<String> toGif(
  String input,
  String output, {
  int fps = 12,
  int width = 480,
}) =>
    [
      '-y',
      '-i', input,
      '-filter_complex',
      '[0:v]fps=$fps,scale=$width:-2:flags=lanczos,split[s0][s1];'
          '[s0]palettegen[p];[s1][p]paletteuse[v]',
      '-map', '[v]',
      output,
    ];

/// Video → animated WebP (libwebp), lossy, infinite loop.
List<String> toAnimatedWebp(
  String input,
  String output, {
  int fps = 12,
  int width = 480,
}) =>
    [
      '-y',
      '-i', input,
      '-vf', 'fps=$fps,scale=$width:-2:flags=lanczos',
      '-c:v', 'libwebp',
      '-lossless', '0',
      '-q:v', '75',
      '-loop', '0',
      '-an',
      output,
    ];

/// Trims [durationSeconds] starting at [startSeconds] with stream copy
/// (no re-encode; cuts land on the nearest keyframe). `-ss` before `-i`
/// uses fast input seeking.
List<String> cut(
  String input,
  String output, {
  required int startSeconds,
  required int durationSeconds,
}) =>
    [
      '-y',
      '-ss', '$startSeconds',
      '-i', input,
      '-t', '$durationSeconds',
      '-c', 'copy',
      output,
    ];

/// Strips the audio track; video stream is copied untouched.
List<String> mute(String input, String output) =>
    ['-y', '-i', input, '-c:v', 'copy', '-an', output];

/// Shrinks a video: downscale to [height] (width auto, kept even) and
/// re-encode at [quality] (mpeg4 `-q:v`, 1 best … 31 smallest). The container
/// is kept, so codecs follow [containerExt]; webm uses the fixed-CRF VP9
/// preset ([quality] does not apply there).
List<String> compress(
  String input,
  String output,
  String containerExt, {
  required int height,
  required int quality,
}) {
  final (_, audio) = codecsFor(containerExt);
  final video = containerExt == 'webm'
      ? vp9Video
      : ['-c:v', 'mpeg4', '-q:v', '$quality'];
  final evenHeight = height - height % 2; // yuv420p needs even dimensions
  return [
    '-y',
    '-i', input,
    '-vf', 'scale=-2:$evenHeight',
    ...video,
    ...audio,
    output,
  ];
}

/// Scales a video to exactly [width]x[height]; audio is copied. The container
/// is kept, so the video codec follows [containerExt].
List<String> resize(
  String input,
  String output,
  String containerExt, {
  required int width,
  required int height,
}) {
  final (video, _) = codecsFor(containerExt);
  return [
    '-y',
    '-i', input,
    '-vf', 'scale=$width:$height',
    ...video,
    '-c:a', 'copy',
    output,
  ];
}

/// Any audio/video → 16 kHz mono PCM16 WAV, the input format the ASR engine
/// (sherpa_onnx Whisper) expects.
List<String> toWav16k(String input, String output) => [
      '-y',
      '-i', input,
      '-vn',
      '-ac', '1',
      '-ar', '16000',
      '-c:a', 'pcm_s16le',
      output,
    ];

/// Samples video frames for OCR: [fps] frames/second, downscaled to
/// [width] px wide (even), written as numbered PNGs into [outPattern]
/// (e.g. `/tmp/frames/%04d.png`).
List<String> extractFrames(
  String input,
  String outPattern, {
  double fps = 0.5,
  int width = 1280,
}) =>
    [
      '-y',
      '-i', input,
      '-vf', 'fps=$fps,scale=$width:-2',
      outPattern,
    ];
