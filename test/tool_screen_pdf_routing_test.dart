import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tool/editors/pdf_doc_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_rect_editor_screen.dart';
import 'package:anvil/ui/tool/editors/pdf_stamp_editor_screen.dart';
import 'package:anvil/ui/tool/generic_tool_screen.dart';
import 'package:anvil/ui/tool/tool_screen.dart';
import 'package:anvil/ui/tool/workspace/pdf_workspace_screen.dart';
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

WorkspaceOp _op(String id) =>
    (toolScreenFor(_FakeTool(id)) as PdfWorkspaceScreen).initialOp;

void main() {
  test('page and document PDF tools open the workspace on their op', () {
    expect(_op('workspace'), WorkspaceOp.none);
    expect(_op('delete'), WorkspaceOp.none);
    expect(_op('rotate'), WorkspaceOp.none);
    expect(_op('merge'), WorkspaceOp.organize);
    expect(_op('rearrange'), WorkspaceOp.organize);
    expect(_op('compress'), WorkspaceOp.compress);
    expect(_op('add-text'), WorkspaceOp.text);
    expect(_op('sign'), WorkspaceOp.sign);
    expect(_op('crop'), WorkspaceOp.crop);
    expect(_op('split'), WorkspaceOp.split);
  });

  test('add-images, remove-watermark, create and edit keep their editors', () {
    expect(toolScreenFor(_FakeTool('add-images')), isA<PdfStampEditorScreen>());
    expect(
      toolScreenFor(_FakeTool('remove-watermark')),
      isA<PdfRectEditorScreen>(),
    );
    final create = toolScreenFor(_FakeTool('create')) as PdfDocEditorScreen;
    expect(create.mode, PdfDocMode.create);
    final edit = toolScreenFor(_FakeTool('edit')) as PdfDocEditorScreen;
    expect(edit.mode, PdfDocMode.edit);
  });

  test('non-spatial PDF tools keep the generic screen', () {
    expect(toolScreenFor(_FakeTool('watermark')), isA<GenericToolScreen>());
  });
}
