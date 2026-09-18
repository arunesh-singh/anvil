# Risk Register

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | **FFmpegKit retired** (Jan 2025); relying on a community fork (`sk3llo`) | High | Isolate behind `ffmpeg` engine executor (one file). D4: no fallback v1, but the interface makes a later platform-channel (MediaCodec/AVFoundation) swap cheap. Pin exact fork version |
| R2 | **Codec patent exposure** post-MPEG-LA/Via-LA | Med | Use LGPL build; avoid bundling patent-encumbered encoders you don't ship; prefer royalty-free (VP9/Opus/WebP/AV1) |
| R3 | **Small-LLM tool-calling unreliable** (FunctionGemma ≈58%) | High (Phase 3) | Primary = Gemma 4 E2B (native function calling); mandatory arg-validation against `fnSchema`; cap at guided chains (3b), confirm before execute. Never run unvalidated calls |
| R4 | **Model size vs APK / storage** | Med | On-demand download (Phase 2), not bundled; LRU cache + storage manager; variant by device |
| R5 | **Device floor** — old/low-RAM Android can't run ONNX/Gemma | Med | Device gating (RAM/accelerator); disable with clear message; deterministic tools still work everywhere |
| R6 | **flutter_gemma setup friction** (master channel, native-assets, iOS Podfile) | Med | Pin Flutter version; document build steps; gate Phase 3 behind a stable integration spike before committing |
| R7 | **Thermal/battery** on long video transcodes | Med | Length/resolution caps; progress + cancel; warn user; run in isolate |
| R8 | **`pdfrx`/native PDF gaps** vs Syncfusion (no built-in compress/advanced edit) | Med | Native platform-channel (PdfBox-Android) for merge/compress/encrypt; validate the ~30 PDF ops against pdfrx capability early in Phase 1 |
| R9 | **iOS parity later** — some plugins/models differ | Low–Med | All chosen plugins (ML Kit, onnxruntime, sherpa, flutter_gemma, ffmpeg fork) support iOS; budget a parity pass post Android v1 |
| R10 | **Deferred cloud tools** (Office/ebook/image-gen) may be expected by users | Low | Clearly out of v1 (D5); revisit as Pro tier with a backend later |

## Early de-risking spikes (do before committing each phase)
- **Phase 1 spike:** prove the ~30 PDF ops on `pdfrx` + native (R8) before building all PDF tools.
- **Phase 1 spike:** confirm the LGPL ffmpeg fork builds + runs the needed filters on a real device (R1/R2).
- **Phase 3 spike:** integrate `flutter_gemma` + run one function-call end-to-end before scoping the agent (R3/R6).
