/// Running the real tool on the selected file IS the preview: exact output
/// bytes and size with no per-tool preview code (the idea behind the generic
/// screen's live preview, extracted for the redesigned image screens).
///
/// [PreviewRunner] debounces requests, drops stale results by sequence
/// number, and never touches `jobProvider` (that one navigates to the result
/// screen). [loadImageFile] reads a picked image and its pixel size once, so
/// each screen starts from the real dimensions.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';

/// Debounced "run [tool] on one file with these params" whose latest output
/// is [bytes]. [loading] covers the debounce wait and the run; [failed] is
/// set when the newest run threw or produced no file.
class PreviewRunner extends ChangeNotifier {
  PreviewRunner(this.tool, {this.delay = const Duration(milliseconds: 300)});

  final ToolModule tool;
  final Duration delay;

  Uint8List? _bytes;

  /// The newest finished output; kept while a newer run is pending so the
  /// UI never flashes empty.
  Uint8List? get bytes => _bytes;

  /// Output size in bytes, or null before the first success.
  int? get byteLength => _bytes?.length;

  String? _outputName;

  /// The output's file name — its extension tells the screen when the tool
  /// changed the format (png → jpg).
  String? get outputName => _outputName;

  bool _loading = false;
  bool get loading => _loading;

  bool _failed = false;
  bool get failed => _failed;

  Timer? _timer;
  int _seq = 0;
  bool _disposed = false;

  /// Schedules a run on [file] with [params]; a newer request supersedes it.
  void request(InputFile file, Map<String, dynamic> params) {
    _timer?.cancel();
    final seq = ++_seq;
    _loading = true;
    _failed = false;
    notifyListeners();
    _timer = Timer(delay, () => _run(seq, file, params));
  }

  /// Drops any pending or in-flight run (e.g. on Run).
  void cancel() {
    _timer?.cancel();
    _seq++;
    if (_loading) {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _run(
    int seq,
    InputFile file,
    Map<String, dynamic> params,
  ) async {
    Uint8List? out;
    String? name;
    try {
      final events = await tool
          .run(ToolInput(files: [file], params: params))
          .toList();
      final last = events.isEmpty ? null : events.last;
      if (last is ToolSucceeded && last.result.files.isNotEmpty) {
        final f = last.result.files.first;
        out = await File(f.path).readAsBytes();
        name = f.name;
        // The output is a throwaway copy; don't let previews pile up in the
        // outputs folder.
        unawaited(File(f.path).delete().then((_) {}, onError: (_) {}));
      }
    } catch (_) {
      out = null;
    }
    if (_disposed || seq != _seq) return;
    _loading = false;
    if (out == null) {
      _failed = true;
    } else {
      _bytes = out;
      _outputName = name;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _seq++;
    super.dispose();
  }
}

/// A picked image read once: its bytes and stored pixel size.
class LoadedImage {
  const LoadedImage({
    required this.file,
    required this.bytes,
    required this.width,
    required this.height,
  });

  final InputFile file;
  final Uint8List bytes;
  final int width;
  final int height;

  int get longEdge => width >= height ? width : height;
}

/// Reads [f] and its stored dimensions from the header (no full decode).
/// These are the pixels the native image tools see — they ignore EXIF
/// orientation, so the numbers match the output.
Future<LoadedImage> loadImageFile(InputFile f) async {
  final bytes = await File(f.path).readAsBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final img = LoadedImage(
      file: f,
      bytes: bytes,
      width: desc.width,
      height: desc.height,
    );
    desc.dispose();
    return img;
  } catch (_) {
    throw const ToolException('Could not read this image.');
  } finally {
    buffer.dispose();
  }
}

/// Lowercase extension of [name] with `jpeg` read as `jpg`; '' when none.
String imageExt(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return '';
  final e = name.substring(dot + 1).toLowerCase();
  return e == 'jpeg' ? 'jpg' : e;
}
