import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/foreground_task.dart';
import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/chat_repository.dart';
import 'package:anvil/core/log_repository.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/settings_repository.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/llm_engine.dart';
import 'package:anvil/models/model_cache.dart';
import 'package:anvil/models/model_manager.dart';

/// Bridges get_it singletons into the widget tree and holds ephemeral UI state.
/// Tests override these (esp. [registryProvider]) via `ProviderScope(overrides:)`
/// so widget tests need no `getIt` init.

/// All registered tools. Overridden in tests.
final registryProvider = Provider<List<ToolModule>>(
  (_) => getIt<ToolRegistry>().all,
);

/// Current home-screen search query.
final searchQueryProvider = StateProvider<String>((_) => '');

/// Tools matching the current query (label/description substring, case-insensitive).
final filteredToolsProvider = Provider<List<ToolModule>>((ref) {
  final q = ref.watch(searchQueryProvider).trim().toLowerCase();
  final tools = ref.watch(registryProvider);
  if (q.isEmpty) return tools;
  return tools
      .where(
        (t) =>
            t.meta.label.toLowerCase().contains(q) ||
            t.meta.description.toLowerCase().contains(q),
      )
      .toList();
});

/// A file received via Android share intent, awaiting a tool selection.
final pendingSharedInputProvider = StateProvider<InputFile?>((_) => null);

/// Holds the app theme mode, persisted via [SettingsRepository].
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async =>
      state = await getIt<SettingsRepository>().getThemeMode();

  Future<void> set(ThemeMode m) async {
    await getIt<SettingsRepository>().setThemeMode(m);
    state = m;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Run history, newest first.
final historyProvider = FutureProvider<List<HistoryRecord>>(
  (_) => getIt<HistoryRepository>().all(),
);

/// Bottom-shell tab index: 0 Tools, 1 Ask, 2 Files, 3 Settings.
final homeTabProvider = StateProvider<int>((_) => 0);

/// Holds the results-retention window (days; 0 = forever), persisted via
/// [SettingsRepository]. Mirrors [ThemeModeNotifier].
class RetentionNotifier extends Notifier<int> {
  @override
  int build() {
    _load();
    return 30;
  }

  Future<void> _load() async =>
      state = await getIt<SettingsRepository>().getRetentionDays();

  Future<void> set(int days) async {
    await getIt<SettingsRepository>().setRetentionDays(days);
    state = days;
  }
}

final retentionProvider = NotifierProvider<RetentionNotifier, int>(
  RetentionNotifier.new,
);

/// Downloaded (cached) models, for the models storage screen.
final cachedModelsProvider = FutureProvider<List<CachedModel>>(
  (_) => getIt<ModelManager>().cachedModels(),
);

/// Total bytes used by the model cache.
final cacheBytesProvider = FutureProvider<int>(
  (_) => getIt<ModelManager>().totalCacheBytes(),
);

/// The full curated model catalog for the models screen.
final availableModelsProvider = FutureProvider<List<AvailableModel>>(
  (_) => getIt<ModelManager>().availableModels(),
);

/// The [ChatRepository] singleton, for the unified chat controller.
final chatRepositoryProvider = Provider<ChatRepository>(
  (_) => getIt<ChatRepository>(),
);

/// Chat-capable models for the picker: every catalog task flagged `chat`.
final chatModelsProvider = FutureProvider<List<AvailableModel>>(
  (_) async => (await getIt<ModelManager>().availableModels())
      .where((m) => m.chat)
      .toList(),
);

/// Cache/compat state for one task id, for tool-screen gating.
final modelStatusProvider = FutureProvider.family<ModelStatus, String>(
  (ref, taskId) => getIt<ModelManager>().status(taskId),
);

/// The LLM slot's load state (unloaded / loading / loaded), so any screen can
/// show that a multi-GB model is coming up instead of appearing frozen.
/// Seeded with the engine's current status so a late listener is never blank,
/// and re-emitted once a second while loading — the native load reports no
/// progress, so elapsed time is the only honest signal. Each tick is a fresh
/// object so riverpod's identity check propagates it.
final llmStatusProvider = StreamProvider<LlmStatus>((ref) {
  // Widget tests mount screens without a locator; an absent engine is simply
  // an empty slot, not an error.
  final engine =
      getIt.isRegistered<LlmEngine>() ? getIt<LlmEngine>() : null;
  if (engine == null) {
    return Stream.value(const LlmStatus(LlmPhase.unloaded));
  }
  final out = StreamController<LlmStatus>();
  Timer? tick;
  void push(LlmStatus s) {
    if (out.isClosed) return;
    out.add(s);
    tick?.cancel();
    tick = s.isLoading
        ? Timer.periodic(
            const Duration(seconds: 1),
            (_) => out.isClosed
                ? null
                : out.add(LlmStatus(s.phase, taskId: s.taskId, since: s.since)),
          )
        : null;
  }

  push(engine.status);
  final sub = engine.statusStream.listen(push);
  ref.onDispose(() {
    tick?.cancel();
    sub.cancel();
    out.close();
  });
  return out.stream;
});

/// The app log, newest first. Invalidate after clearing or to refresh.
final logEntriesProvider = FutureProvider<List<LogEntry>>(
  (_) => getIt<LogRepository>().recent(),
);

/// Entry/error tallies for the Settings row badge.
final logCountsProvider = FutureProvider<({int total, int errors})>(
  (_) => getIt<LogRepository>().counts(),
);

/// In-flight download state for one task: [fraction] in 0..1 (null = size
/// unknown / indeterminate), or a terminal [error] message.
class ModelDownloadState {
  final double? fraction;
  final String? error;
  const ModelDownloadState({this.fraction, this.error});

  bool get isDownloading => error == null;
}

/// Tracks per-task model downloads triggered from the catalog. A task with no
/// entry is idle; entries are removed on success and kept (with [error]) on
/// failure until retried.
class ModelDownloadsNotifier extends Notifier<Map<String, ModelDownloadState>> {
  @override
  Map<String, ModelDownloadState> build() => const {};

  Future<void> download(String taskId) async {
    if (state[taskId]?.isDownloading ?? false) return;
    state = {...state, taskId: const ModelDownloadState(fraction: 0)};
    // A multi-GB download must survive the user switching apps.
    await keepAliveHold(keepAliveDownload, 'Downloading a model');
    logAction(logSourceModel, 'Downloading model $taskId');
    try {
      await getIt<ModelManager>().ensureReady(
        ModelSpec(taskId: taskId),
        onProgress: (received, total) {
          state = {
            ...state,
            taskId: ModelDownloadState(
              fraction: total > 0 ? received / total : null,
            ),
          };
        },
      );
      state = {...state}..remove(taskId);
      await keepAliveRelease(keepAliveDownload);
      logAction(logSourceModel, 'Model $taskId ready on this device');
      ref.invalidate(availableModelsProvider);
      ref.invalidate(cachedModelsProvider);
      ref.invalidate(cacheBytesProvider);
      ref.invalidate(modelStatusProvider(taskId));
    } catch (e, s) {
      logError(logSourceModel, 'Model $taskId download failed',
          error: e, stack: s);
      await keepAliveRelease(keepAliveDownload);
      state = {...state, taskId: ModelDownloadState(error: e.toString())};
    }
  }

  /// Imports a user-picked local model file for [taskId] (verified against the
  /// manifest checksum) instead of downloading. Shares the per-task busy/error
  /// state with [download] so the gate UI is identical.
  Future<void> import(String taskId, String sourcePath) async {
    if (state[taskId]?.isDownloading ?? false) return;
    state = {...state, taskId: const ModelDownloadState(fraction: null)};
    logAction(logSourceModel, 'Importing model $taskId');
    try {
      await getIt<ModelManager>().importModel(taskId, sourcePath);
      state = {...state}..remove(taskId);
      logAction(logSourceModel, 'Model $taskId imported and verified');
      ref.invalidate(availableModelsProvider);
      ref.invalidate(cachedModelsProvider);
      ref.invalidate(cacheBytesProvider);
      ref.invalidate(modelStatusProvider(taskId));
    } catch (e, s) {
      logError(logSourceModel, 'Model $taskId import failed',
          error: e, stack: s);
      state = {...state, taskId: ModelDownloadState(error: e.toString())};
    }
  }

  void clearError(String taskId) => state = {...state}..remove(taskId);
}

final modelDownloadsProvider =
    NotifierProvider<ModelDownloadsNotifier, Map<String, ModelDownloadState>>(
  ModelDownloadsNotifier.new,
);

/// Newest run, for the Home resume card. Null when history is empty/loading.
final resumeProvider = Provider<HistoryRecord?>(
  (ref) => ref.watch(historyProvider).asData?.value.firstOrNull,
);

/// Up to 3 sibling tools in the same category as the most recent run's tool,
/// excluding that tool. Empty when there is no history or the tool is unknown.
final suggestionsProvider = Provider<List<ToolModule>>((ref) {
  final record = ref.watch(resumeProvider);
  if (record == null) return const [];
  final tool = getIt<ToolRegistry>().byId(record.toolId);
  if (tool == null) return const [];
  final siblings = getIt<ToolRegistry>()
      .byCategory(tool.meta.category)
      .where((t) => t.meta.qualifiedId != tool.meta.qualifiedId)
      .toList();
  return siblings.take(3).toList();
});
