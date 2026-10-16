import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/theme.dart';
import 'package:anvil/ui/tool/generic_tool_screen.dart';
import 'package:anvil/ui/tool/input/media_sources.dart';
import 'package:anvil/ui/widgets/slab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted picker sources: Files returns [files]; recents are [recent] once
/// access is granted; [access] is the current permission state, and a request
/// grants it.
class _FakeSources implements MediaSources {
  _FakeSources({
    this.files_ = const [],
    this.recent_ = const [],
    this.access = RecentAccess.granted,
  });
  final List<InputFile> files_;
  final List<RecentMedia> recent_;
  RecentAccess access;
  List<String>? askedExtensions;
  bool? askedMultiple;
  int requests = 0;

  @override
  Future<RecentAccess> recentAccess(MediaKind kind) async => access;
  @override
  Future<RecentAccess> requestRecentAccess(MediaKind kind) async {
    requests++;
    return access = RecentAccess.granted;
  }

  @override
  Future<List<RecentMedia>> recent(
    MediaKind kind,
    List<String> extensions, {
    int limit = 30,
  }) async => access == RecentAccess.granted ? recent_ : const [];
  @override
  Future<InputFile?> camera(MediaKind kind) async => null;
  @override
  Future<List<InputFile>> files(
    List<String> extensions, {
    bool multiple = false,
  }) async {
    askedExtensions = extensions;
    askedMultiple = multiple;
    return files_;
  }

  @override
  Future<InputFile?> paste(MediaKind kind) async => null;
}

void main() {
  final registry = ToolRegistry(buildTools());

  Future<void> pump(
    WidgetTester tester,
    ToolModule tool,
    MediaSources sources, [
    List<dynamic> overrides = const [],
  ]) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaSourcesProvider.overrideWithValue(sources),
          ...overrides.cast(),
        ],
        child: MaterialApp(
          theme: darkTheme,
          home: GenericToolScreen(tool: tool),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('first open shows the picker; a file from Files reveals params '
      'and enables Run', (tester) async {
    final rotate = registry.byId('rotate')!;
    final sources = _FakeSources(
      files_: const [InputFile(path: '/tmp/a.pdf', name: 'a.pdf')],
    );
    await pump(tester, rotate, sources);

    // Picker state: accepted types stated, no params, no Run yet.
    expect(find.textContaining('PDF'), findsWidgets);
    expect(find.text('Rotation (degrees)'), findsNothing);
    expect(find.text('Run'), findsNothing);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(sources.askedExtensions, rotate.meta.acceptedExtensions);
    expect(sources.askedMultiple, isFalse);
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('Rotation (degrees)'), findsOneWidget);
    final run = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, 'Run'),
    );
    expect(run.onPressed, isNotNull);
  });

  testWidgets('multi-file tool asks the file picker for several files', (
    tester,
  ) async {
    final merge = registry.byId('merge')!;
    final sources = _FakeSources();
    await pump(tester, merge, sources);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(sources.askedMultiple, isTrue);
  });

  testWidgets('a file of the wrong type is refused and the picker stays', (
    tester,
  ) async {
    final rotate = registry.byId('rotate')!;
    await pump(
      tester,
      rotate,
      _FakeSources(
        files_: const [InputFile(path: '/tmp/a.png', name: 'a.png')],
      ),
    );
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('a.png'), findsNothing);
    expect(find.text('Files'), findsOneWidget);
  });

  testWidgets('recent photo: Continue stays disabled until one is chosen', (
    tester,
  ) async {
    final grayscale = registry.byId('image/grayscale')!;
    final sources = _FakeSources(
      recent_: [
        RecentMedia(
          id: '1',
          thumbnail: () async => null,
          resolve: () async =>
              const InputFile(path: '/tmp/p.jpg', name: 'p.jpg'),
        ),
      ],
    );
    await pump(tester, grayscale, sources);
    VoidCallback? cont() => tester
        .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Continue'))
        .onPressed;

    expect(cont(), isNull);
    await tester.tap(find.byKey(const ValueKey('1')));
    await tester.pump();
    expect(cont(), isNotNull);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('p.jpg'), findsOneWidget);
  });

  testWidgets('limited media access with nothing visible offers to allow '
      'more and then shows the recents', (tester) async {
    // Photos granted but not videos: photo_manager reports "limited" and the
    // video query is empty — the picker must not dead-end on "nothing recent".
    final mute = registry.byId('video/mute')!;
    final sources = _FakeSources(
      access: RecentAccess.limited,
      recent_: [
        RecentMedia(
          id: 'v1',
          thumbnail: () async => null,
          resolve: () async =>
              const InputFile(path: '/tmp/v.mp4', name: 'v.mp4'),
        ),
      ],
    );
    await pump(tester, mute, sources);

    expect(find.text('Nothing recent on this phone.'), findsNothing);
    await tester.tap(find.text('Show all recent videos'));
    await tester.pumpAndSettle();

    expect(sources.requests, 1);
    expect(find.byKey(const ValueKey('v1')), findsOneWidget);
  });

  group('model-backed tool gating (image/upscale)', () {
    final upscale = registry.byId('upscale')!;
    final sources = _FakeSources(
      files_: const [InputFile(path: '/tmp/p.jpg', name: 'p.jpg')],
    );

    Future<VoidCallback?> pickThenRun(
      WidgetTester tester,
      List<dynamic> overrides,
    ) async {
      await pump(tester, upscale, sources, overrides);
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      return tester
          .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Run'))
          .onPressed;
    }

    testWidgets('incompatible → "more capable device" panel, Run disabled', (
      tester,
    ) async {
      expect(upscale.model, isNotNull);
      final run = await pickThenRun(tester, [
        modelStatusProvider(
          'image.upscale',
        ).overrideWith((ref) => ModelStatus.incompatible),
      ]);
      expect(find.textContaining('more capable device'), findsOneWidget);
      expect(run, isNull);
    });

    testWidgets('notCached → download affordance renders, Run disabled', (
      tester,
    ) async {
      final run = await pickThenRun(tester, [
        modelStatusProvider(
          'image.upscale',
        ).overrideWith((ref) => ModelStatus.notCached),
        availableModelsProvider.overrideWith((ref) async => <AvailableModel>[]),
      ]);
      expect(find.textContaining('Download'), findsWidgets);
      expect(run, isNull);
    });

    testWidgets('cached → no gate panel, Run enabled', (tester) async {
      final run = await pickThenRun(tester, [
        modelStatusProvider(
          'image.upscale',
        ).overrideWith((ref) => ModelStatus.cached),
      ]);
      expect(find.textContaining('more capable device'), findsNothing);
      expect(find.textContaining('Download model'), findsNothing);
      expect(run, isNotNull);
    });

    testWidgets('the gate is visible on the first-open picker too', (
      tester,
    ) async {
      await pump(tester, upscale, sources, [
        modelStatusProvider(
          'image.upscale',
        ).overrideWith((ref) => ModelStatus.incompatible),
      ]);
      expect(find.textContaining('more capable device'), findsOneWidget);
    });
  });
}
