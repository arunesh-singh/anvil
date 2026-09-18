import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tool/editors/pdf_compress_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_doc_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_merge_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_pages_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_rect_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_stamp_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_text_editor_screen.dart';
import 'package:anvil/ui/tool/generic_tool_screen.dart';
import 'package:anvil/ui/tool/tool_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTool extends BaseToolModule {
  _FakeTool(this._id);
  final String _id;

  @override
  ToolMeta get meta => ToolMeta(
        id: _id,
        category: ToolCategory.pdf,
        label: _id,
        icon: Icons.picture_as_pdf,
        description: '',
        tinywowSlug: _id,
        acceptedExtensions: const ['pdf'],
      );

  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {}
}

void main() {
  test('spatial PDF tools route to their WYSIWYG editors', () {
    expect(toolScreenFor(_FakeTool('add-images')), isA<PdfStampEditorScreen>());
    expect(toolScreenFor(_FakeTool('sign')), isA<PdfStampEditorScreen>());
    expect(toolScreenFor(_FakeTool('add-text')), isA<PdfTextEditorScreen>());
    expect(toolScreenFor(_FakeTool('merge')), isA<PdfMergeEditorScreen>());
  });

  test('compress, create, and edit route to their custom screens', () {
    expect(toolScreenFor(_FakeTool('compress')), isA<PdfCompressScreen>());
    final create = toolScreenFor(_FakeTool('create')) as PdfDocEditorScreen;
    expect(create.mode, PdfDocMode.create);
    final edit = toolScreenFor(_FakeTool('edit')) as PdfDocEditorScreen;
    expect(edit.mode, PdfDocMode.edit);
  });

  test('crop and remove-watermark route to the rect editor by mode', () {
    final crop = toolScreenFor(_FakeTool('crop')) as PdfRectEditorScreen;
    expect(crop.mode, PdfRectMode.crop);
    final erase =
        toolScreenFor(_FakeTool('remove-watermark')) as PdfRectEditorScreen;
    expect(erase.mode, PdfRectMode.erase);
  });

  test('delete and rearrange route to the pages editor by mode', () {
    final del = toolScreenFor(_FakeTool('delete')) as PdfPagesEditorScreen;
    expect(del.mode, PdfPagesMode.delete);
    final rear = toolScreenFor(_FakeTool('rearrange')) as PdfPagesEditorScreen;
    expect(rear.mode, PdfPagesMode.rearrange);
  });

  test('non-spatial PDF tools keep the generic screen', () {
    expect(toolScreenFor(_FakeTool('rotate')), isA<GenericToolScreen>());
    expect(toolScreenFor(_FakeTool('watermark')), isA<GenericToolScreen>());
    expect(toolScreenFor(_FakeTool('split')), isA<GenericToolScreen>());
  });
}
