import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/ui/home/home_screen.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app() => ProviderScope(
  overrides: [
    registryProvider.overrideWithValue(buildTools()),
    // The bench reads history for resume/suggestions; empty keeps it off getIt.
    historyProvider.overrideWith((_) => Future.value(<HistoryRecord>[])),
  ],
  // HomeScreen is now Scaffold-less content (AppShell owns the Scaffold),
  // so provide the slab theme + a Scaffold for the test.
  child: MaterialApp(
    theme: darkTheme,
    home: const Scaffold(body: HomeScreen()),
  ),
);

void main() {
  testWidgets('search filters tools and shows empty message', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Empty query shows the bench (category rows), not individual tool rows.
    // Typing a matching query switches to the filtered tool list.
    await tester.enterText(find.byType(TextField), 'json');
    await tester.pumpAndSettle();
    expect(find.text('CSV to JSON'), findsOneWidget);

    // Non-matching query shows the empty message.
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('CSV to JSON'), findsNothing);
    expect(find.text('No tools match.'), findsOneWidget);
  });
}
