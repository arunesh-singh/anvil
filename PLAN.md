# Roadmap

Phased plan for Anvil. Sequencing favors shipping a usable app early (PDF + image), then layering ML and the agent. Effort = solo / small team.

## Phase 0 — Foundation (~2–3 wk) — ✅ COMPLETE (2026-07-03)
The app shell. No tools yet.
- Tool **registry + DI** (`ToolModule` interface — see ARCHITECTURE.md), auto-discovery into the home grid.
- Home (category grid + search), file-picker + Android share-intent ingest, result view (save/share-out), job-progress UI with cancel.
- Isolate runner: all heavy work off the UI thread (`compute`/isolates), streamed progress.
- Theming (light/dark), settings, "My Files" local history (no cloud).
- **Acceptance:** one trivial tool (e.g. csv→json) runs end-to-end through registry → engine → result → share.
- **Status:** shipped. Registry+DI, home grid+search, picker+share-intent, result view, job progress w/ cancel, isolate runner, theming/settings/history all in `lib/`. Acceptance verified: `test/csv_to_json_test.dart` runs csv→json end-to-end through registry → engine → result (40/40 tests green, `flutter analyze` clean).

## Phase 1 — Deterministic on-device tools (~6–8 wk) — 140 tools — ✅ COMPLETE (2026-07-04)
Build order (each block independently shippable). (Counts reclassified 2026-07-03 — see TOOL_CATALOG.md.)
1. **Converters (11)** — `csv`/`xml`/`excel` Dart libs. Warm-up, zero risk.
2. **PDF (32)** — `pdfrx` (render) + `pdf` (create) + native channels for merge/split/compress/rotate/encrypt/unlock/watermark/extract-text. (D3: no Syncfusion.)
3. **Image deterministic (50)** — native platform-channel (Android Bitmap / later iOS) for resize/crop/compress/flip/grayscale/border/rotate + format convert (jpg/png/webp/heic); `flutter_image_compress` where it fits; exotic codecs (tiff/psd/gif) via pure-Dart `image`; avif/apng via ffmpeg engine.
4. **Video/audio (47)** — `ffmpeg_kit_flutter_new_full` LGPL fork (D4): compress/cut/mute/extract-audio/to-gif/format-convert. Thermal + length caps on free tier.
- **Acceptance:** PDF + image blocks usable as a standalone "PDF & photo toolkit" — this is the **first public release candidate**.
- **Status:** shipped. All 140 DET tools registered (11 converters, 32 pdf, 50 image, 47 video) through the single registry; engines: pdf_manipulator (Rust), Kotlin `anvil/image` bitmap channel, pure-Dart `image` codecs, `ffmpeg_kit_flutter_new_full` (LGPL, mpeg4/vp9/opus policy — no x264/AV1), `flutter_avif` (rav1e) for AVIF encode, WebView-print channel for URL→PDF. Verified: `flutter analyze` clean, 105/105 host tests (engine round-trips incl. protect/unlock, codecs, ffmpeg arg builders, registry uniqueness), release APK builds (`app-release.apk`). On-device emulator smoke skipped per user; `integration_test/device_smoke_test.dart` is ready for manual device QA before store release.

## Phase 1.5 — On-device ML tools (~4–6 wk) — 23 tools — ✅ COMPLETE (2026-08-15)
Depends on Phase 2 model delivery for the heavy ones.
1. **ML Kit (easy, free, high ROI):** remove-bg / background tools (Subject Segmentation), OCR / image-to-text (Text Recognition). Models bundled or ML-Kit-downloaded.
2. **ONNX (heavy, NPU-gated):** upscale (Real-ESRGAN), inpaint (LaMa: remove-object/person/text/watermark), colorize, repair, sharpen, unblur — via `onnxruntime`. Models via Phase 2 manifest.
3. **ASR:** audio→text / transcribe / subtitles via `sherpa_onnx`.
- **Acceptance:** remove-bg + OCR + one upscale model run on-device on a mid-range Android; weak devices gracefully hide/disable.
- **Status:** shipped. All 23 ML tools registered (18 image + 5 video/audio) through the single registry; engines: `google_mlkit_subject_segmentation`/`_text_recognition`/`_translation` (self-managed, ungated), `onnxruntime` (upscale/deblur/sharpen/unblur/colorize/inpaint family), `sherpa_onnx` (transcribe/subtitles/summarize); curated `assets/manifest.json` (real HuggingFace URLs + sha256) delivered via the Phase-2 `ModelManager`. Proactive tool-screen device-gating: model-backed tools resolve status on open — incompatible → disabled "needs a more capable device" panel; not-cached → in-screen model download with live progress (Run disabled until cached); cached → normal Run. Verified: `flutter analyze` clean, full host suite green (144 tests) incl. `test/ml_tools_wiring_test.dart` (OCR/segmentation/ONNX-enhance/ASR tool→engine wiring) and the `image/upscale` gating widget test (incompatible/not-cached/cached). On-device smoke (`integration_test/device_smoke_test.dart`: remove-bg + OCR + upscale) ready for manual device QA before release.

## Phase 2 — On-demand model delivery (~2–3 wk) — infra — ✅ COMPLETE (2026-07-04)
Runs in parallel with 1.5 (1.5 consumes it).
- Remote **manifest** (curated: best model per task) → resumable download → **sha256 verify** → versioned cache → device-capability gating. Full spec in `MODEL_DELIVERY.md`.
- **Honest constraint:** "best model" = WE curate it in the manifest (offline eval); app auto-selects a *fast/quality variant* by device class, it does not auto-discover models.
- **Status:** shipped in `lib/models/`: strict manifest schema+parse, ETag-cached loader w/ offline fallback, resumable Range downloads + streamed sha256 (one retry), versioned `taskId/version/variantId` cache w/ LRU eviction, /proc/meminfo device gating, coalescing `ModelManager.ensureReady` wired into DI. 17/17 unit tests. Remaining deployment config (not code): host the curated manifest at `kModelManifestUrl` and author variants after offline eval.

## Phase 3 — On-device agent (~4–6 wk) — 56 LLM tools + orchestration
- `flutter_gemma` + **Gemma 4 E2B** (function calling). The 56 Write/summarize/translate tools become on-device LLM tools.
- **Agent tiers (D6):** 3a NL→single-tool routing (reliable) → 3b 2–3 step guided chains (feasible w/ guardrails). **No 3c full autonomy, no cloud planner.**
- Each `ToolModule.fnSchema` is exposed as a callable function; **all tool-call args validated** before execution.
- **Acceptance:** "compress this PDF and convert to grayscale" → agent picks + chains the two on-device tools with a confirm step.

## Out of scope (see DECISIONS.md)
- Deferred (cloud, post-v1): 20 Office/ebook/image-gen tools.
- Dropped: 7 social downloaders.

## Effort summary
P0 2–3w · P1 6–8w · P1.5 4–6w · P2 2–3w (parallel) · P3 4–6w → **~5–6 months** to differentiated app, near-zero opex. First release candidate at end of Phase 1.
