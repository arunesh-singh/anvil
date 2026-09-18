/// Validates a Gemma tool-call against the target tool's derived schema
/// BEFORE anything executes (R3: a small model hallucinates args — never run
/// unvalidated). Pure Dart — host-tested in test/agent_test.dart.
library;

import 'dart:io';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';

/// A tool-call that passed validation and is ready to execute (after the
/// user's confirm step, D6).
class ValidatedCall {
  final ToolModule tool;
  final ToolInput input;
  const ValidatedCall({required this.tool, required this.input});
}

/// Why a tool-call was rejected; the agent feeds [message] back to the model.
class InvalidCallException implements Exception {
  final String message;
  const InvalidCallException(this.message);
  @override
  String toString() => message;
}

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Validates [args] against [tool]'s meta. [fileExists] is injectable for
/// host tests (defaults to a real filesystem check).
ValidatedCall validateCall(
  ToolModule tool,
  Map<String, dynamic> args, {
  bool Function(String path)? fileExists,
}) {
  final exists = fileExists ?? (p) => File(p).existsSync();
  final meta = tool.meta;
  final knownKeys = {
    if (meta.requiresInput) meta.acceptsMultiple ? 'files' : 'file',
    for (final p in meta.params) p.key,
  };
  for (final key in args.keys) {
    if (!knownKeys.contains(key)) {
      throw InvalidCallException(
          "Unknown argument '$key' for ${meta.qualifiedId}. "
          'Allowed: ${knownKeys.join(', ')}.');
    }
  }

  // Files.
  final files = <InputFile>[];
  if (meta.requiresInput) {
    final List<String> paths;
    if (meta.acceptsMultiple) {
      final raw = args['files'];
      if (raw is! List || raw.isEmpty || raw.any((e) => e is! String)) {
        throw InvalidCallException(
            "${meta.qualifiedId} needs 'files': a non-empty list of paths.");
      }
      paths = raw.cast<String>();
    } else {
      final raw = args['file'];
      if (raw is! String || raw.isEmpty) {
        throw InvalidCallException(
            "${meta.qualifiedId} needs 'file': the input file path.");
      }
      paths = [raw];
    }
    for (final path in paths) {
      if (!exists(path)) {
        throw InvalidCallException("File not found: $path");
      }
      final ext = _ext(path);
      if (meta.acceptedExtensions.isNotEmpty &&
          !meta.acceptedExtensions.contains(ext)) {
        throw InvalidCallException(
            "${meta.qualifiedId} accepts ${meta.acceptedExtensions.join('/')} "
            "files, got '.$ext'.");
      }
      files.add(InputFile(path: path, name: path.split('/').last));
    }
  }

  // Params: coerce + type-check against the declared ToolParams.
  final params = <String, dynamic>{};
  for (final p in meta.params) {
    final raw = args[p.key];
    if (raw == null) continue; // tools fall back to declared defaults
    switch (p.type) {
      case ToolParamType.integer:
        final v = switch (raw) {
          final int i => i,
          final num n => n.toInt(),
          final String s => int.tryParse(s.trim()),
          _ => null,
        };
        if (v == null) {
          throw InvalidCallException(
              "Argument '${p.key}' of ${meta.qualifiedId} must be an "
              'integer.');
        }
        if (v < p.min || (p.max != null && v > p.max!)) {
          final range = p.max != null ? '${p.min}–${p.max}' : 'at least ${p.min}';
          throw InvalidCallException(
              "Argument '${p.key}' of ${meta.qualifiedId} must be $range.");
        }
        params[p.key] = v;
      case ToolParamType.text:
        if (raw is! String) {
          throw InvalidCallException(
              "Argument '${p.key}' of ${meta.qualifiedId} must be a string.");
        }
        params[p.key] = raw;
    }
  }

  return ValidatedCall(
    tool: tool,
    input: ToolInput(files: files, params: params),
  );
}
