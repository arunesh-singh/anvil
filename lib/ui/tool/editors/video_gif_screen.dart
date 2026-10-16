/// Video to GIF / animated WebP (`video/to-gif`, `<ext>-to-gif`,
/// `video/to-webp`; design "Video to GIF"): pick the moment on the timeline,
/// watch it loop, and see the output size — measured from a short sample —
/// before export, because GIFs balloon fast.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/tools/video/ffmpeg_cmd.dart' as cmd;
import 'package:anvil/ui/tool/editors/tool_frame.dart';
import 'package:anvil/ui/tool/editors/tool_stage.dart';
import 'package:anvil/ui/tool/editors/video_math.dart';
import 'package:anvil/ui/tool/editors/video_stage.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

class GifScreen extends ConsumerStatefulWidget {
  const GifScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<GifScreen> createState() => _GifScreenState();
}

class _GifScreenState extends ConsumerState<GifScreen>
    with VideoLoader<GifScreen> {
  int _startMs = 0;
  int _endMs = 0;
  int _fps = gifFpsOptions[1];
  int _width = gifWidthOptions[1];
  final _estimate = SizeEstimator();

  /// Longest sample encoded per estimate.
  static const _sampleMs = 1500;

  bool get _webp => widget.tool.meta.id == 'to-webp';
  String get _ext => _webp ? 'webp' : 'gif';

  @override
  ToolModule get tool => widget.tool;

  @override
  void onVideoReady(VideoSession s) {
    final d = s.probe.durationMs;
    _startMs = 0;
    _endMs = d < gifDefaultWindowMs ? d : gifDefaultWindowMs;
    s
      ..loop = true
      ..setWindow(_startMs, _endMs);
    unawaited(s.player.setVolume(0)); // a GIF has no sound
    unawaited(s.play());
    _measure(s);
  }

  @override
  void dispose() {
    _estimate.dispose();
    super.dispose();
  }

  void _measure(VideoSession s) {
    final windowMs = _endMs - _startMs;
    final (startMs, lenMs) = sampleWindow(
      durationMs: s.probe.durationMs,
      maxSampleMs: _sampleMs,
      windowStartMs: _startMs,
      windowMs: windowMs,
    );
    final fps = _fps;
    final width = _width;
    final webp = _webp;
    _estimate.request((handle) async {
      final bytes = await measureSample(_ext, handle, (out) {
        final start = startMs / 1000;
        final duration = lenMs / 1000;
        return webp
            ? cmd.toAnimatedWebp(
                s.file.path,
                out,
                fps: fps,
                width: width,
                start: start,
                duration: duration,
              )
            : cmd.toGif(
                s.file.path,
                out,
                fps: fps,
                width: width,
                start: start,
                duration: duration,
              );
      });
      return bytes == null
          ? null
          : extrapolateBytes(
              sampleBytes: bytes,
              sampleMs: lenMs,
              totalMs: windowMs,
            );
    });
  }

  void _run() {
    final s = session!;
    unawaited(s.pause());
    _estimate.cancel();
    ref
        .read(jobProvider.notifier)
        .start(
          widget.tool,
          ToolInput(
            files: [s.file],
            params: {
              'fps': _fps,
              'width': _width,
              'start': _startMs / 1000,
              'duration': (_endMs - _startMs) / 1000,
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    return ToolFrame(
      tool: widget.tool,
      title: _webp ? 'Video to WebP' : 'Video to GIF',
      hasInput: s != null || loadingVideo,
      onPicked: openVideo,
      body: s == null
          ? const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          : _body(s),
      runLabel: _webp ? 'Make WebP' : 'Make GIF',
      onRun: s == null ? null : _run,
    );
  }

  Widget _body(VideoSession s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListenableBuilder(
        listenable: s,
        builder: (context, _) => VideoStage(
          session: s,
          playButton: false,
          bar: [
            const StagePill(label: 'looping preview'),
            StagePill(
              icon: s.playing ? Icons.pause : Icons.play_arrow,
              tooltip: s.playing ? 'Pause' : 'Play',
              onTap: s.toggle,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      ListenableBuilder(
        listenable: s,
        builder: (context, _) => VideoTimeline(
          thumbs: s.thumbs,
          durationMs: s.probe.durationMs,
          startMs: _startMs,
          endMs: _endMs,
          onWindowChanged: (a, b, {required movedStart}) {
            setState(() {
              _startMs = a;
              _endMs = b;
            });
            s
              ..setWindow(a, b)
              ..seek(a);
            _measure(s);
          },
        ),
      ),
      TimelineLabels(
        start: clockTenths(_startMs),
        centre: secondsLabel(_endMs - _startMs),
        end: clockTenths(_endMs),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionEyebrow('Smoothness'),
                const SizedBox(height: 8),
                WsSegmented(
                  labels: [for (final f in gifFpsOptions) '$f'],
                  selected: gifFpsOptions.indexOf(_fps),
                  onChanged: (i) {
                    setState(() => _fps = gifFpsOptions[i]);
                    _measure(s);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionEyebrow('Width'),
                const SizedBox(height: 8),
                WsSegmented(
                  labels: [for (final w in gifWidthOptions) '$w'],
                  selected: gifWidthOptions.indexOf(_width),
                  onChanged: (i) {
                    setState(() => _width = gifWidthOptions[i]);
                    _measure(s);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ListenableBuilder(
        listenable: _estimate,
        builder: (context, _) {
          final v = _estimate.value;
          return WsEstimate(
            label: _webp ? 'WebP size' : 'GIF size',
            value: v == null
                ? (_estimate.busy ? '…' : '?')
                : '≈ ${compactBytes(v)}',
          );
        },
      ),
    ],
  );
}
