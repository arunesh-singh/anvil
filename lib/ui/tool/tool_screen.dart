import 'package:flutter/material.dart';

import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tool/editors/collage_editor_screen.dart';
import 'package:anvil/ui/tool/editors/crop_editor_screen.dart';
import 'package:anvil/ui/tool/editors/overlay_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_doc_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_rect_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_stamp_editor_screen.dart';
import 'package:anvil/ui/tool/editors/split_editor_screen.dart';
import 'package:anvil/ui/tool/generic_tool_screen.dart';
import 'package:anvil/ui/tool/workspace/pdf_workspace_screen.dart';

/// Maps a tool to its screen. Spatial/WYSIWYG image tools opt into custom
/// editors; the page/document PDF tools all open the PDF workspace, landing on
/// their op's sheet; everything else uses [GenericToolScreen] (which itself
/// adds a live preview pane for filter image tools).
Widget toolScreenFor(ToolModule tool) => switch (tool.meta.qualifiedId) {
  'image/add-images' => OverlayEditorScreen(tool: tool),
  'image/crop' => CropEditorScreen(tool: tool),
  'image/collage-maker' ||
  'image/combine-maker' => CollageEditorScreen(tool: tool),
  'image/split' => SplitEditorScreen(tool: tool),
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
  _ => GenericToolScreen(tool: tool),
};
