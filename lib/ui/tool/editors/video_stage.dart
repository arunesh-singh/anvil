/// Shared pieces of the video screens (trim, compress, GIF — design
/// `explorations/tools-workspace.html`): the opened-video session (probe +
/// player + timeline thumbnails, window-bounded playback), the player stage,
/// the thumbnail timeline with a draggable selection window, and a debounced
/// size estimator that measures real sample encodes.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/ffmpeg_engine.dart';
import 'package:anvil/tools/video/ffmpeg_cmd.dart' as cmd;
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/tool_stage.dart';
import 'package:anvil/ui/tool/input/input_picker.dart';

AnvilColors _c(BuildContext context) =>
    Theme.of(context).extension<AnvilColors>()!;

/// Number of frames on the timeline strip (the mock's nine tiles).
const _thumbCount = 9;

/// One opened video: its probe, a player, and the timeline thumbnails
/// (filled in after open). Playback is bounded to a window: playing starts
/// inside it and stops (or loops, [loop]) at its end.
class VideoSession extends ChangeNotifier {
  VideoSession._(this.file, this.probe, this.player)
    : _windowEnd = probe.durationMs;

  final InputFile file;
  final VideoProbe probe;
  final VideoPlayerController player;

  List<String> _thumbs = const [];
  List<String> get thumbs => _thumbs;

  final _thumbHandle = FfmpegHandle();
  String? _thumbDir;
  Timer? _ticker;
  bool _disposed = false;

  int _windowStart = 0;
  int _windowEnd;
  int _positionMs = 0;

  /// Loop the window instead of stopping at its end (GIF preview).
  bool loop = false;

  /// Lowercase source extension (the container compress keeps).
  String get ext {
    final dot = file.name.lastIndexOf('.');
    return dot < 0 ? '' : file.name.substring(dot + 1).toLowerCase();
  }

  int get positionMs => _positionMs;
  bool get playing => player.value.isPlaying;

  /// Probes [f], opens a player on it and starts the thumbnail pass.
  /// Throws [ToolException] for unreadable files.
  static Future<VideoSession> open(InputFile f) async {
    final probe = await getIt<FfmpegEngine>().probe(f.path);
    final player = VideoPlayerController.file(File(f.path));
    try {
      await player.initialize();
    } catch (_) {
      await player.dispose();
      throw const ToolException('This video cannot be previewed.');
    }
    final s = VideoSession._(f, probe, player);
    player.addListener(s._onPlayer);
    unawaited(s._loadThumbs());
    return s;
  }

  Future<void> _loadThumbs() async {
    final engine = getIt<FfmpegEngine>();
    final dir = await engine.tempDir('thumbs');
    _thumbDir = dir;
    final out = <String>[];
    final times = cmd.thumbnailTimes(probe.durationMs, _thumbCount);
    for (var i = 0; i < times.length && !_thumbHandle.isCancelled; i++) {
      final path = p.join(dir, 't$i.jpg');
      try {
        await engine.run(
          cmd.thumbnailAt(file.path, path, seconds: times[i]),
          handle: _thumbHandle,
        );
      } on ToolException {
        continue; // a frame that will not decode leaves its tile blank
      }
      out.add(path);
      if (_disposed) return;
      _thumbs = List.unmodifiable([...out]);
      notifyListeners();
    }
  }

  /// Bounds playback to [startMs] … [endMs].
  void setWindow(int startMs, int endMs) {
    _windowStart = startMs;
    _windowEnd = endMs;
  }

  Future<void> seek(int ms) async {
    _positionMs = ms;
    notifyListeners();
    await player.seekTo(Duration(milliseconds: ms));
  }

  /// Plays from the current position, or from the window start when the
  /// playhead sits outside the window (or at its end).
  Future<void> play() async {
    if (_positionMs < _windowStart || _positionMs >= _windowEnd - 100) {
      await seek(_windowStart);
    }
    await player.play();
    // The plugin only reports position about twice a second; poll faster so
    // playback stops on the end handle, not half a second past it.
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _tick(),
    );
  }

  Future<void> pause() async {
    _ticker?.cancel();
    _ticker = null;
    await player.pause();
    notifyListeners();
  }

  Future<void> toggle() => playing ? pause() : play();

  Future<void> _tick() async {
    final pos = await player.position;
    if (_disposed || pos == null) return;
    _positionMs = pos.inMilliseconds;
    if (_positionMs >= _windowEnd) {
      if (loop) {
        await seek(_windowStart);
      } else {
        await pause();
        _positionMs = _windowEnd;
      }
    }
    notifyListeners();
  }

  void _onPlayer() {
    if (!playing && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    unawaited(_thumbHandle.cancel());
    player.removeListener(_onPlayer);
    unawaited(player.dispose());
    final dir = _thumbDir;
    if (dir != null) {
      unawaited(
        Directory(dir).delete(recursive: true).then((_) {}, onError: (_) {}),
      );
    }
    super.dispose();
  }
}

/// Opens the tool's video (shared/hand-off input in `initState`, else the
/// first-open picker via [openVideo]) and owns the [VideoSession].
mixin VideoLoader<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  ToolModule get tool;

  VideoSession? session;
  bool loadingVideo = false;

  /// Called once a session is ready, before the rebuild.
  void onVideoReady(VideoSession s);

  @override
  void initState() {
    super.initState();
    final shared = takeSharedInput(ref, tool.meta);
    if (shared != null) {
      loadingVideo = true; // no setState before the first build
      openVideo([shared]);
    }
  }

  Future<void> openVideo(List<InputFile> files) async {
    if (files.isEmpty) return;
    if (!loadingVideo) setState(() => loadingVideo = true);
    try {
      final s = await VideoSession.open(files.first);
      if (!mounted) {
        s.dispose();
        return;
      }
      session?.dispose();
      onVideoReady(s);
      setState(() {
        session = s;
        loadingVideo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loadingVideo = false);
      final message = e is ToolException
          ? e.message
          : 'Could not open this video.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    session?.dispose();
    super.dispose();
  }
}

/// The player on the stage panel, sized to the video's aspect (capped so the
/// controls stay on screen), with a centred play button while paused when
/// [playButton], and [bar] pills along the bottom.
class VideoStage extends StatelessWidget {
  const VideoStage({
    super.key,
    required this.session,
    this.bar = const [],
    this.playButton = true,
  });

  final VideoSession session;
  final List<Widget> bar;
  final bool playButton;

  @override
  Widget build(BuildContext context) {
    final aspect = session.player.value.aspectRatio;
    return LayoutBuilder(
      builder: (context, box) {
        const pad = 12.0;
        final height = ((box.maxWidth - 2 * pad) / aspect + 2 * pad).clamp(
          160.0,
          320.0,
        );
        return StagePanel(
          height: height,
          padding: const EdgeInsets.all(pad),
          bar: bar,
          child: AspectRatio(
            aspectRatio: aspect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: GestureDetector(
                onTap: session.toggle,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoPlayer(session.player),
                    if (playButton && !session.playing)
                      Center(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            size: 30,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Which part of the selection a timeline drag moves.
enum _Drag { start, end, window, seek }

/// Thumbnail strip with an accent selection window (two handles, the rest
/// dimmed) and an optional playhead. Drag a handle to resize, drag inside
/// the window to move it, tap/drag elsewhere to seek.
class VideoTimeline extends StatefulWidget {
  const VideoTimeline({
    super.key,
    required this.thumbs,
    required this.durationMs,
    required this.startMs,
    required this.endMs,
    required this.onWindowChanged,
    this.playheadMs,
    this.onSeek,
    this.minWindowMs = 500,
  });

  final List<String> thumbs;
  final int durationMs;
  final int startMs;
  final int endMs;

  /// (startMs, endMs) after a drag step; `movedStart` is true when the
  /// start edge moved (a start-handle drag or a window move), false for the
  /// end handle, so the caller can scrub the player to that edge.
  final void Function(int startMs, int endMs, {required bool movedStart})
  onWindowChanged;
  final int? playheadMs;
  final ValueChanged<int>? onSeek;
  final int minWindowMs;

  @override
  State<VideoTimeline> createState() => _VideoTimelineState();
}

class _VideoTimelineState extends State<VideoTimeline> {
  _Drag? _drag;
  double _grabOffsetMs = 0;

  static const _height = 62.0;
  static const _handleSlop = 24.0;

  int _msAt(double dx, double width) =>
      (dx / width * widget.durationMs).round().clamp(0, widget.durationMs);

  double _xOf(int ms, double width) => ms / widget.durationMs * width;

  void _begin(double dx, double width) {
    final sx = _xOf(widget.startMs, width);
    final ex = _xOf(widget.endMs, width);
    final ds = (dx - sx).abs();
    final de = (dx - ex).abs();
    if (ds <= _handleSlop || de <= _handleSlop) {
      _drag = ds <= de ? _Drag.start : _Drag.end;
    } else if (dx > sx && dx < ex) {
      _drag = _Drag.window;
      _grabOffsetMs = (_msAt(dx, width) - widget.startMs).toDouble();
    } else {
      _drag = _Drag.seek;
      widget.onSeek?.call(_msAt(dx, width));
    }
  }

  void _update(double dx, double width) {
    final ms = _msAt(dx, width);
    final len = widget.endMs - widget.startMs;
    switch (_drag) {
      case _Drag.start:
        final s = ms.clamp(0, widget.endMs - widget.minWindowMs);
        widget.onWindowChanged(s, widget.endMs, movedStart: true);
      case _Drag.end:
        final e = ms.clamp(
          widget.startMs + widget.minWindowMs,
          widget.durationMs,
        );
        widget.onWindowChanged(widget.startMs, e, movedStart: false);
      case _Drag.window:
        final s = (ms - _grabOffsetMs).round().clamp(
          0,
          widget.durationMs - len,
        );
        widget.onWindowChanged(s, s + len, movedStart: true);
      case _Drag.seek:
        widget.onSeek?.call(ms);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    // Edge-swipe back gestures eat drags that start near the screen edge, and
    // the handles sit at the timeline's ends; inset past the system zone (the
    // page already has 20 px padding).
    final zone = MediaQuery.systemGestureInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(
        left: math.max(0, zone.left - 20 + 8),
        right: math.max(0, zone.right - 20 + 8),
      ),
      child: _timeline(c),
    );
  }

  Widget _timeline(AnvilColors c) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final sx = _xOf(widget.startMs, w);
        final ex = _xOf(widget.endMs, w);
        final dim = c.bg.withValues(alpha: 0.6);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => widget.onSeek?.call(_msAt(d.localPosition.dx, w)),
          onHorizontalDragStart: (d) => _begin(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _update(d.localPosition.dx, w),
          onHorizontalDragEnd: (_) => _drag = null,
          child: SizedBox(
            height: _height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  top: 3,
                  bottom: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AnvilRadii.chip),
                    child: Row(
                      children: [
                        for (var i = 0; i < _thumbCount; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          Expanded(
                            child: i < widget.thumbs.length
                                ? Image.file(
                                    File(widget.thumbs[i]),
                                    fit: BoxFit.cover,
                                    height: double.infinity,
                                    gaplessPlayback: true,
                                  )
                                : ColoredBox(
                                    color: i.isEven
                                        ? c.containerHigh
                                        : c.container,
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Dim outside the selection.
                Positioned(
                  left: 0,
                  width: sx,
                  top: 3,
                  bottom: 3,
                  child: ColoredBox(color: dim),
                ),
                Positioned(
                  left: ex,
                  right: 0,
                  top: 3,
                  bottom: 3,
                  child: ColoredBox(color: dim),
                ),
                // Selection window with its two handles.
                Positioned(
                  left: sx,
                  width: (ex - sx).clamp(6.0, w),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: c.accent, width: 3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                for (final x in [sx - 3, ex - 11])
                  Positioned(
                    left: x,
                    top: (_height - 30) / 2,
                    child: Container(
                      width: 14,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                if (widget.playheadMs != null)
                  Positioned(
                    left: _xOf(widget.playheadMs!, w) - 1,
                    top: 3,
                    bottom: 3,
                    width: 2,
                    child: ColoredBox(color: c.onSurface),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The mono row under the timeline: start · centre (muted) · end.
class TimelineLabels extends StatelessWidget {
  const TimelineLabels({
    super.key,
    required this.start,
    required this.centre,
    required this.end,
  });

  final String start;
  final String centre;
  final String end;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text(start, style: AnvilText.mono(13, color: c.onSurface)),
          Expanded(
            child: Text(
              centre,
              textAlign: TextAlign.center,
              style: AnvilText.mono(12, color: c.muted),
            ),
          ),
          Text(end, style: AnvilText.mono(13, color: c.onSurface)),
        ],
      ),
    );
  }
}

/// Measures an output size by running a real sample encode: requests are
/// debounced, a newer request cancels the in-flight sample, and stale
/// results are dropped. [value] is null while measuring or after a failure.
class SizeEstimator extends ChangeNotifier {
  SizeEstimator({this.delay = const Duration(milliseconds: 450)});

  final Duration delay;

  int? _value;
  int? get value => _value;
  bool _busy = false;
  bool get busy => _busy;

  Timer? _timer;
  FfmpegHandle? _handle;
  int _generation = 0;
  bool _disposed = false;

  /// Schedules [measure] (bytes, or null for "unknown"); it receives a
  /// handle to pass to the engine so a superseded sample is cancelled.
  void request(Future<int?> Function(FfmpegHandle handle) measure) {
    _timer?.cancel();
    unawaited(_handle?.cancel());
    final gen = ++_generation;
    _busy = true;
    _value = null;
    notifyListeners();
    _timer = Timer(delay, () async {
      final handle = _handle = FfmpegHandle();
      int? result;
      try {
        result = await measure(handle);
      } on ToolException {
        result = null;
      }
      if (_disposed || gen != _generation) return;
      _value = result;
      _busy = false;
      notifyListeners();
    });
  }

  /// Sets a known value (no sample needed), superseding any measurement.
  void set(int? bytes) {
    _timer?.cancel();
    unawaited(_handle?.cancel());
    _generation++;
    _value = bytes;
    _busy = false;
    notifyListeners();
  }

  /// Stops any pending/in-flight sample (e.g. on Run).
  void cancel() {
    _timer?.cancel();
    unawaited(_handle?.cancel());
    _generation++;
    _busy = false;
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

/// Encodes [build]'s sample into a temp `.ext` file and returns its size,
/// or null when the encode produced nothing.
Future<int?> measureSample(
  String ext,
  FfmpegHandle handle,
  List<String> Function(String output) build,
) async {
  final engine = getIt<FfmpegEngine>();
  final dir = await engine.tempDir('sample');
  final out = p.join(dir, 'sample.$ext');
  try {
    final bytes = await engine.measure(build(out), out, handle: handle);
    return bytes > 0 ? bytes : null;
  } finally {
    unawaited(
      Directory(dir).delete(recursive: true).then((_) {}, onError: (_) {}),
    );
  }
}
