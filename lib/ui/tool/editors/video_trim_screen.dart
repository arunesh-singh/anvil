/// Trim video (`video/cutter`, design "Trim video"): the video plays on the
/// stage, a thumbnail timeline with two handles picks the selection, times
/// read as m:ss, and Run states the clip length and size before cutting.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tool/editors/tool_frame.dart';
import 'package:anvil/ui/tool/editors/tool_stage.dart';
import 'package:anvil/ui/tool/editors/video_math.dart';
import 'package:anvil/ui/tool/editors/video_stage.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

class TrimVideoScreen extends ConsumerStatefulWidget {
  const TrimVideoScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<TrimVideoScreen> createState() => _TrimVideoScreenState();
}

class _TrimVideoScreenState extends ConsumerState<TrimVideoScreen>
    with VideoLoader<TrimVideoScreen> {
  int _startMs = 0;
  int _endMs = 0;
  bool _mute = false;

  static const _minMs = 500;

  @override
  ToolModule get tool => widget.tool;

  @override
  void onVideoReady(VideoSession s) {
    _startMs = 0;
    _endMs = s.probe.durationMs;
    s.setWindow(_startMs, _endMs);
  }

  void _setWindow(int start, int end) {
    setState(() {
      _startMs = start;
      _endMs = end;
    });
    session?.setWindow(start, end);
  }

  void _setStart() {
    final pos = session!.positionMs;
    if (pos <= _endMs - _minMs) _setWindow(pos, _endMs);
  }

  void _setEnd() {
    final pos = session!.positionMs;
    if (pos >= _startMs + _minMs) _setWindow(_startMs, pos);
  }

  void _run() {
    final s = session!;
    s.pause();
    ref
        .read(jobProvider.notifier)
        .start(
          widget.tool,
          ToolInput(
            files: [s.file],
            params: {
              'start': _startMs / 1000,
              'duration': (_endMs - _startMs) / 1000,
              'mute': _mute ? 'yes' : 'no',
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final len = _endMs - _startMs;
    return ToolFrame(
      tool: widget.tool,
      title: 'Trim video',
      hasInput: s != null || loadingVideo,
      onPicked: openVideo,
      body: s == null
          ? const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          : _body(s),
      runLabel: 'Trim',
      runDetail: s == null
          ? null
          : '· ${secondsLabel(len)} · ${compactBytes(trimEstimateBytes(sizeBytes: s.probe.sizeBytes, durationMs: s.probe.durationMs, selectionMs: len))}',
      runIcon: null,
      onRun: s == null ? null : _run,
    );
  }

  Widget _body(VideoSession s) => ListenableBuilder(
    listenable: s,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VideoStage(
          session: s,
          bar: [
            StagePill(
              label: '${clock(s.positionMs)} / ${clock(s.probe.durationMs)}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        VideoTimeline(
          thumbs: s.thumbs,
          durationMs: s.probe.durationMs,
          startMs: _startMs,
          endMs: _endMs,
          playheadMs: s.positionMs,
          minWindowMs: _minMs,
          onWindowChanged: (a, b, {required movedStart}) {
            _setWindow(a, b);
            if (s.playing) s.pause();
            s.seek(movedStart ? a : b);
          },
          onSeek: s.seek,
        ),
        TimelineLabels(
          start: clockTenths(_startMs),
          centre: 'selection ${clockTenths(_endMs - _startMs)}',
          end: clockTenths(_endMs),
        ),
        const SizedBox(height: 12),
        WsPillRail(
          children: [
            WsPill(
              icon: Icons.first_page,
              label: 'Set start',
              onTap: _setStart,
            ),
            WsPill(icon: Icons.last_page, label: 'Set end', onTap: _setEnd),
            WsPill(
              icon: Icons.volume_off,
              label: 'Mute',
              on: _mute,
              onTap: () => setState(() => _mute = !_mute),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const InfoCard('No re-encode — trimming is instant and lossless.'),
      ],
    ),
  );
}
