import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/app.dart';
import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/native_licenses.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerNativeLicenses();
  await configureDependencies();
  _captureUncaughtErrors();
  await pruneExpiredHistory();
  runApp(const ProviderScope(child: AnvilApp()));
}

/// Routes framework and platform errors into the app log so a crash the user
/// only saw as a red screen (or nothing at all) is still recoverable from the
/// exported log. Both handlers keep forwarding to the default behaviour.
void _captureUncaughtErrors() {
  final flutterDefault = FlutterError.onError;
  FlutterError.onError = (details) {
    logError(
      logSourceApp,
      'Unhandled UI error: ${details.exceptionAsString()}',
      stack: details.stack,
      detail: details.library,
    );
    flutterDefault?.call(details);
  };
  final platformDefault = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    logError(logSourceApp, 'Unhandled error', error: error, stack: stack);
    return platformDefault?.call(error, stack) ?? false;
  };
}
