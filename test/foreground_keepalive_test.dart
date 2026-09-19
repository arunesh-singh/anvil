/// The background-work contract: overlapping jobs share ONE foreground
/// service, and it stops exactly when the last one finishes. Getting this
/// wrong either strands an "Anvil is working" notification forever or drops
/// the process protection while a job is still running.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/core/foreground_task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('anvil/foreground');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  ForegroundKeepAlive keepAlive() =>
      ForegroundKeepAlive(channel: channel, supported: true);

  test('the last release stops the service, earlier ones do not', () async {
    final k = keepAlive();
    await k.hold(keepAliveChat, 'Anvil is answering');
    await k.hold(keepAliveTool, 'Compress PDF');
    expect(k.active, isTrue);

    await k.release(keepAliveTool);
    expect(k.active, isTrue);
    expect(calls.where((c) => c.method == 'stop'), isEmpty);

    await k.release(keepAliveChat);
    expect(k.active, isFalse);
    expect(calls.last.method, 'stop');
  });

  test('a surviving hold re-labels the notification', () async {
    final k = keepAlive();
    await k.hold(keepAliveChat, 'Anvil is answering');
    await k.hold(keepAliveDownload, 'Downloading a model');
    await k.release(keepAliveDownload);

    expect(calls.last.method, 'start');
    expect(calls.last.arguments['label'], 'Anvil is answering');
  });

  test('re-holding the same owner and label does not re-notify', () async {
    final k = keepAlive();
    await k.hold(keepAliveTool, 'Compress PDF');
    await k.hold(keepAliveTool, 'Compress PDF');
    expect(calls.where((c) => c.method == 'start'), hasLength(1));

    // A changed label is a real update.
    await k.hold(keepAliveTool, 'Convert video');
    expect(calls.where((c) => c.method == 'start'), hasLength(2));
  });

  test('releasing an owner that never held is a no-op', () async {
    final k = keepAlive();
    await k.release(keepAliveTool);
    expect(calls, isEmpty);
    expect(k.active, isFalse);
  });

  test('an unsupported platform never touches the channel', () async {
    final k = ForegroundKeepAlive(channel: channel, supported: false);
    await k.hold(keepAliveChat, 'Anvil is answering');
    await k.release(keepAliveChat);
    expect(calls, isEmpty);
  });
}
