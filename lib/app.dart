import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/ui/home/app_shell.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/theme.dart';

/// Root app widget. Stateful so it can own the Android share-intent listener.
class AnvilApp extends ConsumerStatefulWidget {
  const AnvilApp({super.key});

  @override
  ConsumerState<AnvilApp> createState() => _AnvilAppState();
}

class _AnvilAppState extends ConsumerState<AnvilApp> {
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    // Files shared while the app is running.
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(_onShared);
    // A file that launched the app via share intent.
    ReceiveSharingIntent.instance.getInitialMedia().then((v) {
      _onShared(v);
      ReceiveSharingIntent.instance.reset();
    });
  }

  void _onShared(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final f = files.first; // Phase 0: single-file ingest.
    ref.read(pendingSharedInputProvider.notifier).state = InputFile(
      path: f.path,
      name: f.path.split('/').last,
    );
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anvil',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ref.watch(themeModeProvider),
      home: const AppShell(),
    );
  }
}
