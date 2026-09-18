/// Input/output value types shared by every [ToolModule].
///
/// This file is UI-agnostic: it MUST NOT import `package:flutter/material.dart`.
library;

/// A file handed to a tool as input.
class InputFile {
  final String path;
  final String name;
  final String? mimeType;
  const InputFile({required this.path, required this.name, this.mimeType});
}

/// Everything a tool needs for one run: the files plus tool-specific params.
class ToolInput {
  final List<InputFile> files;
  final Map<String, dynamic> params;
  const ToolInput({required this.files, this.params = const {}});
}

/// A file produced by a tool.
class OutputFile {
  final String path;
  final String name;
  final String? mimeType;
  const OutputFile({required this.path, required this.name, this.mimeType});
}

/// The terminal payload of a successful tool run.
class ToolResult {
  final List<OutputFile> files;
  final String? text;
  const ToolResult({required this.files, this.text});
}

/// Streamed progress emitted by [ToolModule.run].
///
/// Contract: a tool yields zero or more [ToolRunning] updates, then exactly one
/// terminal [ToolSucceeded]. Tools do NOT yield [ToolFailed] themselves — on a
/// known bad input they throw [ToolException]; the job layer is the only place
/// that maps thrown errors (or a yielded [ToolFailed]) into a failed UI state.
sealed class ToolProgress {
  const ToolProgress();
}

class ToolRunning extends ToolProgress {
  /// 0..1 when known; null for indeterminate progress.
  final double? fraction;
  final String? message;
  const ToolRunning({this.fraction, this.message});
}

class ToolSucceeded extends ToolProgress {
  final ToolResult result;
  const ToolSucceeded(this.result);
}

class ToolFailed extends ToolProgress {
  final String message;
  const ToolFailed(this.message);
}

/// Thrown by a tool for a user-presentable failure (e.g. malformed input).
/// [message] is shown to the user verbatim, so keep it friendly.
class ToolException implements Exception {
  final String message;
  const ToolException(this.message);
  @override
  String toString() => message;
}
