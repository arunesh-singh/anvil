# Phase 2 — On-demand Model Delivery

Goal: ship a **lean APK** with no heavy ML models; download only the curated best model for a task when first used. Ported from Gallery's `ModelAllowlist` + `DownloadWorker` + `Model`.

## Flow
```
tool.ensureReady()
  -> fetch manifest (cached, ETag)        # remote JSON, our CDN
  -> resolve task_id -> pick variant by device class (fast|quality)
  -> if not cached: resumable download (dio range)  -> sha256 verify -> unpack -> cache dir (versioned)
  -> load into engine (onnxruntime / sherpa / flutter_gemma)
```

## Manifest schema (remote JSON)
```jsonc
{
  "manifestVersion": 3,
  "models": {
    "image.remove-bg": {
      "variants": [
        { "id": "u2netp-fp16", "tier": "fast",
          "url": "https://cdn.anvil.app/models/u2netp-fp16.onnx",
          "sha256": "…", "sizeBytes": 4600000, "runtime": "onnx",
          "minRamGb": 2, "accelerator": "nnapi", "version": "1.0.0" },
        { "id": "isnet-general", "tier": "quality",
          "url": "…", "sha256": "…", "sizeBytes": 178000000, "runtime": "onnx",
          "minRamGb": 4, "accelerator": "gpu", "version": "1.0.0" }
      ]
    },
    "image.upscale":     { "variants": [ { "id": "realesrgan-x4-fp16", "...": "..." } ] },
    "video.transcribe":  { "variants": [ { "id": "whisper-tiny", "runtime": "onnx", "...": "..." } ] },
    "agent.llm":         { "variants": [ { "id": "gemma-4-e2b-int4", "runtime": "task", "minRamGb": 4 } ] }
  }
}
```

## Rules
- **Curated, not auto-discovered:** we benchmark offline and pin the best model per task in the manifest. App selects a *variant* (fast/quality) by device RAM/accelerator — it does **not** choose models itself. (Honest scoping of the original "best model per task" ask.)
- **Integrity:** every download sha256-verified before use; corrupt → re-download once → fail gracefully.
- **Versioning:** cache keyed by `task_id/version/id`; manifest bump triggers update prompt (Gallery's `updatableModelFiles` pattern).
- **Eviction:** LRU cache with a size ceiling + manual "manage storage" screen (models are large).
- **Gating:** if no variant meets device `minRamGb`/accelerator → tool disabled with a clear message (no cloud fallback in v1, D5).
- **Offline:** once cached, fully offline. First-use requires network for the download only.

## Data backing
- `data/tool_classification.json` lists which tools are `ONDEVICE-ML` (need a model) vs `ONDEVICE-DET` (none).
- Manifest is authored/hosted separately; this doc is the contract.
