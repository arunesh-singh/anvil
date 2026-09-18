import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';

/// Opens results in other apps and exports them to a user-chosen location.
/// Wraps the plugins so the UI never touches them directly (mirrors ShareService).
class ExportService {
  /// Opens [path] in the platform's default viewer for its type.
  /// Returns `null` on success, otherwise a user-facing failure message.
  Future<String?> openFile(String path) async {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done ? null : result.message;
  }

  /// Prompts for a destination (Android Storage Access Framework) and writes the
  /// file there. Returns the saved path, or `null` if the user cancelled.
  Future<String?> saveToDevice(String name, String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final uri = await FilePicker.saveFile(fileName: name, bytes: bytes);
    return uri?.toString();
  }
}
