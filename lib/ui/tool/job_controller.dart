import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/foreground_task.dart';
import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/models/model_manager.dart';

/// UI-facing state of a tool run.
sealed class JobState {
  const JobState();
}

class JobIdle extends JobState {
  const JobIdle();
}

class JobRunning extends JobState {
  final double? fraction;
  final String? message;
  const JobRunning({this.fraction, this.message});
}

class JobSuccess extends JobState {
  final ToolResult result;
  const JobSuccess(this.result);
}

class JobFailed extends JobState {
  final String message;
  const JobFailed(this.message);
}

class JobCancelled extends JobState {
  const JobCancelled();
}

/// Runs a tool's progress stream, maps it to [JobState], persists history on
/// success, and supports cancel. This is the ONE place thrown errors (or a
/// yielded [ToolFailed]) become [JobFailed].
class JobNotifier extends Notifier<JobState> {
  StreamSubscription<ToolProgress>? _sub;

  @override
  JobState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _release();
    });
    return const JobIdle();
  }

  Future<void> start(ToolModule tool, ToolInput input) async {
    await _sub?.cancel();
    state = const JobRunning(message: 'Starting…');
    final id = tool.meta.qualifiedId;
    logAction(logSourceTool, 'Run $id', detail: _inputDetail(input));
    // Long transcodes/upscales must survive the user switching apps.
    await keepAliveHold(keepAliveTool, tool.meta.label);
    // Phase-2 hook: ML tools download/verify their model on first use.
    if (tool.model != null) {
      state = const JobRunning(message: 'Preparing model…');
      try {
        await tool.ensureReady();
      } catch (e, s) {
        final message = switch (e) {
          ToolException e => e.message,
          IncompatibleDeviceException e => e.message,
          _ => 'Could not prepare this tool.',
        };
        logError(logSourceTool, '$id could not prepare its model',
            error: e, stack: s);
        state = JobFailed(message);
        await _release();
        return;
      }
    }
    _sub = tool.run(input).listen(
      (p) {
        switch (p) {
          case ToolRunning(:final fraction, :final message):
            state = JobRunning(fraction: fraction, message: message);
          case ToolSucceeded(:final result):
            state = JobSuccess(result);
            logAction(logSourceTool,
                '$id finished \u00b7 ${result.files.length} file(s)',
                detail: [for (final f in result.files) f.name].join('\n'));
            getIt<HistoryRepository>().add(
              HistoryRecord(
                toolId: id,
                inputNames: [for (final f in input.files) f.name],
                outputPaths: [for (final f in result.files) f.path],
                createdAt: DateTime.now(),
              ),
            );
            _release();
          case ToolFailed(:final message):
            logError(logSourceTool, '$id failed', detail: message);
            state = JobFailed(message);
            _release();
        }
      },
      onError: (Object e, StackTrace s) {
        logError(logSourceTool, '$id failed', error: e, stack: s);
        state = JobFailed(
          e is ToolException ? e.message : 'Something went wrong: $e',
        );
        _release();
      },
      cancelOnError: true,
    );
  }

  /// Drops this run's claim on the process; the service stops when no other
  /// subsystem (a chat turn, a download) is still holding one.
  Future<void> _release() => keepAliveRelease(keepAliveTool);

  /// Cancels the stream subscription and discards any pending result.
  ///
  /// Phase 0 scope: this preempts the Dart stream only. True mid-computation
  /// cancellation of [runOffThread] is NOT implemented — csv→json completes in
  /// milliseconds; real preemption belongs to long-running engines (ffmpeg) in
  /// Phase 1.
  void cancel() {
    _sub?.cancel();
    _sub = null;
    logWarning(logSourceTool, 'Run stopped by the user');
    state = const JobCancelled();
    _release();
  }
}

/// Input files and params as log detail — names only, never file contents.
String? _inputDetail(ToolInput input) {
  final parts = <String>[
    for (final f in input.files) f.name,
    for (final e in input.params.entries)
      if (e.value != null && '${e.value}'.isNotEmpty) '${e.key}=${e.value}',
  ];
  return parts.isEmpty ? null : parts.join('\n');
}

final jobProvider = NotifierProvider.autoDispose<JobNotifier, JobState>(
  JobNotifier.new,
);
