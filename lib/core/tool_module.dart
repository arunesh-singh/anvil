/// The contract every tool implements. Ported pattern from Google AI Edge
/// Gallery's `CustomTask` registry (see ARCHITECTURE.md).
///
/// UI-agnostic except for [IconData], which is a plain value type from
/// `package:flutter/widgets.dart` (no widget tree dependency). Per ARCHITECTURE
/// the doc sketches a `Widget buildScreen(BuildContext)` member; we deliberately
/// omit it so `core/` and `tools/` never import the widget layer. The UI maps a
/// tool to its screen by `meta.id` instead (see lib/ui/tool/generic_tool_screen).
library;

import 'package:flutter/widgets.dart' show IconData;

import 'package:anvil/core/fn_schema.dart';
import 'package:anvil/core/tool_io.dart';

/// Top-level grouping shown as a section on the home grid.
enum ToolCategory { converter, pdf, image, video, write }

/// Selects the executor backing a tool. Names match ARCHITECTURE.md's table.
/// Phase 0 ships only [dartlib]; the rest land with their engines in later phases.
enum EngineKind { dartlib, pdf, image, ffmpeg, mlkit, onnx, asr, llm }

/// Identifies a downloadable model a tool needs. Minimal in Phase 0 (all tools
/// return `null`); expanded in Phase 2 per MODEL_DELIVERY.md.
class ModelSpec {
  final String taskId;
  const ModelSpec({required this.taskId});
}

/// Static, user-facing description of a tool.
class ToolMeta {
  /// Stable internal id; equals the tinywow slug for ported tools.
  final String id;
  final ToolCategory category;

  /// Display label, e.g. 'CSV to JSON'.
  final String label;
  final IconData icon;
  final String description;

  /// Source slug, e.g. 'csv-to-json'.
  final String tinywowSlug;

  /// Lowercase, no leading dot, e.g. `['csv']`.
  final List<String> acceptedExtensions;

  /// Tool-specific inputs rendered by the generic tool screen. Empty for most.
  final List<ToolParam> params;

  /// Whether the tool consumes several input files at once (e.g. merge PDFs).
  /// The generic tool screen enables multi-select when true.
  final bool acceptsMultiple;

  /// False for tools that need no input file (e.g. URL-to-PDF, text-to-image
  /// generators); the generic screen then enables Run with nothing selected.
  final bool requiresInput;

  /// False for tools whose real inputs come from a WYSIWYG editor as JSON
  /// (page sizes, overlay maps, crop margins) rather than declarable [params].
  /// Such tools can only fail when a function-calling agent invokes them, so
  /// they are hidden from the agent's shortlist while staying in the grid.
  final bool agentCallable;

  /// Extra lowercase single words the agent's shortlist scores against, for
  /// phrasings that appear in neither the id, the label, nor the description
  /// (e.g. 'trim' for the video cutter). Scored like an id-word hit.
  final List<String> keywords;

  /// Collision-free identifier: slugs repeat across categories (`compress`
  /// exists for pdf, image, and video), so persistence and the Phase-3 agent
  /// use `<category>/<id>`.
  String get qualifiedId => '${category.name}/$id';

  const ToolMeta({
    required this.id,
    required this.category,
    required this.label,
    required this.icon,
    required this.description,
    required this.tinywowSlug,
    required this.acceptedExtensions,
    this.params = const [],
    this.acceptsMultiple = false,
    this.requiresInput = true,
    this.agentCallable = true,
    this.keywords = const [],
  });
}

/// Kind of value a [ToolParam] carries; drives keyboard + parsing in the UI.
enum ToolParamType { integer, text }

/// A single user-adjustable parameter. Integer params (e.g. rows-per-file)
/// collect via [defaultValue]; free-text params (e.g. watermark text) via
/// [defaultText].
class ToolParam {
  final String key;
  final String label;
  final ToolParamType type;
  final int defaultValue;
  final String defaultText;

  /// Integer bounds for the stepper UI; free-text params ignore them.
  final int min;
  final int? max;

  /// Optional muted helper line rendered under the field.
  final String helperText;

  /// Renders as a multi-line box (article/brief bodies) instead of one line.
  final bool multiline;
  const ToolParam({
    required this.key,
    required this.label,
    this.type = ToolParamType.integer,
    this.defaultValue = 0,
    this.defaultText = '',
    this.min = 0,
    this.max,
    this.helperText = '',
    this.multiline = false,
  });
}

/// One tool. Implementations live under `lib/tools/<category>/`.
abstract interface class ToolModule {
  ToolMeta get meta;
  EngineKind get engine;
  ModelSpec? get model;

  /// JSON-schema fed to the Phase 3 agent. Empty until then.
  Map<String, dynamic> get fnSchema;

  /// Triggers any one-time prep (e.g. model download). No-op until Phase 2.
  Future<void> ensureReady();

  /// Runs the tool, streaming progress then exactly one [ToolSucceeded].
  Stream<ToolProgress> run(ToolInput input);

  /// Rejects an input file *set* the tool cannot run on (e.g. `pdf/add-images`
  /// needs one PDF plus one image, `pdf/merge` needs two files) as a
  /// user-facing message, or null when the set is usable.
  ///
  /// Extension-level checks live in [ToolMeta.acceptedExtensions]; this covers
  /// combinations they cannot express. The Phase-3 validator calls it BEFORE
  /// the confirm step, so the model repairs its call instead of the user
  /// confirming a step that is bound to fail (logged: `pdf/add-images` run
  /// with only a photo attached).
  String? fileSetError(List<InputFile> files);
}

/// Convenience base supplying the inert Phase-0 defaults so concrete tools only
/// implement [meta], [engine], and [run].
abstract class BaseToolModule implements ToolModule {
  @override
  ModelSpec? get model => null;

  @override
  Map<String, dynamic> get fnSchema => fnSchemaFor(meta);

  @override
  Future<void> ensureReady() async {}

  @override
  String? fileSetError(List<InputFile> files) => null;
}
