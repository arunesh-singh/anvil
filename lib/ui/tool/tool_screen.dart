import 'package:flutter/material.dart';

import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tool/editors/collage_editor_screen.dart';
import 'package:anvil/ui/tool/editors/crop_editor_screen.dart';
import 'package:anvil/ui/tool/editors/overlay_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_compress_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_doc_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_merge_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_pages_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_rect_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_stamp_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_text_editor_screen.dart';
import 'package:anvil/ui/tool/editors/split_editor_screen.dart';
import 'package:anvil/ui/tool/generic_tool_screen.dart';

/// Maps a tool to its screen. Spatial/WYSIWYG image tools opt into custom
/// editors; everything else uses [GenericToolScreen] (which itself adds a live
/// preview pane for filter image tools).
Widget toolScreenFor(ToolModule tool) => switch (tool.meta.qualifiedId) {
      'image/add-images' => OverlayEditorScreen(tool: tool),
      'image/crop' => CropEditorScreen(tool: tool),
      'image/collage-maker' ||
      'image/combine-maker' =>
        CollageEditorScreen(tool: tool),
      'image/split' => SplitEditorScreen(tool: tool),
      'pdf/add-images' || 'pdf/sign' => PdfStampEditorScreen(tool: tool),
      'pdf/add-text' => PdfTextEditorScreen(tool: tool),
      'pdf/compress' => PdfCompressScreen(tool: tool),
      'pdf/create' =>
        PdfDocEditorScreen(tool: tool, mode: PdfDocMode.create),
      'pdf/edit' => PdfDocEditorScreen(tool: tool, mode: PdfDocMode.edit),
      'pdf/crop' => PdfRectEditorScreen(tool: tool, mode: PdfRectMode.crop),
      'pdf/remove-watermark' =>
        PdfRectEditorScreen(tool: tool, mode: PdfRectMode.erase),
      'pdf/delete' =>
        PdfPagesEditorScreen(tool: tool, mode: PdfPagesMode.delete),
      'pdf/rearrange' =>
        PdfPagesEditorScreen(tool: tool, mode: PdfPagesMode.rearrange),
      'pdf/merge' => PdfMergeEditorScreen(tool: tool),
      _ => GenericToolScreen(tool: tool),
    };
