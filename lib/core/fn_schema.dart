/// Derives the Phase-3 function-calling schema for a tool from its [ToolMeta].
///
/// Every tool's invocation surface is uniform — input file(s) plus typed
/// params — so the JSON schema the agent exposes to Gemma is derived here
/// once instead of hand-written 219 times. The agent-side validator
/// (lib/agent/arg_validator.dart) enforces the same shape before execution.
library;

import 'package:anvil/core/tool_guide.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/core/tool_vocab.dart';

/// JSON-schema-shaped map: `{name, description, parameters, triggers}`.
Map<String, dynamic> fnSchemaFor(ToolMeta meta) {
  final handoffOnly = meta.editorHandoff?.always ?? false;
  final properties = <String, dynamic>{
    if (meta.inputSlots.isNotEmpty)
      for (final s in meta.inputSlots)
        s.key: {
          'type': 'string',
          'description':
              '${s.description} Absolute path of a ${s.extensions.join('/')} file.',
        }
    else if (meta.requiresInput)
      if (meta.acceptsMultiple)
        'files': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'Absolute paths of the input files '
              '(${meta.acceptedExtensions.join('/')}).',
        }
      else
        'file': {
          'type': 'string',
          'description':
              'Absolute path of the input file '
              '(${meta.acceptedExtensions.join('/')}).',
        },
    if (!handoffOnly)
      for (final p in meta.params)
        p.key: switch (p.type) {
          ToolParamType.integer => {
            'type': 'integer',
            'description': _paramDescription(p),
            'default': p.defaultValue,
            'minimum': p.min,
            if (p.max != null) 'maximum': p.max,
          },
          ToolParamType.text => {
            'type': 'string',
            'description': _paramDescription(p),
            if (p.defaultText.isNotEmpty) 'default': p.defaultText,
          },
          ToolParamType.choice => {
            'type': 'string',
            'description': _paramDescription(p),
            'enum': p.choices,
            'default': p.defaultText,
          },
        },
  };
  final required = <String>[
    if (meta.inputSlots.isNotEmpty)
      for (final s in meta.inputSlots)
        if (s.required)
          s.key
        else if (meta.requiresInput)
          meta.acceptsMultiple ? 'files' : 'file',
  ];
  return {
    'name': fnNameFor(meta),
    'description': () {
      final guide = guideFor(meta.qualifiedId);
      return guide != null
          ? '${meta.description} ${guide.hint}'
          : meta.description;
    }(),
    'parameters': {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    },
    'triggers': needleTriggersFor(meta),
  };
}

/// The model-facing function name. The on-device tool-call grammar (native
/// LiteRT-LM parser and flutter_gemma's fallback regex `call:([\w-]+)`) accepts
/// only `[A-Za-z0-9_-]` — a `/` (as in [ToolMeta.qualifiedId]) makes EVERY call
/// unparseable. We keep the category prefix for unambiguous resolution but
/// join with `_` and collapse the id's hyphens, so `pdf/add-images` becomes
/// `pdf_add_images` — grammar-safe and still meaningful to the model. The
/// agent keys its tool map by this same name, so resolution needs no reversal.
String fnNameFor(ToolMeta meta) =>
    '${meta.category.name}_${meta.id.replaceAll('-', '_')}';

/// A model-facing param description: the label, plus the tool's own helper
/// text when present (e.g. "Quality. 1-100, lower = smaller file"). Small-model
/// tool-calling accuracy hinges on this being specific.
String _paramDescription(ToolParam p) =>
    p.helperText.isEmpty ? p.label : '${p.label}. ${p.helperText}';
