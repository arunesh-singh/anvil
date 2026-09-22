/// Proves the Settings footer surfaces the app version *and* build number from
/// the platform package metadata — which Flutter derives from pubspec's
/// `version: <name>+<build>` — so a pubspec bump shows up with no code change.
///
/// The other providers Settings reads are stubbed; only [appVersionProvider]
/// runs for real, against a mocked [PackageInfo].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/settings/settings_screen.dart';
import 'package:anvil/ui/theme.dart';

/// Fixed theme/retention notifiers so the screen never reaches into
/// `getIt<SettingsRepository>` during the test.
class _FakeTheme extends ThemeModeNotifier {
  @override
  ThemeMode build() => ThemeMode.dark;
}

class _FakeRetention extends RetentionNotifier {
  @override
  int build() => 30;
}

Widget _app() => ProviderScope(
      overrides: [
        themeModeProvider.overrideWith(_FakeTheme.new),
        retentionProvider.overrideWith(_FakeRetention.new),
        cacheBytesProvider.overrideWith((_) => Future.value(0)),
        logCountsProvider
            .overrideWith((_) => Future.value((total: 0, errors: 0))),
      ],
      child: MaterialApp(
        theme: darkTheme,
        home: const Scaffold(body: SettingsScreen()),
      ),
    );

void main() {
  setUp(() {
    getIt.registerSingleton<ToolRegistry>(ToolRegistry(const []));
  });

  tearDown(() async => getIt.reset());

  testWidgets('the footer shows the pubspec version and build number',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Anvil',
      packageName: 'com.arunesh.anvil',
      version: '1.2.3',
      buildNumber: '7',
      buildSignature: '',
    );
    // The footer is the last ListView child; a tall surface renders it without
    // scrolling (ListView builds children lazily).
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Version name with the build number in parentheses — updates whenever
    // pubspec's `version:` (e.g. 1.2.3+7) changes.
    expect(find.textContaining('1.2.3 (7)'), findsOneWidget);
    // The old hardcoded value must be gone.
    expect(find.textContaining('Anvil 1.0.0 '), findsNothing);
  });
}
