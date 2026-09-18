import 'package:anvil/core/registry.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/theme.dart';
import 'package:anvil/ui/tool/generic_tool_screen.dart';
import 'package:anvil/ui/widgets/slab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('multi-file tool shows "Pick files" button', (tester) async {
    final merge = ToolRegistry(buildTools()).byId('merge')!;
    expect(merge.meta.acceptsMultiple, isTrue);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: darkTheme, home: GenericToolScreen(tool: merge)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pick files'), findsOneWidget);
    expect(find.text('Pick file'), findsNothing);
  });

  testWidgets('single-file tool shows "Pick file" button', (tester) async {
    final rotate = ToolRegistry(buildTools()).byId('rotate')!;
    expect(rotate.meta.acceptsMultiple, isFalse);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: darkTheme, home: GenericToolScreen(tool: rotate)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pick file'), findsOneWidget);
    // The rotate param field renders its label.
    expect(find.text('Rotation (degrees)'), findsOneWidget);
  });

  group('model-backed tool gating (image/upscale)', () {
    final upscale = ToolRegistry(buildTools()).byId('upscale')!;

    Future<void> pump(WidgetTester tester, List<dynamic> overrides) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides.cast(),
          child: MaterialApp(
            theme: darkTheme,
            home: GenericToolScreen(tool: upscale),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    VoidCallback? runOnPressed(WidgetTester tester) =>
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed;

    testWidgets('incompatible → "more capable device" panel, Run disabled',
        (tester) async {
      expect(upscale.model, isNotNull);
      await pump(tester, [
        modelStatusProvider('image.upscale')
            .overrideWith((ref) => ModelStatus.incompatible),
      ]);

      expect(find.textContaining('more capable device'), findsOneWidget);
      expect(runOnPressed(tester), isNull);
    });

    testWidgets('notCached → download affordance renders, Run disabled',
        (tester) async {
      await pump(tester, [
        modelStatusProvider('image.upscale')
            .overrideWith((ref) => ModelStatus.notCached),
        availableModelsProvider.overrideWith((ref) async => <AvailableModel>[]),
      ]);

      expect(find.textContaining('Download'), findsWidgets);
      expect(runOnPressed(tester), isNull);
    });

    testWidgets('cached → no gate panel', (tester) async {
      await pump(tester, [
        modelStatusProvider('image.upscale')
            .overrideWith((ref) => ModelStatus.cached),
      ]);

      expect(find.textContaining('more capable device'), findsNothing);
      expect(find.textContaining('Download model'), findsNothing);
    });
  });
}
