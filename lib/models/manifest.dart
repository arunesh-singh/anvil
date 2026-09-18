/// Remote model-manifest schema and strict JSON parsing.
///
/// Contract source: MODEL_DELIVERY.md ("Manifest schema"). The manifest is a
/// curated document on our CDN; parsing is deliberately strict — a malformed
/// manifest is an authoring bug we want to surface loudly, not paper over.
library;

import 'dart:convert';

/// Highest `manifestVersion` this build of the app understands. A manifest
/// with a greater version is rejected with [UnsupportedManifestVersionException]
/// (the format may have changed in ways we cannot parse safely).
const int supportedManifestVersion = 4;

/// Malformed manifest (missing/mistyped fields, bad enum values, bad JSON).
class ManifestFormatException implements Exception {
  final String message;
  const ManifestFormatException(this.message);
  @override
  String toString() => 'ManifestFormatException: $message';
}

/// The manifest was authored for a newer app than this build.
class UnsupportedManifestVersionException extends ManifestFormatException {
  final int manifestVersion;
  const UnsupportedManifestVersionException(this.manifestVersion)
    : super(
        'manifest version $manifestVersion is newer than the highest '
        'supported version $supportedManifestVersion — update Anvil to use '
        'this tool',
      );
}

/// Speed/quality trade-off of a variant; the device class picks one.
enum ModelTier {
  fast,
  quality;

  static ModelTier parse(String raw, String context) => switch (raw) {
    'fast' => fast,
    'quality' => quality,
    _ => throw ManifestFormatException("$context: unknown tier '$raw'"),
  };
}

/// Model architecture family; selects the flutter_gemma `ModelType` and the
/// function-call format the plugin weaves (Gemma 4 native tokens vs Qwen3's
/// `QwenFunctionCallFormat` text stream). Defaults [gemma4] for
/// backward-compatible manifests that omit `family`.
enum ModelFamily {
  gemma4,
  qwen3;

  static ModelFamily parse(String raw, String context) => switch (raw) {
    'gemma4' => gemma4,
    'qwen3' => qwen3,
    _ => throw ManifestFormatException("$context: unknown family '$raw'"),
  };
}

/// Engine that consumes the model file (see EngineKind in core/tool_module).
enum ModelRuntime {
  onnx,
  sherpa,

  /// LiteRT `.task` bundle (flutter_gemma / MediaPipe GenAI).
  task;

  static ModelRuntime parse(String raw, String context) => switch (raw) {
    'onnx' => onnx,
    'sherpa' => sherpa,
    'task' => task,
    _ => throw ManifestFormatException("$context: unknown runtime '$raw'"),
  };
}

final _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

/// One downloadable model file for a task.
class ModelVariant {
  final String id;
  final ModelTier tier;
  final String url;

  /// Lowercase-insensitive hex digest of the file at [url].
  final String sha256;
  final int sizeBytes;
  final ModelRuntime runtime;

  /// Minimum device RAM in whole GB for this variant to be offered.
  final int minRamGb;

  /// Advisory execution-provider hint ('cpu' | 'nnapi' | 'gpu' | …); see
  /// DeviceCaps.supportsAccelerator for how it gates selection.
  final String accelerator;

  /// Model version; part of the cache key, so a manifest bump re-downloads.
  final String version;

  /// Whether this variant can consume image input (vision). Curator-controlled;
  /// defaults false for backward-compatible manifests.
  final bool supportsImage;

  /// Model architecture family; selects the engine's `ModelType`. Defaults
  /// [ModelFamily.gemma4] for backward-compatible manifests that omit it.
  final ModelFamily family;

  /// Whole KV budget (prompt + output) this variant is loaded with. Curated
  /// per model; defaults 4096 for backward-compatible manifests. litertlm's
  /// minimum is 1024.
  final int maxTokens;

  const ModelVariant({
    required this.id,
    required this.tier,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
    required this.runtime,
    required this.minRamGb,
    required this.accelerator,
    required this.version,
    this.supportsImage = false,
    this.family = ModelFamily.gemma4,
    this.maxTokens = 4096,
  });

  factory ModelVariant.fromJson(Map<String, dynamic> json, String context) {
    final id = _field<String>(json, 'id', context);
    final ctx = "$context variant '$id'";
    final sha256 = _field<String>(json, 'sha256', ctx);
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw ManifestFormatException("$ctx: 'sha256' is not a 64-char hex digest");
    }
    final url = _field<String>(json, 'url', ctx);
    if (url.isEmpty) throw ManifestFormatException("$ctx: 'url' is empty");
    final sizeBytes = _field<int>(json, 'sizeBytes', ctx);
    if (sizeBytes <= 0) throw ManifestFormatException("$ctx: 'sizeBytes' must be > 0");
    final minRamGb = _field<int>(json, 'minRamGb', ctx);
    if (minRamGb < 0) throw ManifestFormatException("$ctx: 'minRamGb' must be >= 0");
    final maxTokens = json['maxTokens'] as int? ?? 4096;
    if (maxTokens < 1024) {
      throw ManifestFormatException("$ctx: 'maxTokens' must be >= 1024");
    }
    return ModelVariant(
      id: id,
      tier: ModelTier.parse(_field<String>(json, 'tier', ctx), ctx),
      url: url,
      sha256: sha256.toLowerCase(),
      sizeBytes: sizeBytes,
      runtime: ModelRuntime.parse(_field<String>(json, 'runtime', ctx), ctx),
      minRamGb: minRamGb,
      accelerator: _field<String>(json, 'accelerator', ctx),
      version: _field<String>(json, 'version', ctx),
      supportsImage: json['supportsImage'] as bool? ?? false,
      family: json['family'] == null
          ? ModelFamily.gemma4
          : ModelFamily.parse(json['family'] as String, ctx),
      maxTokens: maxTokens,
    );
  }
}

/// The curated variants for one task id (e.g. `image.remove-bg`).
class TaskModels {
  final List<ModelVariant> variants;

  /// Whether this task is offered in the chat model picker. Defaults false.
  final bool chat;
  const TaskModels({required this.variants, this.chat = false});

  factory TaskModels.fromJson(Map<String, dynamic> json, String taskId) {
    final raw = _field<List<dynamic>>(json, 'variants', "task '$taskId'");
    if (raw.isEmpty) {
      throw ManifestFormatException("task '$taskId': 'variants' is empty");
    }
    return TaskModels(
      chat: json['chat'] as bool? ?? false,
      variants: [
        for (final entry in raw)
          ModelVariant.fromJson(
            _asObject(entry, "task '$taskId' variants[]"),
            "task '$taskId'",
          ),
      ],
    );
  }
}

/// The whole remote manifest: task id -> curated variants.
class Manifest {
  final int manifestVersion;
  final Map<String, TaskModels> models;
  const Manifest({required this.manifestVersion, required this.models});

  factory Manifest.fromJsonString(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      throw ManifestFormatException('manifest is not valid JSON: ${e.message}');
    }
    return Manifest.fromJson(_asObject(decoded, 'manifest root'));
  }

  factory Manifest.fromJson(Map<String, dynamic> json) {
    final version = _field<int>(json, 'manifestVersion', 'manifest root');
    if (version > supportedManifestVersion) {
      throw UnsupportedManifestVersionException(version);
    }
    final models = _field<Map<String, dynamic>>(json, 'models', 'manifest root');
    return Manifest(
      manifestVersion: version,
      models: {
        for (final entry in models.entries)
          entry.key: TaskModels.fromJson(
            _asObject(entry.value, "task '${entry.key}'"),
            entry.key,
          ),
      },
    );
  }
}

T _field<T>(Map<String, dynamic> json, String key, String context) {
  final value = json[key];
  if (value is! T) {
    throw ManifestFormatException(
      json.containsKey(key)
          ? "$context: '$key' has type ${value.runtimeType}, expected $T"
          : "$context: missing required field '$key'",
    );
  }
  return value;
}

Map<String, dynamic> _asObject(Object? value, String context) {
  if (value is! Map<String, dynamic>) {
    throw ManifestFormatException('$context: expected a JSON object');
  }
  return value;
}
