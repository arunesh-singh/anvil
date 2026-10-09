/// Model-facing guidance for one tool. Read this before adding tools.
///
/// Authoring rules (copy them into guide entries as inline comments):
///
/// **Hints (max 220 chars, one line):**
/// - H1: Start with `Use for: ` followed by 2–5 short phrasings a user would
///   type, comma-separated, ending with `.`.
/// - H2: Then at most one sentence naming what the model must pass when it is
///   not obvious:
///   - which slot gets which file;
///   - which params to set from which request words (e.g. "Set position from
///     words like 'bottom left'.");
///   - write-category tools: "Put the user's text in `text`." (real param key);
///   - omit this sentence for single-file, no-param tools.
/// - H3: At most one `Not for: <case> - use <fn_name>.`, only where a
///   confusable tool exists. Use the `fnNameFor` name (e.g. `pdf_add_text`),
///   never the qualified id.
/// - H4: Hand-off tools state that the user finishes it by hand in the editor.
///   Never tell the model to invent coordinates. For pixel/point region params
///   the user did not give (e.g. `_rectParams` tools in `image_ml_tools.dart`),
///   say "Needs the region in pixels; if the user gave none, ask in plain text."
///
/// **Keywords (lowercase, matching ^[a-z0-9]{2,}$):**
/// - K1: Lowercase, no underscores or hyphens; matching `^[a-z0-9]{2,}$`.
/// - K2: Not in `toolStopWords`, not the category name, not an accepted
///   extension, not already a word of the tool id.
/// - K3: Words users really say for this tool: synonyms, jargon, app names
///   (`excel`, `whatsapp`). At most 8.
/// - K4: No generic category words (`image`, `photo`, `video`, `pdf`,
///   `convert`, `edit`, `change`), except in migrated lists.
library;

import 'package:anvil/core/guides/converter_guides.dart';
import 'package:anvil/core/guides/image_guides.dart';
import 'package:anvil/core/guides/pdf_guides.dart';
import 'package:anvil/core/guides/video_guides.dart';
import 'package:anvil/core/guides/write_guides.dart';

/// Model-facing guidance for one tool.
class ToolGuide {
  /// One-line hint: "Use for: ... [Set/Put ...] [Not for: ...]"
  final String hint;

  /// Extra request words the shortlist scores like an id-word hit. Marked up
  /// (lowercase, 2+ chars, no spaces). At most 8.
  final List<String> keywords;

  const ToolGuide(this.hint, {this.keywords = const []});
}

/// Reads a guide for a tool by [qualifiedId], e.g. 'pdf/sign'.
ToolGuide? guideFor(String qualifiedId) => toolGuides[qualifiedId];

/// All tool guides, keyed by `ToolMeta.qualifiedId`.
const toolGuides = <String, ToolGuide>{
  ...converterToolGuides,
  ...pdfToolGuides,
  ...imageToolGuides,
  ...videoToolGuides,
  ...writeToolGuides,
};
