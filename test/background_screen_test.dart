import 'dart:io';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/mlkit_engine.dart';
import 'package:anvil/tools/image/image_ml_tools.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/theme.dart';
import 'package:anvil/ui/tool/editors/background_screen.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Segmenter fake: left half of the photo is the subject.
class _FakeMlKit implements MlKitEngine {
  int calls = 0;

  @override
  Future<SubjectMask> subjectMask(String path, int width, int height) async {
    calls++;
    return SubjectMask(
      width: width,
      height: height,
      confidence: [
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++) x < width / 2 ? 1.0 : 0.0,
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records what Apply starts instead of running it.
class _RecordingJob extends JobNotifier {
  static ToolModule? tool;
  static ToolInput? input;

  @override
  Future<void> start(ToolModule t, ToolInput i) async {
    tool = t;
    input = i;
  }
}

void main() {
  test('blur strength names the tool radius bands', () {
    expect(blurStrengthLabel(blurRadiusMin), 'Subtle');
    expect(blurStrengthLabel(8), 'Light');
    expect(blurStrengthLabel(blurRadiusDefault), 'Medium');
    expect(blurStrengthLabel(20), 'Strong');
    expect(blurStrengthLabel(blurRadiusMax), 'Max');
  });

  test('each opened tool starts on its own treatment', () {
    expect(BackgroundMode.forTool('image/remove-bg'), BackgroundMode.remove);
    expect(
      BackgroundMode.forTool('image/change-bg-photo'),
      BackgroundMode.colour,
    );
    expect(
      BackgroundMode.forTool('image/blur-background'),
      BackgroundMode.blur,
    );
  });

  testWidgets('switching Blur → Colour applies change-bg-photo with the chosen '
      'colour and no mask override', (tester) async {
    await getIt.reset();
    final registry = ToolRegistry(buildImageMlTools());
    final mlkit = _FakeMlKit();
    getIt
      ..registerSingleton<ToolRegistry>(registry)
      ..registerSingleton<MlKitEngine>(mlkit);
    addTearDown(getIt.reset);

    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('anvil_bg'),
    );
    addTearDown(() => dir!.delete(recursive: true));
    final photo = img.Image(width: 8, height: 6);
    img.fill(photo, color: img.ColorRgb8(200, 100, 50));
    final path = p.join(dir!.path, 'cat.png');
    await tester.runAsync(() => File(path).writeAsBytes(img.encodePng(photo)));

    final container = ProviderContainer(
      overrides: [jobProvider.overrideWith(_RecordingJob.new)],
    );
    addTearDown(container.dispose);
    container.read(pendingSharedInputProvider.notifier).state = InputFile(
      path: path,
      name: 'cat.png',
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: darkTheme,
            home: BackgroundScreen(
              tool: registry.byId('image/blur-background')!,
            ),
          ),
        ),
      );
      // Decode + mask preparation + preview layers run in real isolates.
      for (
        var i = 0;
        i < 40 && find.text('subject found').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    await tester.pump();

    expect(find.text('subject found'), findsOneWidget);
    expect(mlkit.calls, 1, reason: 'the subject is detected once on load');
    expect(find.text('Medium · 12'), findsOneWidget);

    await tester.tap(find.text('Colour'));
    await tester.pump();
    expect(mlkit.calls, 1, reason: 'switching treatment never re-detects');

    // Swatches: white, black, grey, blue — pick black.
    await tester.tap(find.byType(WsSwatch).at(1));
    await tester.pump();
    expect(find.text('#FF000000'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pump();

    expect(_RecordingJob.tool?.meta.qualifiedId, 'image/change-bg-photo');
    expect(_RecordingJob.input?.files.single.path, path);
    expect(_RecordingJob.input?.params, {'color': '#FF000000'});
    expect(_RecordingJob.input?.params.containsKey(maskPathParam), isFalse);
  });
}
