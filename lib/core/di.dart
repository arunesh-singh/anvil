import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_gemma/flutter_gemma.dart' show FlutterGemma;
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/database.dart';
import 'package:anvil/core/chat_repository.dart';
import 'package:anvil/core/export_service.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/log_repository.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/settings_repository.dart';
import 'package:anvil/core/share_service.dart';
import 'package:anvil/engines/asr_engine.dart';
import 'package:anvil/engines/ffmpeg_engine.dart';
import 'package:anvil/engines/image_engine.dart';
import 'package:anvil/engines/llm_engine.dart';
import 'package:anvil/engines/mlkit_engine.dart';
import 'package:anvil/engines/onnx_engine.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/models/device_caps.dart';
import 'package:anvil/models/downloader.dart';
import 'package:anvil/models/manifest_loader.dart';
import 'package:anvil/models/model_cache.dart';
import 'package:anvil/models/model_manager.dart';

/// v1 ships the curated catalog inside the app (`assets/manifest.json`); no
/// Anvil-controlled CDN exists, so no remote catalog is configured and the
/// app never calls out for one. Set this to a real HTTPS URL to turn on
/// ETag-cached remote updates.
const String? kModelManifestUrl = null;

/// Global service locator. Holds lifecycle-free singletons (DB, repos, services,
/// tool registry). Ephemeral UI state lives in riverpod, not here.
final getIt = GetIt.instance;

/// Wires up all singletons. Call once during app bootstrap before `runApp`.
Future<void> configureDependencies() async {
  // Phase 3: flutter_gemma's EngineRegistry starts empty — without an opt-in
  // inference engine the first createModel throws. `.litertlm` bundles are
  // served by the LiteRT-LM FFI engine.
  await FlutterGemma.initialize(inferenceEngines: const [LiteRtLmEngine()]);
  final db = await openAnvilDatabase();
  final support = await getApplicationSupportDirectory();
  getIt
    ..registerSingleton<Database>(db)
    ..registerLazySingleton<HistoryRepository>(
      () => HistoryRepository(getIt<Database>()),
    )
    ..registerLazySingleton<SettingsRepository>(
      () => SettingsRepository(getIt<Database>()),
    )
    ..registerLazySingleton<LogRepository>(
      () => LogRepository(getIt<Database>()),
    )
    ..registerLazySingleton<AppLog>(() => AppLog(getIt<LogRepository>()))
    ..registerLazySingleton<ChatRepository>(
      () => ChatRepository(getIt<Database>()),
    )
    ..registerLazySingleton<FileService>(FileService.new)
    ..registerLazySingleton<ShareService>(ShareService.new)
    ..registerLazySingleton<ExportService>(ExportService.new)
    ..registerLazySingleton<PdfEngine>(PdfEngine.new)
    ..registerLazySingleton<ImageEngine>(ImageEngine.new)
    ..registerLazySingleton<FfmpegEngine>(FfmpegEngine.new)
    ..registerLazySingleton<MlKitEngine>(MlKitEngine.new)
    ..registerLazySingleton<OnnxEngine>(OnnxEngine.new)
    ..registerLazySingleton<AsrEngine>(AsrEngine.new)
    ..registerLazySingleton<LlmEngine>(LlmEngine.new)
    ..registerLazySingleton<ModelManager>(
      () {
        final dio = Dio();
        return ModelManager(
          loader: ManifestLoader(
            dio: dio,
            cacheDir: Directory(p.join(support.path, 'anvil', 'manifest')),
            manifestUrl: kModelManifestUrl,
            bundledManifest: () => rootBundle.loadString('assets/manifest.json'),
          ),
          downloader: ModelDownloader(dio: dio),
          cache: ModelCache(
            baseDir: Directory(p.join(support.path, 'anvil')),
          ),
          capsProvider: const ProcMeminfoDeviceCapsProvider(),
        );
      },
    )
    ..registerSingleton<ToolRegistry>(ToolRegistry(buildTools()));
  logAction(logSourceApp,
      'App started \u00b7 ${getIt<ToolRegistry>().all.length} tools registered');
}

/// Enforces the retention setting: deletes history rows (and their output
/// files) older than the configured window. `0` days = keep forever (no-op).
/// Call once at startup after [configureDependencies].
Future<void> pruneExpiredHistory() async {
  final days = await getIt<SettingsRepository>().getRetentionDays();
  if (days <= 0) return;
  final cutoff = DateTime.now().subtract(Duration(days: days));
  final removed = await getIt<HistoryRepository>().pruneOlderThan(cutoff);
  await getIt<FileService>().deletePaths([
    for (final r in removed) ...r.outputPaths,
  ]);
  if (removed.isNotEmpty) {
    logAction(logSourceApp,
        'Retention cleared ${removed.length} old results (older than $days days)');
  }
}
