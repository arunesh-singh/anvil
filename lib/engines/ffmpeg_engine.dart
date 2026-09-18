import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';

import 'package:anvil/core/tool_io.dart';

/// Wraps `ffmpeg_kit_flutter_new_full` (sk3llo fork, LGPL "full" flavor — no
/// x264/x265, per D4/R2) — the single place the FFmpeg plugin is touched, so a
/// future engine swap is one file.
///
/// FFmpegKit runs commands on its own native worker threads, so callers do NOT
/// wrap [run] in `runOffThread`. Commands are built as argument lists by the
/// pure-Dart builders in `lib/tools/video/ffmpeg_cmd.dart` (unit-tested on the
/// host); this class only executes them on-device.
class FfmpegEngine {
  /// Executes one FFmpeg invocation. Throws [ToolException] on a non-zero
  /// return code, including the tail of the FFmpeg log so failures are
  /// actionable. [onProgress] receives elapsed output milliseconds when known.
  Future<void> run(
    List<String> args, {
    void Function(int outputTimeMs)? onProgress,
  }) async {
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

  /// Cancels every in-flight FFmpeg session.
  Future<void> cancelAll() => FFmpegKit.cancel();
}
