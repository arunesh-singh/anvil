/// Orchestrates the MODEL_DELIVERY.md flow:
/// `ensureReady() → manifest → variant by device class → download+verify →
/// versioned cache → local path` for the engine to load.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/core/tool_module.dart' show ModelSpec;
import 'package:anvil/models/device_caps.dart';
import 'package:anvil/models/downloader.dart';
import 'package:anvil/models/manifest.dart';
import 'package:anvil/models/manifest_loader.dart';
import 'package:anvil/models/model_cache.dart';

/// No variant of the task fits this device (RAM/accelerator gate).
class IncompatibleDeviceException implements Exception {
  final String message;
  const IncompatibleDeviceException(this.message);
  @override
  String toString() => 'IncompatibleDeviceException: $message';
}

/// The manifest has no entry for the requested task id — an app/manifest
/// version skew or an authoring bug.
class UnknownModelTaskException implements Exception {
  final String taskId;
  const UnknownModelTaskException(this.taskId);
  @override
  String toString() => "UnknownModelTaskException: no models for '$taskId'";
}

/// A resolved, locally cached model ready for its engine.
class LoadedModel {
  final String taskId;
  final ModelVariant variant;
  final String filePath;
  const LoadedModel({
    required this.taskId,
    required this.variant,
    required this.filePath,
  });
}

enum ModelStatus { cached, notCached, incompatible }

/// One catalog row for the available-models screen: the variant this device
/// would download for [taskId] (or the leanest variant when none fit), plus
/// whether it fits this device and is already on disk.
class AvailableModel {
  final String taskId;
  final ModelVariant variant;
  final bool compatible;
  final bool cached;

  /// Task is offered in the chat model picker.
  final bool chat;

  /// Selected variant is vision-capable.
  final bool supportsImage;
  const AvailableModel({
    required this.taskId,
    required this.variant,
    required this.compatible,
    required this.cached,
    this.chat = false,
    this.supportsImage = false,
  });
}

class ModelManager {
  ModelManager({
    required this.loader,
    required this.downloader,
    required this.cache,
    required this.capsProvider,
  });

  final ManifestLoader loader;
  final ModelDownloader downloader;
  final ModelCache cache;
  final DeviceCapsProvider capsProvider;

  final Map<String, Future<LoadedModel>> _inflight = {};

  /// Resolves, downloads (if needed), verifies, and returns the local model
  /// for [spec]. Concurrent calls for the same task coalesce into one flow.
  Future<LoadedModel> ensureReady(
    ModelSpec spec, {
    void Function(int received, int total)? onProgress,
  }) {
    final existing = _inflight[spec.taskId];
    if (existing != null) return existing;
    // NOTE: whenComplete must NOT return the removed future — returning a
    // Future from whenComplete makes it await that future, which here is the
    // chain itself (deadlock).
    final future = _ensureReady(spec, onProgress).whenComplete(() {
      _inflight.remove(spec.taskId);
    });
    _inflight[spec.taskId] = future;
    return future;
  }

  Future<LoadedModel> _ensureReady(
    ModelSpec spec,
    void Function(int, int)? onProgress,
  ) async {
    final variant = await _resolve(spec.taskId);
    final fileName = _fileNameOf(variant);
    final file =
        cache.fileFor(spec.taskId, variant.version, variant.id, fileName);
    if (!await cache.contains(
        spec.taskId, variant.version, variant.id, fileName)) {
      await downloader.download(
        variant.url,
        file,
        expectedSha256: variant.sha256,
        expectedSizeBytes: variant.sizeBytes,
        onProgress: onProgress,
      );
    }
    await cache.touch(spec.taskId, variant.version, variant.id);
    return LoadedModel(
        taskId: spec.taskId, variant: variant, filePath: file.path);
  }

  /// Imports a user-picked local model file for [taskId] into the versioned
  /// cache, in place of the in-app download. The file MUST be the curated
  /// variant this device would download — its sha256 is verified against the
  /// manifest, so a wrong quant/format/artifact is rejected loudly rather than
  /// loaded. No-op (returns the cached path) when already present.
  Future<LoadedModel> importModel(String taskId, String sourcePath) async {
    final variant = await _resolve(taskId);
    final fileName = _fileNameOf(variant);
    final dest = cache.fileFor(taskId, variant.version, variant.id, fileName);
    if (await cache.contains(taskId, variant.version, variant.id, fileName)) {
      await cache.touch(taskId, variant.version, variant.id);
      return LoadedModel(taskId: taskId, variant: variant, filePath: dest.path);
    }
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw const ModelIntegrityException('The picked file no longer exists.');
    }
    await dest.parent.create(recursive: true);
    // Copy to a sibling .part, verify, then atomically rename — an interrupted
    // import never leaves a half-written payload the cache would trust.
    final part = File('${dest.path}.part');
    if (await part.exists()) await part.delete();
    await src.copy(part.path);
    final actual = (await sha256.bind(part.openRead()).first).toString();
    if (actual != variant.sha256) {
      await part.delete();
      throw ModelIntegrityException(
        "That file isn't the curated model for '$taskId'. Its checksum does "
        'not match — make sure you picked the exact ${variant.id} '
        '($fileName) file.',
      );
    }
    if (await dest.exists()) await dest.delete();
    await part.rename(dest.path);
    await cache.touch(taskId, variant.version, variant.id);
    return LoadedModel(taskId: taskId, variant: variant, filePath: dest.path);
  }

  /// Cache/compatibility state for the tool screen (download button, disabled
  /// state, storage list).
  Future<ModelStatus> status(String taskId) async {
    final ModelVariant variant;
    try {
      variant = await _resolve(taskId);
    } on IncompatibleDeviceException {
      return ModelStatus.incompatible;
    }
    return await cache.contains(
            taskId, variant.version, variant.id, _fileNameOf(variant))
        ? ModelStatus.cached
        : ModelStatus.notCached;
  }

  Future<void> evict(String taskId) => cache.evict(taskId);
  Future<List<CachedModel>> cachedModels() => cache.cachedModels();
  Future<int> totalCacheBytes() => cache.totalCacheBytes();

  /// The full curated catalog for the models screen: every task in the
  /// manifest with its device-selected variant and cache/compat state.
  /// Sorted by task id for a stable list order.
  Future<List<AvailableModel>> availableModels() async {
    final manifest = await loader.load();
    final caps = await capsProvider.read();
    final out = <AvailableModel>[];
    for (final entry in manifest.models.entries) {
      final variants = entry.value.variants;
      final compatible = [
        for (final v in variants) if (caps.isCompatibleWith(v)) v,
      ];
      final selected =
          compatible.isEmpty ? _leanest(variants) : _select(compatible, caps);
      final cached = await cache.contains(
          entry.key, selected.version, selected.id, _fileNameOf(selected));
      out.add(AvailableModel(
        taskId: entry.key,
        variant: selected,
        compatible: compatible.isNotEmpty,
        cached: cached,
        chat: entry.value.chat,
        supportsImage: selected.supportsImage,
      ));
    }
    out.sort((a, b) => a.taskId.compareTo(b.taskId));
    return out;
  }

  /// Variant selection policy (MODEL_DELIVERY.md "Honest constraint"): among
  /// device-compatible variants, quality wins on >= 6 GB devices, fast
  /// otherwise; a missing preferred tier falls back to the other one.
  Future<ModelVariant> _resolve(String taskId) async {
    final manifest = await loader.load();
    final task = manifest.models[taskId];
    if (task == null) throw UnknownModelTaskException(taskId);
    final caps = await capsProvider.read();
    final compatible =
        [for (final v in task.variants) if (caps.isCompatibleWith(v)) v];
    if (compatible.isEmpty) {
      throw const IncompatibleDeviceException(
          'This tool needs a more capable device (not enough memory for its '
          'on-device model).');
    }
    return _select(compatible, caps);
  }

  /// Among device-compatible [variants], quality wins on >= 6 GB devices, fast
  /// otherwise; a missing preferred tier falls back to the other one.
  ModelVariant _select(List<ModelVariant> variants, DeviceCaps caps) {
    final preferred = caps.ramGb >= 6 ? ModelTier.quality : ModelTier.fast;
    return variants.firstWhere(
      (v) => v.tier == preferred,
      orElse: () => variants.first,
    );
  }

  /// The variant with the smallest RAM requirement — shown (disabled) for a
  /// task no variant of which fits this device, so the catalog still lists it.
  ModelVariant _leanest(List<ModelVariant> variants) =>
      variants.reduce((a, b) => a.minRamGb <= b.minRamGb ? a : b);

  String _fileNameOf(ModelVariant variant) {
    final path = Uri.parse(variant.url).path;
    final name = p.basename(path);
    return name.isEmpty ? '${variant.id}.bin' : name;
  }
}
