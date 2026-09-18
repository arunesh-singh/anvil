import 'package:share_plus/share_plus.dart';

/// Thin wrapper over share_plus so tools/UI never touch the plugin directly.
class ShareService {
  /// Opens the platform share sheet for the given file [paths].
  /// Uses the share_plus v13 API: `SharePlus.instance.share(ShareParams(...))`.
  Future<void> shareFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(files: [for (final path in paths) XFile(path)]),
    );
  }
}
