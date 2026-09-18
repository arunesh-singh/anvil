# Tool Catalog — TinyWow parity map

Source: scraped from https://tinywow.com/tools (+5 category pages) via Scrapling on 2026-06-20.
Raw data: `data/tinywow_catalog.json` · Classification: `data/tool_classification.json`
Reclassified 2026-07-03: eps/vsd/vsdx/from-msg → DEFERRED-CLOUD (no on-device engine: Ghostscript / Visio renderer / .msg parser); translate + tiff-to-text → ONDEVICE-ML (OCR/MT).

**259 TinyWow tools** → **218 on-device in scope (84%)**, 33 deferred (cloud, post-v1), 7 dropped. (`pdf/annotate` merged into `pdf/add-text`.)

| Bucket | Count | Meaning |
|---|---|---|
| ONDEVICE-DET | 139 | Deterministic native libs. Phase 1. Zero model, zero cost |
| ONDEVICE-ML | 23 | On-device ML model. Phase 1.5. Model downloaded on demand (Phase 2) |
| ONDEVICE-LLM | 56 | On-device Gemma. Phase 3. Writing/summarize/translate |
| DEFERRED-CLOUD | 33 | Needs LibreOffice/Ghostscript/Calibre/diffusion. Out of v1 (no cloud). Revisit as Pro |
| DROPPED | 7 | Social downloaders. Store-policy + legal risk |


## On-device deterministic (Phase 1) — 139

| Category | Tool | Engine |
|---|---|---|
| converter | csv-to-excel | `dart-libs` |
| converter | csv-to-json | `dart-libs` |
| converter | csv-to-xml | `dart-libs` |
| converter | excel-to-csv | `dart-libs` |
| converter | excel-to-xml | `dart-libs` |
| converter | json-to-xml | `dart-libs` |
| converter | split-csv | `dart-libs` |
| converter | split-excel | `dart-libs` |
| converter | xml-to-csv | `dart-libs` |
| converter | xml-to-excel | `dart-libs` |
| converter | xml-to-json | `dart-libs` |
| image | add-images | `native-image` |
| image | border | `native-image` |
| image | chart-maker | `native-image` |
| image | collage-maker | `native-image` |
| image | combine-maker | `native-image` |
| image | compress | `native-image` |
| image | crop | `native-image` |
| image | crop-circle | `native-image` |
| image | flip | `native-image` |
| image | font-to-png | `native-image` |
| image | gif-to-apng | `native-image` |
| image | gif-to-avif | `native-image` |
| image | gif-to-jpg | `native-image` |
| image | gif-to-png | `native-image` |
| image | grayscale | `native-image` |
| image | heic-to-avif | `native-image` |
| image | heic-to-jpg | `native-image` |
| image | heic-to-png | `native-image` |
| image | jpg-to-avif | `native-image` |
| image | jpg-to-gif | `native-image` |
| image | jpg-to-png | `native-image` |
| image | jpg-to-svg | `native-image` |
| image | jpg-to-tiff | `native-image` |
| image | jpg-to-webp | `native-image` |
| image | metadata | `native-image` |
| image | pixelate | `native-image` |
| image | png-to-avif | `native-image` |
| image | png-to-eps | `native-image` |
| image | png-to-gif | `native-image` |
| image | png-to-jpg | `native-image` |
| image | png-to-svg | `native-image` |
| image | png-to-tiff | `native-image` |
| image | png-to-webp | `native-image` |
| image | psd-to-ai | `native-image` |
| image | psd-to-jpg | `native-image` |
| image | psd-to-pdf | `native-image` |
| image | psd-to-png | `native-image` |
| image | psd-to-svg | `native-image` |
| image | resize | `native-image` |
| image | split | `native-image` |
| image | svg-to-png | `native-image` |
| image | text-image-generator | `native-image` |
| image | text-to-image | `native-image` |
| image | tiff-to-jpg | `native-image` |
| image | tiff-to-png | `native-image` |
| image | tiff-to-svg | `native-image` |
| image | webp-to-avif | `native-image` |
| image | webp-to-gif | `native-image` |
| image | webp-to-jpg | `native-image` |
| image | webp-to-png | `native-image` |
| pdf | add-images | `pdfrx+pdf+native` |
| pdf | add-pages | `pdfrx+pdf+native` |
| pdf | add-text | `pdfrx+pdf+native` |
| pdf | compress | `pdfrx+pdf+native` |
| pdf | create | `pdfrx+pdf+native` |
| pdf | crop | `pdfrx+pdf+native` |
| pdf | delete | `pdfrx+pdf+native` |
| pdf | edit | `pdfrx+pdf+native` |
| pdf | extract-img | `pdfrx+pdf+native` |
| pdf | extract-text | `pdfrx+pdf+native` |
| pdf | from-gif | `pdfrx+pdf+native` |
| pdf | from-heic | `pdfrx+pdf+native` |
| pdf | from-jpg | `pdfrx+pdf+native` |
| pdf | from-png | `pdfrx+pdf+native` |
| pdf | from-tiff | `pdfrx+pdf+native` |
| pdf | from-url | `pdfrx+pdf+native` |
| pdf | from-webp | `pdfrx+pdf+native` |
| pdf | merge | `pdfrx+pdf+native` |
| pdf | protect | `pdfrx+pdf+native` |
| pdf | rearrange | `pdfrx+pdf+native` |
| pdf | remove-watermark | `pdfrx+pdf+native` |
| pdf | rotate | `pdfrx+pdf+native` |
| pdf | sign | `pdfrx+pdf+native` |
| pdf | split | `pdfrx+pdf+native` |
| pdf | to-csv | `pdfrx+pdf+native` |
| pdf | to-jpg | `pdfrx+pdf+native` |
| pdf | to-png | `pdfrx+pdf+native` |
| pdf | to-text | `pdfrx+pdf+native` |
| pdf | to-tiff | `pdfrx+pdf+native` |
| pdf | unlock | `pdfrx+pdf+native` |
| pdf | watermark | `pdfrx+pdf+native` |
| video | aac-to-flac | `ffmpeg-kit-fork(LGPL)` |
| video | aac-to-m4r | `ffmpeg-kit-fork(LGPL)` |
| video | aac-to-mp3 | `ffmpeg-kit-fork(LGPL)` |
| video | aac-to-mp4 | `ffmpeg-kit-fork(LGPL)` |
| video | aac-to-wav | `ffmpeg-kit-fork(LGPL)` |
| video | avi-to-gif | `ffmpeg-kit-fork(LGPL)` |
| video | avi-to-mkv | `ffmpeg-kit-fork(LGPL)` |
| video | avi-to-mov | `ffmpeg-kit-fork(LGPL)` |
| video | avi-to-mp3 | `ffmpeg-kit-fork(LGPL)` |
| video | avi-to-mp4 | `ffmpeg-kit-fork(LGPL)` |
| video | compress | `ffmpeg-kit-fork(LGPL)` |
| video | compress-avi | `ffmpeg-kit-fork(LGPL)` |
| video | compress-mkv | `ffmpeg-kit-fork(LGPL)` |
| video | compress-mov | `ffmpeg-kit-fork(LGPL)` |
| video | cutter | `ffmpeg-kit-fork(LGPL)` |
| video | extract-audio | `ffmpeg-kit-fork(LGPL)` |
| video | gif-to-mov | `ffmpeg-kit-fork(LGPL)` |
| video | gif-to-webm | `ffmpeg-kit-fork(LGPL)` |
| video | m4a-to-mp3 | `ffmpeg-kit-fork(LGPL)` |
| video | m4a-to-mp4 | `ffmpeg-kit-fork(LGPL)` |
| video | m4a-to-wav | `ffmpeg-kit-fork(LGPL)` |
| video | mkv-to-avi | `ffmpeg-kit-fork(LGPL)` |
| video | mkv-to-gif | `ffmpeg-kit-fork(LGPL)` |
| video | mkv-to-mov | `ffmpeg-kit-fork(LGPL)` |
| video | mkv-to-mp3 | `ffmpeg-kit-fork(LGPL)` |
| video | mkv-to-mp4 | `ffmpeg-kit-fork(LGPL)` |
| video | mov-to-avi | `ffmpeg-kit-fork(LGPL)` |
| video | mov-to-gif | `ffmpeg-kit-fork(LGPL)` |
| video | mov-to-mp3 | `ffmpeg-kit-fork(LGPL)` |
| video | mov-to-mp4 | `ffmpeg-kit-fork(LGPL)` |
| video | mov-to-wav | `ffmpeg-kit-fork(LGPL)` |
| video | mp4-to-avi | `ffmpeg-kit-fork(LGPL)` |
| video | mp4-to-gif | `ffmpeg-kit-fork(LGPL)` |
| video | mp4-to-mov | `ffmpeg-kit-fork(LGPL)` |
| video | mp4-to-mp3 | `ffmpeg-kit-fork(LGPL)` |
| video | mp4-to-ogg | `ffmpeg-kit-fork(LGPL)` |
| video | mp4-to-wav | `ffmpeg-kit-fork(LGPL)` |
| video | mp4-to-webm | `ffmpeg-kit-fork(LGPL)` |
| video | mute | `ffmpeg-kit-fork(LGPL)` |
| video | ogg-to-mp3 | `ffmpeg-kit-fork(LGPL)` |
| video | ogg-to-wav | `ffmpeg-kit-fork(LGPL)` |
| video | resize | `ffmpeg-kit-fork(LGPL)` |
| video | to-gif | `ffmpeg-kit-fork(LGPL)` |
| video | to-webp | `ffmpeg-kit-fork(LGPL)` |
| video | webm-to-mov | `ffmpeg-kit-fork(LGPL)` |
| video | webm-to-mp3 | `ffmpeg-kit-fork(LGPL)` |
| video | webm-to-mp4 | `ffmpeg-kit-fork(LGPL)` |

## On-device ML (Phase 1.5) — 23

| Category | Tool | Engine |
|---|---|---|
| image | blur-background | `mlkit-segmentation` |
| image | change-bg-photo | `mlkit-segmentation` |
| image | cleanup-picture | `onnxruntime` |
| image | colorize-photo | `onnxruntime` |
| image | make-background-transparent | `mlkit-segmentation` |
| image | profile-photo | `mlkit-segmentation` |
| image | remove-bg | `mlkit-segmentation` |
| image | remove-objects | `onnxruntime` |
| image | remove-person | `onnxruntime` |
| image | remove-text-photo | `mlkit-ocr` |
| image | remove-watermark-photo | `onnxruntime` |
| image | repair-defects | `onnxruntime` |
| image | sharpen | `onnxruntime` |
| image | tiff-to-text | `mlkit` |
| image | to-text | `mlkit-ocr` |
| image | translate | `mlkit+onnx` |
| image | unblur | `onnxruntime` |
| image | upscale | `onnxruntime` |
| video | add-subtitles | `sherpa-onnx-asr` |
| video | audio-to-text | `sherpa-onnx-asr` |
| video | summarize-podcast | `sherpa-onnx-asr` |
| video | to-text | `mlkit-ocr` |
| video | transcribe-podcast | `sherpa-onnx-asr` |

## On-device LLM (Phase 3) — 56

| Category | Tool | Engine |
|---|---|---|
| pdf | summarizer | `flutter_gemma` |
| pdf | translate | `flutter_gemma` |
| write | ai-detector | `flutter_gemma` |
| write | ai-rephraser | `flutter_gemma` |
| write | ai-twitter-generator | `flutter_gemma` |
| write | article-generator | `flutter_gemma` |
| write | article-rewriter | `flutter_gemma` |
| write | article-writer | `flutter_gemma` |
| write | bill-sale-generator | `flutter_gemma` |
| write | blog-outline | `flutter_gemma` |
| write | business-name-generator | `flutter_gemma` |
| write | business-plan-generator | `flutter_gemma` |
| write | business-slogan-generator | `flutter_gemma` |
| write | cold-email-writer | `flutter_gemma` |
| write | content-brief-generator | `flutter_gemma` |
| write | content-improver | `flutter_gemma` |
| write | content-planner | `flutter_gemma` |
| write | content-summarizer | `flutter_gemma` |
| write | essay-writer | `flutter_gemma` |
| write | explain-like-five | `flutter_gemma` |
| write | facebook-ad-headlines | `flutter_gemma` |
| write | faq-generator | `flutter_gemma` |
| write | grammar-fixer | `flutter_gemma` |
| write | humanizer-ai | `flutter_gemma` |
| write | instagram-caption-generator | `flutter_gemma` |
| write | instagram-story-ideas | `flutter_gemma` |
| write | landing-page-copy | `flutter_gemma` |
| write | linkedin-post-generator | `flutter_gemma` |
| write | listicle-writer | `flutter_gemma` |
| write | meta-description-generator | `flutter_gemma` |
| write | nda-generator | `flutter_gemma` |
| write | paragraph-completer | `flutter_gemma` |
| write | paragraph-rewriter | `flutter_gemma` |
| write | paragraph-writer | `flutter_gemma` |
| write | paraphrasing | `flutter_gemma` |
| write | podcast-writer | `flutter_gemma` |
| write | poll-generator | `flutter_gemma` |
| write | post-generator | `flutter_gemma` |
| write | post-ideas | `flutter_gemma` |
| write | post-rewriter | `flutter_gemma` |
| write | post-writer | `flutter_gemma` |
| write | press-release-generator | `flutter_gemma` |
| write | privacy-policy-generator | `flutter_gemma` |
| write | purchase-agreement-generator | `flutter_gemma` |
| write | real-estate-description | `flutter_gemma` |
| write | sentence-rewriter | `flutter_gemma` |
| write | shorten-content | `flutter_gemma` |
| write | story-generator | `flutter_gemma` |
| write | summarize-youtube | `flutter_gemma` |
| write | tiktok-script-writer | `flutter_gemma` |
| write | title-rewriter | `flutter_gemma` |
| write | tone-of-voice | `flutter_gemma` |
| write | translate | `flutter_gemma` |
| write | trivia-generator | `flutter_gemma` |
| write | word-counter | `flutter_gemma` |
| write | youtube-script-writer | `flutter_gemma` |

## Deferred — cloud required (post-v1) — 33

| Category | Tool | Engine |
|---|---|---|
| converter | azw3-to-epub | `-` |
| converter | azw3-to-mobi | `-` |
| converter | epub-to-azw3 | `-` |
| converter | epub-to-mobi | `-` |
| converter | excel-to-pdf | `-` |
| converter | mobi-to-azw3 | `-` |
| converter | mobi-to-epub | `-` |
| image | ai-art-generator | `-` |
| image | ai-image-generator | `-` |
| image | eps-to-jpg | `cloud-required` |
| image | eps-to-png | `cloud-required` |
| image | eps-to-svg | `cloud-required` |
| image | vsd-to-docx | `cloud-required` |
| image | vsd-to-jpg | `cloud-required` |
| image | vsd-to-pdf | `cloud-required` |
| image | vsd-to-pptx | `cloud-required` |
| image | vsdx-to-docx | `cloud-required` |
| image | vsdx-to-jpg | `cloud-required` |
| image | vsdx-to-pdf | `cloud-required` |
| image | vsdx-to-pptx | `cloud-required` |
| pdf | from-azw3 | `-` |
| pdf | from-eps | `cloud-required` |
| pdf | from-epub | `-` |
| pdf | from-mobi | `-` |
| pdf | from-msg | `cloud-required` |
| pdf | from-ppt | `-` |
| pdf | from-word | `-` |
| pdf | to-azw3 | `-` |
| pdf | to-epub | `-` |
| pdf | to-mobi | `-` |
| pdf | to-ppt | `-` |
| pdf | to-word | `-` |
| pdf | to-xlsx | `-` |

## Dropped — 7

- **video**: from-fb, from-gif, from-inst, from-tiktok, from-twitter, youtube-to-text, youtube-transcript
