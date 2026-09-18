import 'package:anvil/core/tool_module.dart';
import 'package:anvil/tools/converters/converter_tools.dart';
import 'package:anvil/tools/image/image_convert_tools.dart';
import 'package:anvil/tools/image/image_ml_tools.dart';
import 'package:anvil/tools/image/image_native_tools.dart';
import 'package:anvil/tools/pdf/pdf_tools.dart';
import 'package:anvil/tools/video/video_ml_tools.dart';
import 'package:anvil/tools/video/video_tools.dart';
import 'package:anvil/tools/write/write_tools.dart';

/// Holds every registered tool and answers lookups for the home grid, search,
/// and (Phase 3) the agent.
class ToolRegistry {
  ToolRegistry(this.all);
  final List<ToolModule> all;

  /// Looks a tool up by bare id (first match) or by qualified
  /// `<category>/<id>` (exact) — slugs like `compress` repeat across
  /// categories, so persisted references MUST use [ToolMeta.qualifiedId].
  ToolModule? byId(String id) {
    final slash = id.indexOf('/');
    if (slash > 0) {
      final cat = id.substring(0, slash);
      final slug = id.substring(slash + 1);
      return all
          .where((t) => t.meta.category.name == cat && t.meta.id == slug)
          .firstOrNull;
    }
    return all.where((t) => t.meta.id == id).firstOrNull;
  }

  List<ToolModule> byCategory(ToolCategory c) =>
      all.where((t) => t.meta.category == c).toList();
}

/// The single canonical registration list. Adding a tool = add its constructor
/// to the category builder. Dart has no runtime reflection in release builds, so
/// this explicit list IS the auto-discovery pattern, made concrete.
List<ToolModule> buildTools() => [
      ...buildConverters(),
      ...buildPdfTools(),
      ...buildImageNativeTools(),
      ...buildImageConvertTools(),
      ...buildVideoTools(),
      ...buildImageMlTools(),
      ...buildVideoMlTools(),
      ...buildWriteTools(),
    ];
