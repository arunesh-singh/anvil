# Repository Guidelines

## Project Overview
Anvil (working codename) is a Flutter, Android-first mobile app that replicates ~85% of [TinyWow](https://tinywow.com)'s 259-tool catalog **fully on-device** — offline, private, zero per-use cost. Scope: 219/259 tools across PDF, image, video/audio, file-conversion, and on-device AI, plus an on-device LLM agent that drives tools by natural language.

> **Status: IN DEVELOPMENT.** Flutter app scaffolded (`pubspec.yaml`, `lib/`, `test/`, `android/`). Phase status is tracked in PLAN.md. The specs are the contract.

## Repository Layout (current)
```
README.md            Entry point + reading order
DECISIONS.md         Locked product/tech decisions (D1–D7) — read first, do not relitigate
PLAN.md              Phased roadmap (Phase 0 → 3), effort, sequencing
ARCHITECTURE.md      Tool-registry pattern, engine abstraction, agent design
STACK.md             Flutter packages, versions, setup gotchas
MODEL_DELIVERY.md    Phase 2 model manifest / download / verify / cache spec
TOOL_CATALOG.md      All 259 tools → bucket + engine (generated)
RISKS.md             Dependency/legal/perf risks (R1–R10) + mitigations
data/
  tinywow_catalog.json      Raw scrape: { counts, tools: {category:[urls]} }, 259 URLs
  tool_classification.json  Derived: { summary, tools:[{category,slug,bucket,engine,url}] }
```
**Read order for any task:** `DECISIONS.md` → `PLAN.md` → `ARCHITECTURE.md` → `STACK.md` → (`MODEL_DELIVERY.md` / `TOOL_CATALOG.md` / `RISKS.md` as needed).

## Data Model (the catalog)
- `data/tinywow_catalog.json` — raw TinyWow scrape (Scrapling, 2026-06-20). Shape: `{ counts: {pdf:47, image:81, write:54, video:59, converter:18}, tools: {category: [url]} }`. URLs are `https://tinywow.com/{category}/{slug}`. Pure URLs, no engine metadata.
- `data/tool_classification.json` — **derived from** the raw scrape. Shape: `{ summary, tools: [...] }`. Each record: `{category, slug, bucket, engine, url}`.
  - Example: `{category:"converter", slug:"csv-to-excel", bucket:"ONDEVICE-DET", engine:"dart-libs", url:"..."}`
- `TOOL_CATALOG.md` consumes both and tables tools by bucket × category.
- **Buckets** partition by execution mode: `ONDEVICE-DET` (140, Phase 1), `ONDEVICE-ML` (23, Phase 1.5), `ONDEVICE-LLM` (56, Phase 3), `DEFERRED-CLOUD` (33, post-v1), `DROPPED` (7, social — Play policy/legal).

## Architecture & Data Flow (intended `lib/`)
Pluggable **tool-registry** pattern (ported as *patterns, not code* from Google AI Edge Gallery's Kotlin `CustomTask`). A 219-tool app is never a giant switch — every tool self-registers as a `ToolModule` with metadata + engine + optional model + UI + function schema. Home grid, search, and the Phase-3 agent all read the **same registry**.

```
lib/
  core/      registry, DI, isolate runner, file IO, share intents, result model
  engines/   pdf/ image/ ffmpeg/ mlkit/ onnx/ asr/ llm/ dartlib/  (one executor each)
  models/    manifest loader, downloader, sha256 verifier, versioned cache, device gating
  tools/     one ToolModule per tool, grouped by category (pdf/ image/ video/ file/ write/)
  agent/     Phase 3: gemma runtime, tool-call loop, arg validation, chain executor
  ui/        home grid, search, tool screen scaffold, settings, history
```

Data flow: **registry → engine executor → result → save/share**. The Phase-3 agent path: `NL request → Gemma 4 E2B (function calling) → arg validator (against fnSchema) → engine executor → result → next step/done`.

## Key Patterns (apply when coding)
- **`ToolModule` is the unit of work.** Every tool implements:
  ```dart
  abstract class ToolModule {
    ToolMeta   get meta;        // id, category, label, icon, description, tinywow slug
    EngineKind get engine;      // dartlib|pdf|image|ffmpeg|mlkit|onnx|asr|llm
    ModelSpec? get model;       // null for deterministic (Phase 1); set for ML/LLM
    Map<String, dynamic> get fnSchema;        // JSON-schema {name, description, params}
    Future<void> ensureReady();               // trigger model download (Phase 2)
    Stream<ToolProgress> run(ToolInput input);// streamed progress + result
    Widget buildScreen(BuildContext context); // tool detail UI
  }
  ```
- **DI auto-discovery:** bind each module into a `Set<ToolModule>` via `get_it`/`riverpod` (mirrors Gallery's Hilt `@IntoSet`). Never hand-maintain a tool list.
- **`EngineKind` selects the executor.** A tool body NEVER imports a plugin directly. Each executor implements a tiny common contract — `prepare()` / `execute(input) -> Stream<ToolProgress>` / `dispose()` — so the FFmpeg fork can be swapped in one file (D4).
- **Heavy `run()` work goes in an isolate** (`compute` / `Isolate.run`). The UI thread never blocks; progress is streamed with cancel support.
- **Phase-3 agent: validate every tool-call's args against `fnSchema` before executing.** A 2B model hallucinates args — never run unvalidated. Guided chains only (Tier 3a single-tool, 3b 2–3 step, validated steps auto-execute); no full autonomy, no cloud planner.
- **No cloud in v1** (D5). Everything on-device; cloud-only tools are deferred, not stubbed.

## Engines → Packages (STACK.md)
| EngineKind | Package | Phase | Note |
|---|---|---|---|
| `dartlib` | `csv`,`xml`,`excel_community` (pure Dart) | 1 | converters |
| `pdf` | `pdfrx` + `pdf` + native channel | 1 | D3: no Syncfusion; native = PdfBox-Android/PdfRenderer |
| `image` | native platform-channel + `flutter_image_compress` | 1 | pure-Dart `image` too slow |
| `ffmpeg` | `ffmpeg_kit_flutter` (sk3llo **LGPL** fork) | 1 | D4: no fallback v1; isolate behind interface |
| `mlkit` | `google_mlkit_subject_segmentation` / `_text_recognition` | 1.5 | remove-bg, OCR |
| `onnx` | `onnxruntime` | 1.5 | upscale/inpaint/colorize; models via Phase 2 |
| `asr` | `sherpa_onnx` | 1.5 | transcription, VAD |
| `llm` | `flutter_gemma` (Gemma 4 E2B) | 3 | write tools + agent |

Support packages: DI/state `get_it`+`riverpod`; pick/share `file_picker`,`share_plus`,`receive_sharing_intent`; download `dio` (range/resume); hashing `crypto` (sha256); storage `path_provider`,`sqflite`/`drift`.

## Runtime / Tooling Preferences
- **Flutter, Android-first** (D1). `minSdk 26+` recommended for ML/NPU. ONNX/Gemma need >2 GB RAM → device-gated.
- **Flutter stable** for the app; **master channel required only for Phase 3** `flutter_gemma` (`--enable-experiment=native-assets`).
- iOS (parity later): manual `Podfile` linking MediaPipe `MediaPipeTasksGenAI` for Phase 3.
- FFmpeg: use the **LGPL** (non-GPL, `min-gpl`-free) fork build; prefer royalty-free codecs (VP9/Opus/WebP); pin the exact fork version (R1).

## Development Commands (once scaffolded)
No build system exists yet. After `flutter create` scaffolds the project, standard commands apply:
```bash
flutter pub get                 # install deps
flutter analyze                 # static analysis / lint (analysis_options.yaml)
flutter test                    # unit/widget tests (test/)
dart format .                   # formatting
flutter run -d <device>         # run on Android device/emulator
flutter build apk               # release build
# Phase 3 only (flutter_gemma): Flutter master channel +
flutter run --enable-experiment=native-assets
```

## Code Conventions
- **Dart/Flutter standard style:** `dart format` (2-space indent); files `snake_case.dart`; types `PascalCase`; members/vars `lowerCamelCase`; constants `lowerCamelCase`.
- **Tool layout:** one `ToolModule` subclass per tool under `lib/tools/<category>/`; tool `id` matches its TinyWow `slug` from `tool_classification.json`.
- **Errors/async:** stream progress + failures through `Stream<ToolProgress>`; surface device-incapability as a graceful "needs a more capable device" state, not a crash (R5). Cancellable jobs.
- **No second convention:** reuse the registry/executor/isolate pattern above; do not introduce a parallel mechanism beside it.

## Model Delivery (Phase 2, MODEL_DELIVERY.md)
On-demand only for `ONDEVICE-ML` tools. Flow: `tool.ensureReady()` → fetch curated **manifest** (ETag-cached) → resolve `task_id` to a device-gated **variant** (`fast`|`quality` by RAM/accelerator) → resumable download (`dio` range) → **sha256 verify** → unpack → versioned cache → load (`onnxruntime`/`sherpa_onnx`/`flutter_gemma`). Manifest variant fields: `id, tier, url, sha256, sizeBytes, runtime, minRamGb, accelerator, version`. No variant meets device limits → tool disabled with a message. LRU eviction + manual storage manager; offline once cached. "Best model" = WE curate it offline; the app selects a variant, it does not auto-discover models.

## Testing & QA
- Framework: `flutter_test` (unit + widget); `test/` mirrors `lib/`.
- **Run only tests you add/modify** unless asked otherwise. Test behavior, not plumbing: tool input→output correctness, arg-validation rejection of bad args, device-gating disable path, chain step hand-off.
- **Acceptance gates per phase** (PLAN.md) are the QA bar: P0 = csv→json runs end-to-end through registry→engine→result→share; P1 = PDF+image usable as a standalone toolkit (first RC); P1.5 = remove-bg+OCR+one upscale on mid-range Android; P3 = "compress this PDF and convert to grayscale" → agent chains two tools unattended.
- Early de-risking spikes before committing: Phase 1 FFmpeg fork build + PDF native ops; Phase 3 `flutter_gemma` integration (R1, R6).

## Key Risks to Respect (RISKS.md)
- **R1 (High):** `ffmpeg_kit_flutter` upstream retired Jan 2025 → use sk3llo fork, isolate behind executor, pin version.
- **R3 (High):** FunctionGemma 270M ≈58% tool-calling accuracy → primary is Gemma 4 E2B + mandatory arg validation + guided chains.
- **R8:** `pdfrx` lacks compress/encrypt → do those via native platform-channel (PdfBox-Android).
- Also: codec patents (R2, prefer royalty-free), model size (R4, on-demand+LRU), device floor (R5, gate+disable), `flutter_gemma` setup friction (R6), thermal/battery on video (R7, cap length/resolution).
