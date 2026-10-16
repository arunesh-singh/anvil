/// Wraps `ffmpeg_kit_flutter_new_full` (sk3llo fork, LGPL "full" flavor — no
/// x264/x265, per D4/R2) — the single place the FFmpeg plugin is touched, so a
/// future engine swap is one file.
///
/// FFmpegKit runs commands on its own native worker threads, so callers do NOT
/// wrap [FfmpegEngine.run] in `runOffThread`. Commands are built as argument
/// lists by the pure-Dart builders in `lib/tools/video/ffmpeg_cmd.dart`
/// (unit-tested on the host); this class only executes them on-device.
library;

import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';

import 'package:anvil/core/tool_io.dart';

/// What the video editors need to know about a source before any encode.
/// [width]/[height] are the DISPLAY size (rotation metadata applied — ffmpeg
/// auto-rotates before filters, so scale maths must use these).
class VideoProbe {
  const VideoProbe({
    required this.durationMs,
    required this.width,
    required this.height,
    required this.sizeBytes,
    this.bitRate,
    required this.hasAudio,
  });

  final int durationMs;
  final int width;
  final int height;
  final int sizeBytes;

  /// Container bit rate (bits/s) when ffprobe reports it.
  final int? bitRate;
  final bool hasAudio;

  /// The shorter display side — what "720p" refers to for portrait clips.
  int get shortSide => width < height ? width : height;

  /// Parses ffprobe's `-show_format -show_streams` JSON ([format] and
  /// [streams] maps). [fileBytes] is the fallback when the format has no
  /// `size`. Pure, so it is host-testable.
  factory VideoProbe.fromFfprobe(
    Map<dynamic, dynamic> format,
    List<Map<dynamic, dynamic>> streams, {
    int fileBytes = 0,
  }) {
    final video = streams.where((s) => s['codec_type'] == 'video').firstOrNull;
    var w = _int(video?['width']) ?? 0;
    var h = _int(video?['height']) ?? 0;
    if (_rotation(video) % 180 != 0) (w, h) = (h, w);
    final seconds = _num(format['duration']) ?? _num(video?['duration']) ?? 0;
    return VideoProbe(
      durationMs: (seconds * 1000).round(),
      width: w,
      height: h,
      sizeBytes: _int(format['size']) ?? fileBytes,
      bitRate: _int(format['bit_rate']),
      hasAudio: streams.any((s) => s['codec_type'] == 'audio'),
    );
  }

  /// Rotation in degrees from either the legacy `tags.rotate` or the
  /// display-matrix side data newer ffprobe builds report.
  static int _rotation(Map<dynamic, dynamic>? stream) {
    if (stream == null) return 0;
    final tags = stream['tags'];
    if (tags is Map) {
      final r = _int(tags['rotate']);
      if (r != null) return r.abs();
    }
    final side = stream['side_data_list'];
    if (side is List) {
      for (final d in side) {
        if (d is Map) {
          final r = _int(d['rotation']);
          if (r != null) return r.abs();
        }
      }
    }
    return 0;
  }

  static num? _num(Object? v) => switch (v) {
    final num n => n,
    final String s => num.tryParse(s.trim()),
    _ => null,
  };

  static int? _int(Object? v) => _num(v)?.round();
}

/// Lets a caller cancel ONE in-flight FFmpeg run (an estimate sample, a
/// thumbnail pass) without touching any other session — `FFmpegKit.cancel()`
/// with no id would kill a running tool job too.
class FfmpegHandle {
  int? _sessionId;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  Future<void> cancel() async {
    _cancelled = true;
    final id = _sessionId;
    if (id != null) await FFmpegKit.cancel(id);
  }
}

class FfmpegEngine {
  /// Executes one FFmpeg invocation. Throws [ToolException] on a non-zero
  /// return code, including the tail of the FFmpeg log so failures are
  /// actionable. [onProgress] receives elapsed output milliseconds when known.
  /// [handle] (optional) can cancel just this run.
  Future<void> run(
    List<String> args, {
    void Function(int outputTimeMs)? onProgress,
    FfmpegHandle? handle,
  }) async {
    if (handle?.isCancelled ?? false) {
      throw const ToolException('Conversion cancelled.');
    }
    final FFmpegSession session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      null,
      null,
      onProgress == null
          ? null
          : (stats) {
              final t = stats.getTime();
              if (t > 0) onProgress(t.toInt());
            },
    );
    if (handle != null) {
      handle._sessionId = session.getSessionId();
      if (handle.isCancelled) await handle.cancel();
    }

    // executeWithArgumentsAsync returns immediately; poll until terminal.
    ReturnCode? code = await session.getReturnCode();
    while (code == null) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      code = await session.getReturnCode();
    }
    if (ReturnCode.isCancel(code)) {
      throw const ToolException('Conversion cancelled.');
    }
    if (!ReturnCode.isSuccess(code)) {
      final log = await session.getOutput() ?? '';
      final tail = log.length > 400 ? log.substring(log.length - 400) : log;
      throw ToolException('Conversion failed.\n$tail');
    }
  }

  /// Reads duration, display size, file size, bit rate and whether there is
  /// an audio track. Throws [ToolException] when the file is not a readable
  /// video.
  Future<VideoProbe> probe(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    final all = info?.getAllProperties();
    if (info == null || all == null) {
      throw const ToolException('Could not read this video.');
    }
    final probe = VideoProbe.fromFfprobe(
      info.getFormatProperties() ?? const {},
      [
        for (final s in (all['streams'] as List? ?? const []))
          if (s is Map) s,
      ],
      fileBytes: await File(path).length(),
    );
    if (probe.durationMs <= 0 || probe.width <= 0) {
      throw const ToolException('Could not read this video.');
    }
    return probe;
  }

  /// Runs [args] (whose output path is [output]) and returns the byte size
  /// of what it wrote, deleting the file afterwards. Used for size-estimate
  /// samples; [handle] cancels a stale sample.
  Future<int> measure(
    List<String> args,
    String output, {
    FfmpegHandle? handle,
  }) async {
    final f = File(output);
    try {
      await run(args, handle: handle);
      return await f.exists() ? await f.length() : 0;
    } finally {
      if (await f.exists()) await f.delete();
    }
  }

  /// A fresh temp directory for scratch output (timeline thumbnails,
  /// estimate samples); the OS cache cleaner reclaims it.
  Future<String> tempDir(String prefix) async =>
      (await Directory.systemTemp.createTemp('anvil_${prefix}_')).path;

  /// Cancels every in-flight FFmpeg session.
  Future<void> cancelAll() => FFmpegKit.cancel();
}
