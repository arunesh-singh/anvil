import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Filesystem access for tool outputs. Outputs live under the app's persistent
/// documents directory (survives OS cache eviction, so history paths stay valid).
class FileService {
  /// `<app documents>/anvil/outputs`, created if absent.
  Future<Directory> outputsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'anvil', 'outputs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Writes [content] into [outputsDir] under a collision-safe name and returns
  /// the created file. The name is prefixed with an epoch-ms stamp.
  Future<File> writeString(String fileName, String content) async {
    final file = await _stampedFile(fileName);
    return file.writeAsString(content);
  }

  /// Binary counterpart of [writeString] for formats like xlsx.
  Future<File> writeBytes(String fileName, List<int> bytes) async {
    final file = await _stampedFile(fileName);
    return file.writeAsBytes(bytes);
  }

  /// Reserves a collision-safe output path without creating the file, for
  /// engines (e.g. FFmpeg) that write the output themselves.
  Future<File> reserveFile(String fileName) => _stampedFile(fileName);

  Future<String> readString(String path) => File(path).readAsString();

  Future<List<int>> readBytes(String path) => File(path).readAsBytes();

  /// Deletes each path if it exists; individual failures are swallowed so one
  /// stale entry never aborts a bulk prune.
  Future<void> deletePaths(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // best-effort cleanup
      }
    }
  }

  /// Removes every produced output, then recreates the empty outputs dir.
  Future<void> clearOutputs() async {
    final d = await outputsDir();
    if (await d.exists()) await d.delete(recursive: true);
    await outputsDir();
  }

  Future<File> _stampedFile(String fileName) async {
    final dir = await outputsDir();
    final stamped = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    return File(p.join(dir.path, stamped));
  }
}
