import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/tools/converters/converter_tools.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/theme.dart';
import 'package:anvil/ui/tool/editors/split_table_screen.dart';
import 'package:anvil/ui/widgets/slab.dart';

class _FakeFileService implements FileService {
  _FakeFileService(this.csv);
  final String csv;

  @override
  Future<String> readString(String path) async => csv;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('output summary', () {
    test('states file count and the short last file', () {
      final plan = splitPlan(2140, const SplitSpec(rowsPerFile: 500));
      expect(splitSummary(plan), '5 files · last has 140 rows');
      expect(splitRunLabel(plan), 'Split into 5');
    });

    test('even and single-file plans', () {
      expect(splitSummary([100, 100]), '2 files · 100 rows each');
      expect(splitSummary([1]), '1 file · 1 row');
      expect(splitRunLabel([40]), 'Keep as 1 file');
      expect(groupDigits(1234567), '1,234,567');
    });

    test('preview reads size and only the first three rows', () {
      final p = previewCsv('a,b\n1,2\n3,4\n5,6\n7,8');
      expect(p.headers, ['a', 'b']);
      expect(p.rowCount, 4);
      expect(p.firstRows, [
        ['1', '2'],
        ['3', '4'],
        ['5', '6'],
      ]);
    });
  });

  testWidgets('a loaded CSV states its size and the split before Run', (
    tester,
  ) async {
    await getIt.reset();
    final rows = [for (var i = 0; i < 2140; i++) 'n$i,e$i,c$i'].join('\n');
    getIt.registerSingleton<FileService>(
      _FakeFileService('name,email,city\n$rows'),
    );
    addTearDown(getIt.reset);
    final tool = ToolRegistry(buildTools()).byId('converter/split-csv')!;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(pendingSharedInputProvider.notifier).state = const InputFile(
      path: '/tmp/contacts.csv',
      name: 'contacts.csv',
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: darkTheme,
            home: SplitTableScreen(tool: tool),
          ),
        ),
      );
      // Parsing runs in a real isolate.
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pumpAndSettle();

    expect(find.text('contacts.csv'), findsOneWidget);
    expect(find.text('2,140 rows · 3 columns'), findsOneWidget);
    expect(find.text('n0'), findsOneWidget);
    expect(find.text('n3'), findsNothing);
    // Default 100 rows per file.
    expect(find.text('22 files · last has 40 rows'), findsOneWidget);
    PrimaryButton run() =>
        tester.widget<PrimaryButton>(find.byType(PrimaryButton));
    expect(run().label, 'Split into 22');

    // Switching to a file count carries the current count over.
    await tester.tap(find.text('Number of files'));
    await tester.pumpAndSettle();
    expect(run().label, 'Split into 22');
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(run().label, 'Split into 21');
    expect(find.text('21 files · last has 101 rows'), findsOneWidget);
  });
}
