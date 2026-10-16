import 'package:flutter/material.dart';

import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tool/editors/background_screen.dart';
import 'package:anvil/ui/tool/editors/border_image_screen.dart';
import 'package:anvil/ui/tool/editors/collage_editor_screen.dart';
import 'package:anvil/ui/tool/editors/compress_image_screen.dart';
import 'package:anvil/ui/tool/editors/crop_editor_screen.dart';
import 'package:anvil/ui/tool/editors/overlay_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_doc_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_rect_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_stamp_editor_screen.dart';
import 'package:anvil/ui/tool/editors/resize_image_screen.dart';
import 'package:anvil/ui/tool/editors/split_editor_screen.dart';
import 'package:anvil/ui/tool/editors/split_table_screen.dart';
import 'package:anvil/ui/tool/editors/translate_image_screen.dart';
import 'package:anvil/ui/tool/editors/video_compress_screen.dart';
import 'package:anvil/ui/tool/editors/video_gif_screen.dart';
import 'package:anvil/ui/tool/editors/video_trim_screen.dart';
import 'package:anvil/ui/tool/editors/write_tool_screen.dart';
import 'package:anvil/ui/tool/generic_tool_screen.dart';
import 'package:anvil/ui/tool/workspace/pdf_workspace_screen.dart';

/// Maps a tool to its screen. Tools with a redesigned screen (design
/// `explorations/tools-workspace.html`) get it — every write tool shares the
/// inline-result [WriteToolScreen]; the page/document PDF tools all open the
/// PDF workspace, landing on their op's sheet; everything else uses
/// [GenericToolScreen] (shared first-open picker + params).
Widget toolScreenFor(ToolModule tool) => switch (tool.meta.qualifiedId) {
  'image/add-images' => OverlayEditorScreen(tool: tool),
  'image/crop' => CropEditorScreen(tool: tool),
  'image/collage-maker' ||
  'image/combine-maker' => CollageEditorScreen(tool: tool),
  'image/split' => SplitEditorScreen(tool: tool),
  'image/compress' => CompressImageScreen(tool: tool),
  'image/resize' => ResizeImageScreen(tool: tool),
  'image/border' => BorderImageScreen(tool: tool),
  'image/blur-background' ||
  'image/remove-bg' ||
  'image/change-bg-photo' => BackgroundScreen(tool: tool),
  'image/translate' => TranslateImageScreen(tool: tool),
  'video/cutter' => TrimVideoScreen(tool: tool),
  'video/compress' ||
  'video/compress-avi' ||
  'video/compress-mkv' ||
  'video/compress-mov' => CompressVideoScreen(tool: tool),
  'video/to-gif' ||
  'video/mp4-to-gif' ||
  'video/mov-to-gif' ||
  'video/mkv-to-gif' ||
  'video/avi-to-gif' ||
  'video/to-webp' => GifScreen(tool: tool),
  'converter/split-csv' ||
  'converter/split-excel' => SplitTableScreen(tool: tool),
  'pdf/workspace' || 'pdf/delete' || 'pdf/rotate' => const PdfWorkspaceScreen(),
  'pdf/merge' ||
  'pdf/rearrange' => const PdfWorkspaceScreen(initialOp: WorkspaceOp.organize),
  'pdf/compress' => const PdfWorkspaceScreen(initialOp: WorkspaceOp.compress),
  'pdf/add-text' => const PdfWorkspaceScreen(initialOp: WorkspaceOp.text),
  'pdf/sign' => const PdfWorkspaceScreen(initialOp: WorkspaceOp.sign),
  'pdf/crop' => const PdfWorkspaceScreen(initialOp: WorkspaceOp.crop),
  'pdf/split' => const PdfWorkspaceScreen(initialOp: WorkspaceOp.split),
  'pdf/add-images' => PdfStampEditorScreen(tool: tool),
  'pdf/create' => PdfDocEditorScreen(tool: tool, mode: PdfDocMode.create),
  'pdf/edit' => PdfDocEditorScreen(tool: tool, mode: PdfDocMode.edit),
  'pdf/remove-watermark' => PdfRectEditorScreen(tool: tool),
  _ when tool.meta.category == ToolCategory.write => WriteToolScreen(
    tool: tool,
  ),
  _ => GenericToolScreen(tool: tool),
};
