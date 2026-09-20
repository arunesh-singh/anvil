import 'dart:io';

import 'package:anvil/models/manifest.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/settings/models_screen.dart';
import 'package:anvil/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ModelVariant _variant({
  String id = 'v1',
  ModelTier tier = ModelTier.fast,
  int sizeBytes = 1000,
  int minRamGb = 3,
}) =>
    ModelVariant(
      id: id,
      tier: tier,
      url: 'https://cdn.test/$id.onnx',
      sha256: '0' * 64,
      sizeBytes: sizeBytes,
      runtime: ModelRuntime.onnx,
      minRamGb: minRamGb,
      accelerator: 'nnapi',
      version: '1.0.0',
    );

Widget _app(List<AvailableModel> catalog) => ProviderScope(
      overrides: [
        availableModelsProvider.overrideWith((_) => Future.value(catalog)),
        cacheBytesProvider.overrideWith((_) => Future.value(0)),
      ],
      child: MaterialApp(theme: darkTheme, home: const ModelsScreen()),
    );

void main() {
  testWidgets('catalog lists models with the right per-state action',
      (tester) async {
    final catalog = [
      AvailableModel(
        taskId: 'image.upscale',
        variant: _variant(id: 'swin2sr', sizeBytes: 32724291),
        compatible: true,
        cached: false,
      ),
      AvailableModel(
        taskId: 'image.inpaint',
        variant: _variant(id: 'lama', sizeBytes: 208044816),
        compatible: true,
        cached: true,
      ),
      AvailableModel(
        taskId: 'agent.llm',
        variant: _variant(id: 'qwen', sizeBytes: 1597913616, minRamGb: 8),
        compatible: false,
        cached: false,
      ),
    ];

    await tester.pumpWidget(_app(catalog));
    await tester.pumpAndSettle();

    // Friendly labels render for known task ids.
    expect(find.text('Upscale image'), findsOneWidget);
    expect(find.text('Object removal'), findsOneWidget);
    expect(find.text('Gemma 4 E2B'), findsOneWidget);

    // Compatible + not cached -> a download affordance.
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    // Cached -> a remove button.
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    // Incompatible -> a lock, and its subtitle explains why.
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.textContaining('Needs more memory'), findsOneWidget);
  });

  test('the bundled manifest asset is schema-valid', () {
    final body = File('assets/manifest.json').readAsStringSync();
    final manifest = Manifest.fromJsonString(body);
    // Every task the app's tools reference must exist in the shipped catalog.
    for (final taskId in const [
      'image.upscale',
      'image.colorize',
      'image.deblur',
      'image.inpaint',
      'asr.transcribe',
      'agent.llm',
      'agent.llm.needle',
    ]) {
      expect(manifest.models[taskId]?.variants, isNotEmpty,
          reason: 'missing manifest entry for $taskId');
    }
  });
}
