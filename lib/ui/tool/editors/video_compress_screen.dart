/// Compress video (`video/compress` + the per-container variants, design
/// "Compress video"): choose by destination, resolution as chips, a named
/// quality slider, and an estimate measured from a real sample encode —
/// stated before Run.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/ffmpeg_engine.dart';
import 'package:anvil/tools/video/ffmpeg_cmd.dart' as cmd;
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/tool_frame.dart';
import 'package:anvil/ui/tool/editors/tool_stage.dart';
import 'package:anvil/ui/tool/editors/video_math.dart';
import 'package:anvil/ui/tool/editors/video_stage.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

class CompressVideoScreen extends ConsumerStatefulWidget {
  const CompressVideoScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<CompressVideoScreen> createState() =>
      _CompressVideoScreenState();
}

class _CompressVideoScreenState extends ConsumerState<CompressVideoScreen>
    with VideoLoader<CompressVideoScreen> {
  CompressSettings _settings = const CompressSettings(
    shortSide: 720,
    quality: 6,
  );
  final _estimate = SizeEstimator();

  /// Encoded per estimate; ~2 s from the middle of the video.
  static const _sampleMs = 2000;

  @override
  ToolModule get tool => widget.tool;

  @override
  void onVideoReady(VideoSession s) {
    _settings = presetSettings(CompressPreset.whatsapp, s.probe.shortSide);
    _measure(s, _settings);
  }

  @override
  void dispose() {
    _estimate.dispose();
    super.dispose();
  }

  void _apply(CompressSettings next) {
    setState(() => _settings = next);
    _measure(session!, next);
  }

  int _heightParam(VideoProbe p, CompressSettings s) =>
      heightParamFor(s.shortSide, p.width, p.height);

  void _measure(VideoSession s, CompressSettings set) {
    final probe = s.probe;
    if (set.targetMb > 0) {
      _estimate.set(
        targetEstimateBytes(
          targetMb: set.targetMb,
          durationMs: probe.durationMs,
          hasAudio: probe.hasAudio,
        ),
      );
      return;
    }
    final (startMs, lenMs) = sampleWindow(
      durationMs: probe.durationMs,
      maxSampleMs: _sampleMs,
    );
    _estimate.request((handle) async {
      final bytes = await measureSample(
        s.ext,
        handle,
        (out) => cmd.compress(
          s.file.path,
          out,
          s.ext,
          height: _heightParam(probe, set),
          quality: set.quality,
          start: startMs / 1000,
          duration: lenMs / 1000,
        ),
      );
      return bytes == null
          ? null
          : extrapolateBytes(
              sampleBytes: bytes,
              sampleMs: lenMs,
              totalMs: probe.durationMs,
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
              'height': _heightParam(s.probe, _settings),
              'quality': _settings.quality,
              'targetMb': _settings.targetMb,
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    return ToolFrame(
      tool: widget.tool,
      title: 'Compress video',
      hasInput: s != null || loadingVideo,
      onPicked: openVideo,
      body: s == null
          ? const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          : _body(context, s),
      runLabel: 'Compress',
      onRun: s == null ? null : _run,
    );
  }

  Widget _body(BuildContext context, VideoSession s) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final probe = s.probe;
    final source = probe.shortSide;
    final preset = presetFor(_settings, source);
    final resolutions = resolutionOptions(source);
    final selectedRes = resolutions.indexOf(_settings.shortSide);
    // webm keeps its fixed-CRF VP9 preset; a target size replaces quality.
    final qualityApplies = _settings.targetMb == 0 && s.ext != 'webm';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: s,
          builder: (context, _) => VideoStage(
            session: s,
            bar: [
              StagePill(
                label:
                    '${probe.width} × ${probe.height} · '
                    '${clock(probe.durationMs)} · ${compactBytes(probe.sizeBytes)}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionEyebrow('Made for'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in CompressPreset.values)
              WsPill(
                label: p.label,
                on: p == preset,
                onTap: () => _apply(presetSettings(p, source)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const SectionEyebrow('Resolution'),
        const SizedBox(height: 8),
        WsSegmented(
          labels: [for (final r in resolutions) resolutionLabel(r, source)],
          selected: selectedRes < 0 ? 0 : selectedRes,
          onChanged: (i) =>
              _apply(_settings.copyWith(shortSide: resolutions[i])),
        ),
        const SizedBox(height: 14),
        if (qualityApplies)
          LabeledSlider(
            title: 'Quality',
            valueLabel:
                '${qualityName(_settings.quality)} · q${_settings.quality}',
            // Reversed: right = sharper = lower qscale.
            value: (qualityBest + qualityWorst - _settings.quality).toDouble(),
            min: qualityBest.toDouble(),
            max: qualityWorst.toDouble(),
            divisions: qualityWorst - qualityBest,
            onChanged: (v) => setState(
              () => _settings = _settings.copyWith(
                quality: qualityBest + qualityWorst - v.round(),
              ),
            ),
            onChangeEnd: (_) => _measure(s, _settings),
            startLabel: 'smaller',
            endLabel: 'sharper',
          )
        else
          Text(
            _settings.targetMb > 0
                ? 'Quality follows the ${_settings.targetMb} MB target.'
                : 'WebM keeps its own quality setting.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: c.muted),
          ),
        if (_settings.targetMb > 0) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _apply(_settings.copyWith(targetMb: 0)),
            child: const Text('Set quality instead'),
          ),
        ],
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: _estimate,
          builder: (context, _) {
            final after = _estimate.value;
            return WsEstimate(
              label: 'Estimated',
              value:
                  '${compactBytes(probe.sizeBytes)} → '
                  '${after == null ? (_estimate.busy ? '…' : '?') : compactBytes(after)}',
              delta: after == null
                  ? null
                  : savingsLabel(probe.sizeBytes, after),
            );
          },
        ),
      ],
    );
  }
}
