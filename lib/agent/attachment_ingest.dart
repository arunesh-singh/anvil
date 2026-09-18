/// Turns a picked file into a Gemma-consumable form: vision-capable models get
/// image bytes; everything else is coerced to text (OCR / extraction /
/// conversion) reusing Anvil's own tools + engines. Unsupported formats are
/// rejected with a clear note. Pure of Flutter widgets — host-testable via
/// getIt overrides.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/image_engine.dart';

/// The result of ingesting one attachment for the model.
sealed class IngestedAttachment {
  final String name;
  const IngestedAttachment(this.name);
}

/// File content injected into the prompt as text.
class IngestedText extends IngestedAttachment {
  final String content;
  const IngestedText(super.name, this.content);
}

/// Image bytes (png/jpg/webp) fed to a vision-capable model.
class IngestedImage extends IngestedAttachment {
  final Uint8List bytes;
  const IngestedImage(super.name, this.bytes);
}

/// The format could not be read into a chat.
class IngestRejected extends IngestedAttachment {
  final String reason;
  const IngestRejected(super.name, this.reason);
}

/// Runs [tool] to its terminal result, throwing [ToolException] on a failure
/// or a missing result. Extracted so the chat controller and the ingestion
/// paths share one drain of `Stream<ToolProgress>`.
Future<ToolResult> runToolToCompletion(ToolModule tool, ToolInput input) async {
  ToolResult? out;
  await for (final p in tool.run(input)) {
    switch (p) {
      case ToolSucceeded(:final result):
        out = result;
      case ToolFailed(:final message):
        throw ToolException(message);
      case ToolRunning():
        break;
    }
  }
  if (out == null) throw const ToolException('That step produced no result.');
  return out;
}

const int _maxTextChars = 4000;

const Set<String> _textExts = {
  'txt', 'text', 'md', 'markdown', 'json', 'jsonl', 'csv', 'tsv', 'xml',
  'yaml', 'yml', 'log', 'ini', 'toml', 'html', 'htm', 'css', 'dart', 'py',
  'js', 'ts', 'tsx', 'jsx', 'java', 'kt', 'kts', 'c', 'h', 'cpp', 'cc', 'hpp',
  'cs', 'go', 'rs', 'rb', 'php', 'swift', 'sql', 'sh', 'bash',
};

const Set<String> _imageDirectExts = {'jpg', 'jpeg', 'png', 'webp'};
const Set<String> _imageConvertExts = {
  'heic', 'heif', 'bmp', 'gif', 'tiff', 'tif', 'avif',
};

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Ingests [file] for a model. [modelSupportsImage] decides whether images are
/// passed as bytes (vision) or OCR'd to text.
Future<IngestedAttachment> ingestAttachment(
  InputFile file, {
  required bool modelSupportsImage,
}) async {
  final ext = _ext(file.name);

  if (_textExts.contains(ext)) {
    final raw = await File(file.path).readAsString();
    return IngestedText(file.name, _truncate(raw));
  }

  if (_imageDirectExts.contains(ext)) {
    if (modelSupportsImage) {
      final bytes = await File(file.path).readAsBytes();
      return IngestedImage(file.name, bytes);
    }
    return _ocrFile(file, 'image/to-text');
  }

  if (_imageConvertExts.contains(ext)) {
    // tiff/tif OCR happens on the original file (ML Kit can't read TIFF; the
    // tool normalizes to PNG itself) when there's no vision model.
    if (!modelSupportsImage && (ext == 'tiff' || ext == 'tif')) {
      return _ocrFile(file, 'image/tiff-to-text');
    }
    final src = await File(file.path).readAsBytes();
    final Uint8List png;
    try {
      png = await getIt<ImageEngine>().convert(src, format: 'png', quality: 100);
    } catch (_) {
      return IngestRejected(
          file.name, "Anvil couldn't decode this .$ext image.");
    }
    if (modelSupportsImage) return IngestedImage(file.name, png);
    return _ocrBytes(file.name, png);
  }

  if (ext == 'pdf') {
    try {
      final result = await runToolToCompletion(
          _tool('pdf/extract-text'), ToolInput(files: [file]));
      final text = await _resultText(result);
      if (text.trim().isEmpty) {
        return IngestRejected(
            file.name, 'No selectable text — this PDF looks scanned.');
      }
      return IngestedText(file.name, _truncate(text));
    } on ToolException catch (e) {
      return IngestRejected(file.name, e.message);
    }
  }

  if (ext == 'xlsx') {
    try {
      final result = await runToolToCompletion(
          _tool('converter/excel-to-csv'), ToolInput(files: [file]));
      return IngestedText(file.name, _truncate(await _resultText(result)));
    } on ToolException catch (e) {
      return IngestRejected(file.name, e.message);
    }
  }

  return IngestRejected(
    file.name,
    "Anvil can't read .$ext into a chat yet — convert it in the Tools tab "
    'first.',
  );
}

ToolModule _tool(String id) => getIt<ToolRegistry>().byId(id)!;

/// OCR a file already on disk (jpg/png/webp/tiff) via [toolId].
Future<IngestedAttachment> _ocrFile(InputFile file, String toolId) async {
  try {
    final result =
        await runToolToCompletion(_tool(toolId), ToolInput(files: [file]));
    final text = result.text ?? '';
    if (text.trim().isEmpty) {
      return IngestRejected(file.name, 'No readable text in this image.');
    }
    return IngestedText(file.name, _truncate(text));
  } on ToolException {
    return IngestRejected(file.name, 'No readable text in this image.');
  }
}

/// OCR image [bytes] (written to a temp png) via `image/to-text`.
Future<IngestedAttachment> _ocrBytes(String name, Uint8List bytes) async {
  final tmp = await getIt<FileService>().writeBytes('chat-ocr.png', bytes);
  return _ocrFile(InputFile(path: tmp.path, name: 'chat-ocr.png'), 'image/to-text')
      .then((r) => switch (r) {
            IngestedText(:final content) => IngestedText(name, content),
            IngestRejected(:final reason) => IngestRejected(name, reason),
            _ => IngestRejected(name, 'No readable text in this image.'),
          });
}

/// Prefer the tool's inline [ToolResult.text]; else read its first output file.
Future<String> _resultText(ToolResult result) async {
  if (result.text != null && result.text!.isNotEmpty) return result.text!;
  final first = result.files.firstOrNull;
  if (first == null) return '';
  return File(first.path).readAsString();
}

String _truncate(String s) =>
    s.length <= _maxTextChars ? s : '${s.substring(0, _maxTextChars)}\n…[truncated]';
