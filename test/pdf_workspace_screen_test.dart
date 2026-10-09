/// Widget test for the PDF workspace grid: selection, delete, undo and the
/// "cannot delete every page" guard, against faked engine/file services.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart' show PdfPageInfo;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/ui/theme.dart';
import 'package:anvil/ui/tool/workspace/page_thumb.dart';
import 'package:anvil/ui/tool/workspace/pdf_workspace_screen.dart';
import 'package:anvil/ui/tool/workspace/workspace_controller.dart';
import 'package:anvil/ui/widgets/slab.dart';

// 8×8 solid-red PNG.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR42mO4IyKCFTEMLQkAmD9BAeEqE6gAAAAASUVORK5CYII=',
  ),
);

class _FakePdfEngine implements PdfEngine {
  @override
  Future<List<PdfPageInfo>> pageInfos(Uint8List input) async => [
    for (var i = 0; i < 3; i++) PdfPageInfo(index: i, width: 595, height: 842),
  ];

  @override
  Future<List<PdfImageOut>> renderThumbnails(
    Uint8List input, {
    int maxWidth = 320,
    int maxHeight = 320,
  }) async => [
    for (var i = 0; i < 3; i++) PdfImageOut(_png, 'png', 'image/png'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFileService implements FileService {
  @override
  Future<List<int>> readBytes(String path) async => Uint8List.fromList([1, 2]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await getIt.reset();
    getIt
      ..registerSingleton<PdfEngine>(_FakePdfEngine())
      ..registerSingleton<FileService>(_FakeFileService());
  });

  tearDown(() => getIt.reset());

  testWidgets('select, delete, undo, and the delete-everything guard', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: lightTheme, home: const PdfWorkspaceScreen()),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PdfWorkspaceScreen)),
    );
    await tester.runAsync(
      () => container.read(pdfWorkspaceProvider.notifier).open([
        const InputFile(path: 'a.pdf', name: 'a.pdf'),
      ]),
    );
    await tester.pump();
    expect(find.textContaining('3 pages'), findsOneWidget);

    PrimaryButton export() => tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, 'Export'),
    );
    expect(export().onPressed, isNull);

    await tester.tap(find.byType(PageThumb).at(0));
    await tester.tap(find.byType(PageThumb).at(1));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(find.textContaining('1 page '), findsOneWidget);
    expect(export().onPressed, isNotNull);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(find.textContaining('3 pages'), findsOneWidget);

    await tester.tap(find.text('Select all'));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Cannot delete every page of the PDF.'), findsOneWidget);
    expect(find.textContaining('3 pages'), findsOneWidget);
  });
}
