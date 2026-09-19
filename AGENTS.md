# Repository Guidelines

## Project Overview

Anvil is a **Flutter, Android-only** toolkit that runs ~85% of [TinyWow](https://tinywow.com)'s 259-tool catalog **fully on-device** — offline, private, zero per-use cost — plus an on-device LLM assistant that drives those tools by natural language. 220 tools are registered today (`test/registry_test.dart:63`): 11 converter, 34 pdf, 69 image, 52 video, 54 write.

Shipped: Phase 0 (registry/DI/shell), Phase 1 (deterministic tools), Phase 1.5 (ML tools), Phase 2 (model delivery), Phase 3 (agent). Current version `1.0.0-rc.1+3` (`pubspec.yaml:19`).

Locked decisions live in `DECISIONS.md` (D1–D7) — **do not relitigate**: Flutter/Android-first (D1), no Syncfusion (D3), LGPL ffmpeg fork with no v1 fallback (D4), **no cloud in v1** (D5), guided agent chains only (D6), codename Anvil (D7). D6 was amended 2026-09-19: **the confirm gate is gone** — a validated tool call executes immediately; Stop is the only brake. Code referring to a "confirm step" is stale comment text, not behaviour.

Doc reading order for deeper context: `DECISIONS.md` → `PLAN.md` → `ARCHITECTURE.md` → `STACK.md` → (`MODEL_DELIVERY.md` / `TOOL_CATALOG.md` / `RISKS.md`).

## Architecture & Data Flow

**One registry, one executor per engine, one isolate boundary.** A 220-tool app is never a switch statement: each tool is a `ToolModule` that declares metadata, an `EngineKind`, an optional `ModelSpec`, and a function schema. The home grid, search, and the agent all read the same `ToolRegistry`.

```
Tool run:   UI → JobNotifier.start(tool, input) → tool.ensureReady() (model gate)
                → tool.run(ToolInput) → Stream<ToolProgress> → JobState → result/share/history

Agent turn: ChatController.send(text)
                → busy=true + persist user turn  (BEFORE the slow model load)
                → ModelManager.ensureReady(taskId) → LlmEngine.ensureLoaded(...)
                → shortlistTools(request, limit 6) → AgentSession(chat, tools, availableFiles)
                → LlmChat stream → LlmToolCall → validateCall(...) → AgentToolCall
                → _runStep executes the tool → output becomes next step's availableFiles
                → repeat up to _maxChainSteps (5) → AgentDone
```

Layering is strict and one-directional: `lib/core` ← `lib/engines` + `lib/models` + `lib/tools` ← `lib/agent` + `lib/ui`. A tool body **never imports a plugin**; it goes through its engine (`lib/engines/*_engine.dart`). `lib/agent/**` never imports `flutter_gemma` — it talks to the `LlmChat` seam (`lib/engines/llm_chat.dart`), which is why the whole agent loop is host-testable.

Key invariants:
- **`LlmEngine` holds exactly one model.** `ensureLoaded` coalesces concurrent calls (same config joins the in-flight load, a different one queues); `unload()` queues behind an in-flight load — tearing down mid-create is a native crash. Transitions broadcast on `statusStream` as `LlmStatus(LlmPhase.unloaded|loading|loaded, taskId, since)`.
- **Heavy pure-Dart work goes through `runOffThread` (`lib/core/isolate_runner.dart`)**; only sendable values may be captured (no `getIt`, `File`, widgets).
- **Long jobs hold the process up.** `ForegroundKeepAlive` (`lib/core/foreground_task.dart`) starts an Android `dataSync` foreground service so a chat turn, transcode, or model download survives the user switching apps.

## Key Directories

| Path | Purpose |
|---|---|
| `lib/core/` | `tool_module.dart` (the contract), `registry.dart` (`buildTools()`), `di.dart` (get_it wiring), `tool_io.dart`, `fn_schema.dart`, `isolate_runner.dart`, `app_log.dart`, `foreground_task.dart`, sqflite repositories (history/settings/log/chat) |
| `lib/engines/` | One executor per `EngineKind`: `pdf_engine`, `image_engine`, `ffmpeg_engine`, `mlkit_engine`, `onnx_engine`, `asr_engine`, `llm_engine` (+ `llm_chat.dart` seam) |
| `lib/models/` | Phase-2 delivery: `manifest*.dart`, `downloader.dart`, `model_cache.dart`, `device_caps.dart`, `model_manager.dart` |
| `lib/tools/<category>/` | `ToolModule` implementations + a `build*Tools()` list per file |
| `lib/agent/` | `agent_session.dart` (tool-call loop), `arg_validator.dart`, `tool_shortlist.dart`, `chain_prompt.dart`, `attachment_ingest.dart` |
| `lib/ui/` | `providers.dart` (riverpod), `agent/` (chat), `tool/` (+ `editors/` WYSIWYG screens), `home/`, `settings/`, `widgets/` (`slab.dart`, `model_gate.dart`, `llm_memory_panel.dart`), `tokens.dart` |
| `android/app/src/main/kotlin/com/arunesh/anvil/` | Platform channels: `ImageChannel` (`anvil/image`), `PdfChannel` (`anvil/pdf`), `ForegroundChannel` (`anvil/foreground`), `KeepAliveService` |
| `test/`, `integration_test/` | 30 host tests mirroring `lib/`, 1 on-device smoke test |
| `data/`, `assets/manifest.json` | TinyWow catalog + classification JSON; curated model manifest (bundled, v4) |

## Development Commands

```bash
flutter pub get
flutter analyze                       # must be clean; flutter_lints, android/ excluded
dart format .
flutter test                          # full host suite (~264 tests, ~35 s)
flutter test test/chat_chain_test.dart --plain-name "a cold model"   # one test
flutter run -d <device>
flutter build apk --release           # signs with android/key.properties, else debug keys
flutter test integration_test -d <device>                             # on-device smoke, needs models
flutter test --dart-define=ANVIL_REQUIRE_MODELS=true integration_test -d <device>  # QA gate: fail, don't skip
```

There is no CI, no Makefile, and no scripts directory — these commands are the whole toolchain. The release APK is ~546 MB (universal, all ABIs and native runtimes); Play requires `--split-per-abi` or an app bundle before store submission.

## Code Conventions & Common Patterns

**Formatting/naming.** `dart format` (2-space); `snake_case.dart` files, `PascalCase` types, `lowerCamelCase` members, private helpers prefixed `_`. Every library starts with a `///` doc comment block ending in `library;` that states *why* the file exists (see `lib/engines/llm_engine.dart:1`). Imports are grouped `dart:` → `package:` third-party → `package:anvil/…`, alphabetical within a group. Non-obvious decisions get an inline comment naming the constraint (e.g. the `maxTokens` rationale at `lib/engines/llm_engine.dart`).

**Adding a tool** — the single most common change:
1. Subclass `BaseToolModule` in `lib/tools/<category>/…` (defaults: `model` null, `fnSchema` = `fnSchemaFor(meta)`, `ensureReady` no-op, `fileSetError` null). Most files already have a reusable shape to extend — `_PdfToPdf`, `_ManyToPdf`, `_PureConvert`, `_Generator`, `_TextToText`.
2. `meta.id` **must equal the TinyWow slug** (`data/tool_classification.json`); `qualifiedId` is `<category>/<id>` and must be unique.
3. `run()` yields zero or more `ToolRunning(fraction?, message?)` then exactly one `ToolSucceeded(ToolResult(...))`; throw `ToolException('user-facing message')` for failures.
4. Append it to the file's `build*Tools()` list — `buildTools()` in `lib/core/registry.dart` is the one canonical list; never hand-maintain a second one.
5. Set `agentCallable: false` for tools whose real input comes from a WYSIWYG editor, and implement `fileSetError` for combinations extensions cannot express (e.g. "one PDF plus one image"). Extension checks belong in `acceptedExtensions`, not `fileSetError`.

**DI split.** `getIt` (`lib/core/di.dart`) holds lifecycle-free singletons: DB, repositories, services, engines, `ModelManager`, `ToolRegistry`, `ForegroundKeepAlive`. Riverpod holds ephemeral UI state (`lib/ui/providers.dart`). Tool bodies resolve engines via `getIt<XEngine>()`; widgets read providers.

**Riverpod usage.** `Provider` for derived lists (`filteredToolsProvider`), `FutureProvider` for cached async reads (`availableModelsProvider`, `modelStatusProvider(taskId)`), `StreamProvider` for live state (`llmStatusProvider` — re-emits every second while loading so the UI can show elapsed time), `Notifier` for logic (`ChatController` non-autoDispose so chat survives tab switches; `JobNotifier` autoDispose). After mutating model state you must `ref.invalidate` the dependent providers — see `ModelDownloadsNotifier.download` in `lib/ui/providers.dart`.

**Optional-singleton accessor pattern.** Cross-cutting services that must never break a caller degrade to no-ops when unregistered: `_log()` in `lib/core/app_log.dart` and `_service()` in `lib/core/foreground_task.dart`. Call them through the top-level helpers (`logAction`/`logWarning`/`logError`, `keepAliveHold`/`keepAliveRelease`) — never `getIt<AppLog>()` directly.

**Keep-alive holds** are per-owner and idempotent (`keepAliveChat`, `keepAliveTool`, `keepAliveDownload`); every hold needs a matching release on *every* terminal path, including cancel and error.

**Errors/async.** User-facing failures are `ToolException`; `JobNotifier` (`lib/ui/tool/job_controller.dart`) is the single place thrown errors become `JobFailed`. Sealed classes + exhaustive `switch` pattern matching everywhere (`ToolProgress`, `JobState`, `LlmEvent`, `AgentEvent`) — no `default:` arms. Device incapability surfaces as a disabled "needs a more capable device" panel (`lib/ui/widgets/model_gate.dart`), never a crash.

**UI.** Colours only via `Theme.of(context).extension<AnvilColors>()!`, radii from `AnvilRadii`, monospace via `AnvilText.mono` (`lib/ui/tokens.dart`); compose from `lib/ui/widgets/slab.dart` (`SlabPanel`, `ToolRow`, `PrimaryButton`, `SecondaryButton`, `IconChip`, `InfoCard`, `formatBytes`). Model labels come from `modelTaskInfo`/`modelTaskLabel` in `model_gate.dart` — one source, no per-screen label maps.

**Agent specifics.** The model addresses tools by `fnNameFor(meta)` (`pdf/add-images` → `pdf_add_images`); `AgentSession._resolve` also accepts normalized and bare-slug drift, but two tools normalizing identically are dropped from loose lookup. Every call passes `validateCall` before it runs (R3: a 2B model hallucinates args); invalid calls are fed back for repair within the repair budget. Shortlist is capped at 6 tools per step and chains at 5 steps to fit the KV budget.

## Important Files

- `lib/main.dart` — bootstrap: `registerNativeLicenses()` → `configureDependencies()` → error capture → `pruneExpiredHistory()` → `runApp`.
- `lib/core/tool_module.dart` — the real `ToolModule`/`BaseToolModule`/`ToolMeta` contract (ground truth over any doc sketch; there is deliberately **no** `buildScreen` member).
- `lib/core/registry.dart`, `lib/core/di.dart` — tool discovery and singleton wiring.
- `lib/engines/llm_engine.dart` + `lib/engines/llm_chat.dart` — the only files touching `flutter_gemma`.
- `lib/ui/agent/chat_controller.dart` — chain loop, model-load ordering, keep-alive holds, `unloadModel()`.
- `assets/manifest.json` — curated model catalog (variants: `id, tier, url, sha256, sizeBytes, runtime, minRamGb, accelerator, supportsImage, family, maxTokens, version`). `kModelManifestUrl = null` in `di.dart`, so v1 uses the bundled manifest only.
- `android/app/build.gradle.kts`, `android/gradle.properties`, `android/app/src/main/AndroidManifest.xml` — build and platform config (see below).
- `data/tool_classification.json` — `{category, slug, bucket, engine, url}` per tool; buckets `ONDEVICE-DET|ONDEVICE-ML|ONDEVICE-LLM|DEFERRED-CLOUD|DROPPED`.

## Runtime/Tooling Preferences

- **Flutter stable + Dart SDK `^3.12.1`**; `pub` is the package manager. Android-only: there is no `ios/`, `web/`, or desktop directory.
- `minSdk 26`, `compileSdk = maxOf(flutter.compileSdkVersion, 37)` (forced by `receive_sharing_intent` 1.9.0), JVM 17, AGP 9.0.1, Kotlin 2.3.20, Gradle 9.1.0.
- **Do not flip `android.r8.strictFullModeForKeepRules` back to true** (`android/gradle.properties`): AGP 9's strict mode breaks ML Kit's AGP-8-era consumer keep rules and crashes OCR/segmentation in minified release builds.
- `packaging.jniLibs.pickFirsts = **/libonnxruntime.so` resolves the `onnxruntime` vs `sherpa_onnx` duplicate; `third_party/flutter_avif_android` is a vendored override dropping a duplicate plugin class. Both are load-bearing.
- Dependencies carry inline rationale in `pubspec.yaml` — honour it: `excel_community` (not `excel`), `ffmpeg_kit_flutter_new_full` LGPL fork pinned (R1), royalty-free codecs only (mpeg4/aac, vp9/opus — no x264/AV1 via ffmpeg; AVIF via `flutter_avif`), `flutter_gemma` 1.8.2 + `flutter_gemma_litertlm` 1.6.3.
- Adding a platform channel means touching three places: the Kotlin object, `MainActivity.configureFlutterEngine`, and (for services/permissions) `AndroidManifest.xml`. `android/**` is excluded from the Dart analyzer.

## Testing & QA

- `flutter_test` + `sqflite_common_ffi`; `test/` mirrors `lib/`. Run the tests you touch; run the full suite before declaring done (it takes ~35 s).
- **Host-test harness:** `sqfliteFfiInit()`, `databaseFactory = databaseFactoryFfi`, `inMemoryDatabasePath` with a hand-written `CREATE TABLE` in `setUp`, `getIt.registerSingleton<…>` per dependency, `await getIt.reset()` in `tearDown`. Logic tests use a bare `ProviderContainer()` + `addTearDown(container.dispose)`; widget tests use `ProviderScope(overrides: […])`.
- **Fakes:** engines that reach native code are faked with `implements X` + `noSuchMethod` forwarding (`_FakeLlmEngine`, `_FakePdfEngine`, `_FakeMlKit`, `_FakeOnnx`, `_FakeAsr`, `_FakeFfmpeg`) — see the comment at `test/write_tools_test.dart:19`. `extends` is only for controllers with a safe base (`_FakeChatNotifier`). The agent loop is driven by scripted `LlmEvent` lists through `_ScriptedChat`.
- **Widget tests** must override `modelStatusProvider(ChatSession.defaultModelTaskId)`, `availableModelsProvider`, and (when the LLM status is read) `llmStatusProvider`; screens with spinners need `pump()` + a fixed duration, never `pumpAndSettle()`. Async controller state is awaited with the `settle(container, cond)` polling helper in `test/chat_chain_test.dart`.
- **Test bar:** assert observable behaviour (page counts, PNG magic bytes, ffmpeg arg lists, state transitions, validation rejections, device-gating disable paths), not plumbing. A regression test must fail before the fix — e.g. the cold-model test in `chat_chain_test.dart` fails if the model load is moved back ahead of persisting the user turn. Avoid pinning UI wording beyond what a user actually depends on.
- **Not testable on host:** flutter_gemma FFI, the PDF Rust plugin, ffmpeg execution, ML Kit, ONNX Runtime. Those are covered by `integration_test/device_smoke_test.dart`, which skips missing models unless `ANVIL_REQUIRE_MODELS=true`.
- **Phase acceptance gates** (`PLAN.md`) are the QA bar; the Phase-3 gate is "compress this PDF and convert to grayscale" chaining two tools end-to-end on a device.
