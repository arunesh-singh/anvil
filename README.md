# Anvil

> Working codename — an on-device "workbench" of file/media/AI tools. Rename freely.

**What:** A Flutter mobile app (Android-first, iOS later) that replicates ~85% of [TinyWow](https://tinywow.com)'s 259-tool catalog **fully on-device** — offline, private, zero per-use cost. PDF, image, video/audio, file-conversion, and (later) on-device AI tools, with an on-device LLM agent that drives the tools by natural language.

**Why on-device:** flips TinyWow's economics — no transcode/inference/egress opex; "instant + offline + nothing leaves your phone" is itself the retention hook. A sustainable free tier (the on-device tools) drives installs/retention.

## Status
- **Phase: PLANNING.** No code yet. This folder is the spec for execution.
- Decisions locked — see `DECISIONS.md`.

## How to read these docs (for the next agent)
1. `DECISIONS.md` — locked product/tech decisions. **Read first; do not relitigate.**
2. `PLAN.md` — phased roadmap, sequencing, effort, scope cuts.
3. `ARCHITECTURE.md` — tool-registry pattern, engine abstraction, agent design, what we reuse from Google AI Edge Gallery.
4. `STACK.md` — Flutter packages, versions, setup gotchas.
5. `MODEL_DELIVERY.md` — Phase 2 on-demand model manifest + download/verify/cache design.
6. `TOOL_CATALOG.md` — all 259 tools mapped to bucket + engine (generated).
7. `RISKS.md` — dependency/legal/perf risks + mitigations.
8. `data/` — `tinywow_catalog.json` (raw scrape), `tool_classification.json` (buckets + engines).

## One-paragraph summary
219/259 TinyWow tools run on-device across the roadmap: 140 deterministic (Phase 1, native libs), 23 ML (Phase 1.5, downloaded models), 56 LLM (Phase 3, on-device Gemma). 33 conversions needing LibreOffice/Ghostscript/Calibre/diffusion are **deferred** (no cloud in v1). 7 social-media downloaders are **dropped** (store policy + legal). Architecture copies Gallery's pluggable `CustomTask` registry + on-demand model-delivery stack, in Dart.
