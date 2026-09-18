# Stack & Packages

Flutter (stable for app; **master channel required only for `flutter_gemma`** native-assets — see Phase 3 note). Android-first (minSdk 26+ recommended for ML/NPU; some ONNX/Gemma need more RAM).

## Packages by engine
| Concern | Package | Notes / risk |
|---|---|---|
| DI / state | `get_it` + `riverpod` | registry binding, auto-discovery |
| File pick / share | `file_picker`, `share_plus`, `receive_sharing_intent` | Android share-intent ingest |
| PDF render | `pdfrx` | free (D3) |
| PDF create/edit | `pdf` + native platform-channel | merge/split/compress/rotate/encrypt via native (PdfBox-Android / PdfRenderer) |
| Image transform | native channel + `flutter_image_compress` | pure-Dart `image` too slow for big files |
| SVG render | `flutter_svg` | conversion to/from SVG is limited |
| Video/audio | `ffmpeg_kit_flutter` (**sk3llo fork, LGPL build**) | ⚠️ upstream retired; D4: no fallback v1 |
| ML segmentation/OCR | `google_mlkit_subject_segmentation`, `google_mlkit_text_recognition` | free; remove-bg + image-to-text |
| ONNX ML | `onnxruntime` | upscale (Real-ESRGAN), inpaint (LaMa), colorize; models via manifest |
| ASR | `sherpa_onnx` | transcription, VAD; ONNX models |
| On-device LLM | `flutter_gemma` | Gemma 4 E2B / FunctionGemma 270M; function calling |
| Download | `dio` (range/resume) or `flutter_downloader` | Phase 2 model fetch |
| Hashing | `crypto` | sha256 model verify |
| Storage | `path_provider`, `sqflite`/`drift` | model cache + history |

## flutter_gemma setup gotchas (Phase 3)
- Requires **Flutter master channel** + `--enable-experiment=native-assets`.
- iOS needs a **manually created Podfile** to link MediaPipe (`MediaPipeTasksGenAI`).
- Gemma 4 E2B fits <1.5 GB at 2–4-bit quant → safe from OS low-memory kills on mid/high-end.
- FunctionGemma 270M base tool-calling ≈58% accuracy → use Gemma 4 E2B as primary; FunctionGemma only as a fast router if fine-tuned.

## FFmpeg licensing note (D4)
- Use the **LGPL** (non-GPL, `min-gpl`-free) build of the fork to keep the app closed-source-distributable.
- Codec patent exposure is an open question post-MPEG-LA/Via-LA — avoid bundling patent-encumbered encoders you don't need; prefer royalty-free (VP9/Opus/WebP) where possible.

## Device gating
- Read RAM/accelerator at runtime; gate ONNX/Gemma tools behind a minimum (mirror Gallery's `minDeviceMemoryInGb`).
- Tiny on-device benchmark on first ML use → pick `fast` vs `quality` model variant.
- Weak device → tool shown as "needs a more capable device" rather than crashing.
