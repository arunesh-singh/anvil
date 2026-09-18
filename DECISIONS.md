# Locked Decisions

Confirmed with product owner on 2026-06-20. **These are settled — execute against them, do not reopen without explicit instruction.**

| # | Decision | Choice | Rationale / consequence |
|---|---|---|---|
| D1 | Platform | **Flutter, Android-first**, iOS later | One codebase; Android-first ships faster, iOS parity later via same plugins |
| D2 | Social media downloaders (TikTok/IG/FB/Twitter/YouTube — 7 tools) | **DROPPED** | Google Play removes such apps; ToS/DMCA exposure. Not worth the risk |
| D3 | PDF engine | **`pdfrx` + native (free)**, NOT Syncfusion | Avoid commercial license / revenue cap. More work, no licensing strings |
| D4 | FFmpeg | **`sk3llo/ffmpeg_kit_flutter` LGPL fork; NO platform-channel fallback for v1** | Accept the dependency risk for now; isolate behind engine interface so a fallback can be added later if the fork dies |
| D5 | Cloud | **None in v1.** Everything on-device | No backend, no opex, no privacy compromise. Cloud-only tools are deferred |
| D6 | Agent (Phase 3) | **On-device Gemma 4 E2B, basic function calling, guided chains only.** No cloud planner | Tier 3a (NL→single tool) + 3b (2–3 step chains). No full autonomy (3c). Small-model arg-validation mandatory |
| D7 | Project location | `/Volumes/Arunesh/projects/anvil` | Codename "Anvil"; planning docs live here for omp/Claude handoff |

## Scope consequences
- **In scope (on-device): 219/259 tools** — 140 deterministic + 23 ML + 56 LLM. (Reclassified 2026-07-03: eps/vsd/vsdx/from-msg have no on-device engine → deferred; translate + tiff-to-text are OCR/MT → ML.)
- **Deferred (needs cloud, revisit post-v1 as Pro): 33** — PDF↔Office, ebook (epub/mobi/azw3) conversions, excel-to-pdf, AI image generation, EPS/Visio (.vsd/.vsdx) conversions, Outlook .msg to PDF.
- **Dropped: 7** — social downloaders.

## Explicit non-goals (v1)
- No backend / no cloud APIs.
- No Office/ebook document conversion (needs LibreOffice/Calibre class).
- No AI image generation (Stable Diffusion too heavy/thermal on most Android).
- No fully autonomous multi-step agent.
- No iOS build (parity pass comes after Android v1).
