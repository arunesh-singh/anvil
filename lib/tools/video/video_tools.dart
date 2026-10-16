/// Video/audio tools backed by the FFmpeg engine. Command arg-lists come from
/// the pure builders in `ffmpeg_cmd.dart`; this file only wires slugs, params,
/// and file plumbing. The single registration list for this category.
library;

import 'dart:async';

import 'package:flutter/material.dart' show IconData, Icons;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/ffmpeg_engine.dart';
import 'package:anvil/tools/video/ffmpeg_cmd.dart' as cmd;

// ── Helpers ──────────────────────────────────────────────────────────────────

const _mimeByExt = {
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'mkv': 'video/x-matroska',
  'avi': 'video/x-msvideo',
  'webm': 'video/webm',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'flac': 'audio/flac',
  'ogg': 'audio/ogg',
  'm4a': 'audio/mp4',
  'm4r': 'audio/mp4',
};

String _mime(String ext) => _mimeByExt[ext] ?? 'application/octet-stream';

String _outName(String input, String ext) {
  final dot = input.lastIndexOf('.');
  final base = dot <= 0 ? input : input.substring(0, dot);
  return '$base.$ext';
}

/// Lowercase extension of [name].
String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

int _intParam(Map<String, dynamic> params, String key, int fallback) =>
    switch (params[key]) {
      final int v => v,
      _ => fallback,
    };

/// Seconds-style params: the agent passes integers, the editors pass
/// fractional seconds (a timeline selection), so accept any number.
double _numParam(Map<String, dynamic> params, String key, double fallback) =>
    switch (params[key]) {
      final num v => v.toDouble(),
      _ => fallback,
    };

String _textParam(Map<String, dynamic> params, String key, String fallback) =>
    switch (params[key]) {
      final String v => v,
      _ => fallback,
    };

/// Builds the FFmpeg args for one run. [inExt] is the (lowercased) source
/// extension so container-keeping tools (compress/resize/cutter/mute) can
/// pick policy codecs. Async so a builder can probe the source first
/// (target-size compress needs the duration).
typedef _ArgsBuilder =
    FutureOr<List<String>> Function(
      String inPath,
      String outPath,
      String inExt,
      Map<String, dynamic> params,
    );

/// One FFmpeg-backed tool: single media file in → single media file out.
/// FFmpeg reads/writes paths directly — no byte copies through Dart.
class _FfmpegTool extends BaseToolModule {
  _FfmpegTool(this.meta, this._outExt, this._build);
  @override
  final ToolMeta meta;

  /// Target extension; null keeps the input's container/extension.
  final String? _outExt;
  final _ArgsBuilder _build;

  @override
  EngineKind get engine => EngineKind.ffmpeg;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    final f = input.files.single;
    final inExt = _ext(f.name);
    final ext = _outExt ?? inExt;
    final name = _outName(f.name, ext);
    final out = await getIt<FileService>().reserveFile(name);
    yield const ToolRunning(message: 'Converting…');
    final args = await _build(f.path, out.path, inExt, input.params);
    await getIt<FfmpegEngine>().run(args);
    if (!await out.exists() || await out.length() == 0) {
      throw const ToolException('Conversion produced no output.');
    }
    yield ToolSucceeded(
      ToolResult(
        files: [OutputFile(path: out.path, name: name, mimeType: _mime(ext))],
      ),
    );
  }
}

// ── Registration ─────────────────────────────────────────────────────────────

ToolMeta _meta(
  String id,
  String label,
  IconData icon,
  String description,
  List<String> accepts, {
  List<ToolParam> params = const [],
}) => ToolMeta(
  id: id,
  category: ToolCategory.video,
  label: label,
  icon: icon,
  description: description,
  tinywowSlug: id,
  acceptedExtensions: accepts,
  params: params,
);

const _videoExts = ['mp4', 'mov', 'mkv', 'avi', 'webm'];

/// `<src>-to-<container>` video conversion tool.
_FfmpegTool _videoConvert(String from, String to, {String? label}) =>
    _FfmpegTool(
      _meta(
        '$from-to-$to',
        label ?? '${from.toUpperCase()} to ${to.toUpperCase()}',
        Icons.movie,
        'Convert a .$from video into a .$to video.',
        [from],
      ),
      to,
      (i, o, _, p) => cmd.videoConvert(i, o, to, evenDims: from == 'gif'),
    );

/// `<src>-to-<audio>` audio extraction/conversion tool.
_FfmpegTool _audioConvert(String from, String to) => _FfmpegTool(
  _meta(
    '$from-to-$to',
    '${from.toUpperCase()} to ${to.toUpperCase()}',
    Icons.audiotrack,
    'Convert .$from audio/video into a .$to audio file.',
    [from],
  ),
  to,
  (i, o, _, p) => cmd.extractAudio(i, o, to),
);

/// Audio remux into an audio-only .mp4 without re-encoding.
_FfmpegTool _audioToMp4(String from) => _FfmpegTool(
  _meta(
    '$from-to-mp4',
    '${from.toUpperCase()} to MP4',
    Icons.audiotrack,
    'Wrap .$from audio in an MP4 container without re-encoding.',
    [from],
  ),
  'mp4',
  (i, o, _, p) => cmd.audioCopyToMp4(i, o),
);

/// Video compressor that keeps the source container. `targetMb` > 0 probes
/// the duration and encodes to a computed bitrate instead of `quality`.
_FfmpegTool _compress(String id, List<String> accepts) => _FfmpegTool(
  _meta(
    id,
    id == 'compress'
        ? 'Compress Video'
        : 'Compress ${accepts.single.toUpperCase()}',
    Icons.compress,
    'Shrink a video by downscaling and re-encoding.',
    accepts,
    params: const [
      ToolParam(
        key: 'height',
        label: 'Target height (px)',
        defaultValue: 720,
        helperText: '0 keeps the source size.',
      ),
      ToolParam(
        key: 'quality',
        label: 'Quality (1 best - 31 smallest)',
        defaultValue: 6,
      ),
      ToolParam(
        key: 'targetMb',
        label: 'Target size (MB)',
        helperText: '0 = off; otherwise aims the file at this size.',
      ),
    ],
  ),
  null,
  _compressArgs,
);

Future<List<String>> _compressArgs(
  String i,
  String o,
  String inExt,
  Map<String, dynamic> p,
) async {
  final targetMb = _intParam(p, 'targetMb', 0);
  var bitrate = 0;
  if (targetMb > 0) {
    final probe = await getIt<FfmpegEngine>().probe(i);
    bitrate = cmd.targetVideoBitrate(
      targetBytes: targetMb * 1024 * 1024,
      durationMs: probe.durationMs,
      audioBitsPerSec: probe.hasAudio ? cmd.targetAudioBitsPerSec : 0,
    );
  }
  return cmd.compress(
    i,
    o,
    inExt,
    height: _intParam(p, 'height', 720),
    quality: _intParam(p, 'quality', 6),
    videoBitsPerSec: bitrate,
  );
}

const _gifParams = [
  ToolParam(key: 'fps', label: 'Frames per second', defaultValue: 12),
  ToolParam(key: 'width', label: 'Width (px)', defaultValue: 480),
  ToolParam(key: 'start', label: 'Start (seconds)'),
  ToolParam(
    key: 'duration',
    label: 'Duration (seconds)',
    helperText: '0 = to the end.',
  ),
];

/// Animated GIF export of a video window (`start`/`duration` seconds).
_FfmpegTool _gif(
  String id,
  String label,
  IconData icon,
  String description,
  List<String> accepts,
) => _FfmpegTool(
  _meta(id, label, icon, description, accepts, params: _gifParams),
  'gif',
  (i, o, _, p) => cmd.toGif(
    i,
    o,
    fps: _intParam(p, 'fps', 12),
    width: _intParam(p, 'width', 480),
    start: _numParam(p, 'start', 0),
    duration: _numParam(p, 'duration', 0),
  ),
);

/// Every video/audio tool. The single registration list for this category.
List<ToolModule> buildVideoTools() => [
  // AAC sources.
  _audioConvert('aac', 'flac'),
  _FfmpegTool(
    _meta(
      'aac-to-m4r',
      'AAC to M4R',
      Icons.notifications_active,
      'Convert AAC audio into an iPhone ringtone (.m4r).',
      ['aac'],
    ),
    'm4r',
    (i, o, _, p) => cmd.extractAudio(i, o, 'm4r'),
  ),
  _audioConvert('aac', 'mp3'),
  _audioToMp4('aac'),
  _audioConvert('aac', 'wav'),
  // AVI sources.
  _gif(
    'avi-to-gif',
    'AVI to GIF',
    Icons.gif,
    'Turn an AVI video into an animated GIF.',
    ['avi'],
  ),
  _videoConvert('avi', 'mkv'),
  _videoConvert('avi', 'mov'),
  _audioConvert('avi', 'mp3'),
  _videoConvert('avi', 'mp4'),
  // Compress family.
  _compress('compress', _videoExts),
  _compress('compress-avi', ['avi']),
  _compress('compress-mkv', ['mkv']),
  _compress('compress-mov', ['mov']),
  // Editing.
  _FfmpegTool(
    _meta(
      'cutter',
      'Video Cutter',
      Icons.content_cut,
      'Cut a clip out of a video without re-encoding.',
      _videoExts,
      params: const [
        ToolParam(key: 'start', label: 'Start (seconds)'),
        ToolParam(
          key: 'duration',
          label: 'Duration (seconds)',
          defaultValue: 10,
        ),
        ToolParam(
          key: 'mute',
          label: 'Remove sound',
          type: ToolParamType.choice,
          defaultText: 'no',
          choices: ['no', 'yes'],
        ),
      ],
    ),
    null,
    (i, o, _, p) => cmd.cut(
      i,
      o,
      startSeconds: _numParam(p, 'start', 0),
      durationSeconds: _numParam(p, 'duration', 10),
      mute: _textParam(p, 'mute', 'no') == 'yes',
    ),
  ),
  _FfmpegTool(
    _meta(
      'extract-audio',
      'Extract Audio',
      Icons.music_note,
      'Extract a video\'s audio track as an MP3.',
      _videoExts,
    ),
    'mp3',
    (i, o, _, p) => cmd.extractAudio(i, o, 'mp3'),
  ),
  // GIF sources.
  _videoConvert('gif', 'mov'),
  _videoConvert('gif', 'webm'),
  // M4A sources.
  _audioConvert('m4a', 'mp3'),
  _audioToMp4('m4a'),
  _audioConvert('m4a', 'wav'),
  // MKV sources.
  _videoConvert('mkv', 'avi'),
  _gif(
    'mkv-to-gif',
    'MKV to GIF',
    Icons.gif,
    'Turn an MKV video into an animated GIF.',
    ['mkv'],
  ),
  _videoConvert('mkv', 'mov'),
  _audioConvert('mkv', 'mp3'),
  _videoConvert('mkv', 'mp4'),
  // MOV sources.
  _videoConvert('mov', 'avi'),
  _gif(
    'mov-to-gif',
    'MOV to GIF',
    Icons.gif,
    'Turn a MOV video into an animated GIF.',
    ['mov'],
  ),
  _audioConvert('mov', 'mp3'),
  _videoConvert('mov', 'mp4'),
  _audioConvert('mov', 'wav'),
  // MP4 sources.
  _videoConvert('mp4', 'avi'),
  _gif(
    'mp4-to-gif',
    'MP4 to GIF',
    Icons.gif,
    'Turn an MP4 video into an animated GIF.',
    ['mp4'],
  ),
  _videoConvert('mp4', 'mov'),
  _audioConvert('mp4', 'mp3'),
  _audioConvert('mp4', 'ogg'),
  _audioConvert('mp4', 'wav'),
  _videoConvert('mp4', 'webm'),
  // Track ops.
  _FfmpegTool(
    _meta(
      'mute',
      'Mute Video',
      Icons.volume_off,
      'Remove the audio track from a video (no re-encode).',
      _videoExts,
    ),
    null,
    (i, o, _, p) => cmd.mute(i, o),
  ),
  // OGG sources.
  _audioConvert('ogg', 'mp3'),
  _audioConvert('ogg', 'wav'),
  // Resize.
  _FfmpegTool(
    _meta(
      'resize',
      'Resize Video',
      Icons.aspect_ratio,
      'Scale a video to an exact width and height.',
      _videoExts,
      params: const [
        ToolParam(key: 'width', label: 'Width (px)', defaultValue: 1280),
        ToolParam(key: 'height', label: 'Height (px)', defaultValue: 720),
      ],
    ),
    null,
    (i, o, inExt, p) => cmd.resize(
      i,
      o,
      inExt,
      width: _intParam(p, 'width', 1280),
      height: _intParam(p, 'height', 720),
    ),
  ),
  // Animated exports.
  _gif(
    'to-gif',
    'Video to GIF',
    Icons.gif_box,
    'Turn any video into an animated GIF.',
    _videoExts,
  ),
  _FfmpegTool(
    _meta(
      'to-webp',
      'Video to WebP',
      Icons.animation,
      'Turn any video into an animated WebP.',
      _videoExts,
      params: _gifParams,
    ),
    'webp',
    (i, o, _, p) => cmd.toAnimatedWebp(
      i,
      o,
      fps: _intParam(p, 'fps', 12),
      width: _intParam(p, 'width', 480),
      start: _numParam(p, 'start', 0),
      duration: _numParam(p, 'duration', 0),
    ),
  ),
  // WebM sources.
  _videoConvert('webm', 'mov'),
  _audioConvert('webm', 'mp3'),
  _videoConvert('webm', 'mp4'),
];
