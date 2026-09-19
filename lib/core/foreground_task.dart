/// Keeps Anvil's process alive, unfrozen and de-prioritised for the OOM killer
/// while a long on-device job runs — so the user can leave the app (or blank
/// the screen) mid-task and come back to a finished result.
///
/// Android freezes cached processes (App Freezer, 12+) and kills the largest
/// ones first under memory pressure; an app holding a multi-GB LLM is the
/// first candidate. A foreground service with an ongoing notification opts the
/// process out of both for as long as a hold is held — nothing more. It does
/// NOT move work off the main isolate (that already happens: the LiteRT-LM
/// engine decodes on native threads) and it cannot survive a process death.
///
/// Holds are keyed by owner and idempotent: `hold(owner, label)` twice is one
/// hold, and the service stops when the last owner releases.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/di.dart';

/// Owner keys — one per long-running subsystem, so overlapping work (a chat
/// turn during a model download) keeps a single service running.
const String keepAliveChat = 'chat';
const String keepAliveTool = 'tool';
const String keepAliveDownload = 'download';

class ForegroundKeepAlive {
  ForegroundKeepAlive({MethodChannel? channel, bool? supported})
      : _channel = channel ?? const MethodChannel(_channelName),
        _supported = supported ?? Platform.isAndroid;

  static const String _channelName = 'anvil/foreground';

  final MethodChannel _channel;

  /// Android-only: iOS has no equivalent (a backgrounded app gets seconds).
  final bool _supported;

  final Map<String, String> _holds = {};

  /// Owners currently holding the service up, in insertion order.
  Iterable<String> get holders => _holds.keys;

  bool get active => _holds.isNotEmpty;

  /// Takes (or re-labels) [owner]'s hold and starts the service if needed.
  /// [label] is the notification text the user sees while away from the app.
  Future<void> hold(String owner, String label) async {
    final unchanged = _holds[owner] == label;
    _holds[owner] = label;
    if (unchanged) return;
    await _invoke('start', {'label': label});
  }

  /// Drops [owner]'s hold; the service stops when none remain. The surviving
  /// hold's label is restored so the notification never names finished work.
  Future<void> release(String owner) async {
    if (_holds.remove(owner) == null) return;
    if (_holds.isEmpty) {
      await _invoke('stop', const {});
      return;
    }
    await _invoke('start', {'label': _holds.values.last});
  }

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      // A refused foreground service (policy, permissions) must never fail the
      // work it was protecting — the job just stays foreground-only.
      logWarning(logSourceApp, 'Background keep-alive unavailable',
          detail: e.message);
    } on MissingPluginException {
      // Host tests / unsupported embedder.
    }
  }
}

/// Mirrors `app_log`'s accessor: the keep-alive is protective plumbing, never
/// a precondition for the work it protects, so an unregistered locator (host
/// tests, early boot) degrades to a no-op instead of throwing.
ForegroundKeepAlive? _service() => getIt.isRegistered<ForegroundKeepAlive>()
    ? getIt<ForegroundKeepAlive>()
    : null;

/// Claims the process for [owner], labelling the notification with [label].
Future<void> keepAliveHold(String owner, String label) async =>
    _service()?.hold(owner, label);

/// Drops [owner]'s claim; the service stops when the last owner releases.
Future<void> keepAliveRelease(String owner) async =>
    _service()?.release(owner);
