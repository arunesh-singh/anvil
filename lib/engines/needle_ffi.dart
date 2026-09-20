/// dart:ffi transport for the Needle 3 engine (`libneedle_ffi.so`).
///
/// The C API is "one process-global, non-thread-safe model" (third_party/
/// needle/needle.h), so every call funnels through ONE long-lived worker
/// isolate: two isolates calling `needle_complete` would corrupt the shared
/// decode state, and a short-lived isolate would re-`dlopen` and re-read the
/// 35 MB `.cact` on every turn.
///
/// [NeedleTransport] is the seam: `needle_engine.dart` maps envelopes onto
/// [LlmEvent]s against this interface, so the whole adapter is host-testable
/// with a scripted fake and no device.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Ops the worker understands; also the wire tag of a request.
const String _opLoad = 'load';
const String _opInit = 'init';
const String _opComplete = 'complete';
const String _opReset = 'reset';
const String _opExit = 'exit';

/// Sentinel the worker returns when `libneedle_ffi.so` cannot be opened —
/// Needle publishes no x86_64 Android engine, so the library is simply absent
/// on an emulator. Surfaced to the user as an unsupported-device message.
const String kNeedleUnsupportedAbi = 'unsupported-abi';

/// First `needle_complete` output buffer, in bytes. An undersized buffer does
/// NOT fail: the engine truncates and still returns a non-negative code, so
/// the only detection is a JSON parse error (see [NeedleIsolateTransport]).
const int _initialOutBytes = 128 * 1024;
const int _maxOutBytes = 1024 * 1024;

/// The plugin-free contract `NeedleChat` talks to.
abstract interface class NeedleTransport {
  /// Reads and installs the `.cact` weights. Idempotent per path.
  Future<void> load(String weightsPath);

  /// Starts a conversation: environment facts + the tool declarations
  /// (Anvil's `fnSchemaFor` shape plus `triggers`).
  Future<void> init({required String system, required String toolsJson});

  /// Runs one non-streaming turn and returns the raw JSON envelope.
  Future<String> complete(String input, {required int maxNewTokens});

  /// Clears per-conversation state; the model stays loaded.
  Future<void> reset();

  /// Tears the worker down and frees the model.
  Future<void> dispose();
}

/// Raised for every worker-side failure; [message] is already user-readable
/// except for [kNeedleUnsupportedAbi], which callers translate.
class NeedleException implements Exception {
  final String message;
  const NeedleException(this.message);
  @override
  String toString() => message;
}

/// The real transport: one worker isolate owning the process-global engine.
class NeedleIsolateTransport implements NeedleTransport {
  Isolate? _isolate;
  SendPort? _tx;
  ReceivePort? _exitPort;

  /// Serializes every op onto the worker: the engine is non-thread-safe and
  /// the protocol is strictly request/response.
  Future<void> _queue = Future<void>.value();

  Future<T> _call<T>(String op, List<Object?> args) {
    final result = _queue.then((_) => _send<T>(op, args));
    // Keep the chain alive past a failed op so a later call still runs.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<T> _send<T>(String op, List<Object?> args) async {
    final tx = _tx ?? await _spawn();
    final reply = ReceivePort();
    tx.send((op, args, reply.sendPort));
    final response = await reply.first;
    reply.close();
    final (tag, payload) = response as (String, Object?);
    if (tag == 'err') throw NeedleException(payload as String);
    return payload as T;
  }

  Future<SendPort> _spawn() async {
    final handshake = ReceivePort();
    final exitPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _needleWorker,
      handshake.sendPort,
      onExit: exitPort.sendPort,
      debugName: 'needle',
    );
    final tx = await handshake.first as SendPort;
    handshake.close();
    _isolate = isolate;
    _exitPort = exitPort;
    _tx = tx;
    return tx;
  }

  @override
  Future<void> load(String weightsPath) => _call<void>(_opLoad, [weightsPath]);

  @override
  Future<void> init({required String system, required String toolsJson}) =>
      _call<void>(_opInit, [system, toolsJson]);

  @override
  Future<String> complete(String input, {required int maxNewTokens}) =>
      _call<String>(_opComplete, [input, maxNewTokens]);

  @override
  Future<void> reset() => _call<void>(_opReset, const []);

  @override
  Future<void> dispose() async {
    final tx = _tx;
    if (tx == null) return;
    _tx = null;
    try {
      // Queued behind any in-flight turn: Needle has no cancel API, so the
      // only safe teardown is after the native call returns.
      await _queue.then((_) {}, onError: (_) {});
      final reply = ReceivePort();
      tx.send((_opExit, const <Object?>[], reply.sendPort));
      await reply.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _isolate?.kill(priority: Isolate.immediate);
          return ('ok', null);
        },
      );
      reply.close();
    } catch (_) {
      _isolate?.kill(priority: Isolate.immediate);
    }
    _exitPort?.close();
    _exitPort = null;
    _isolate = null;
    _queue = Future<void>.value();
  }
}

// --- worker ---------------------------------------------------------------

typedef _LoadNative = Int32 Function(Pointer<Uint8>, Uint64);
typedef _LoadDart = int Function(Pointer<Uint8>, int);
typedef _InitNative =
    Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _InitDart = int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _CompleteNative =
    Int32 Function(Pointer<Utf8>, Int32, Pointer<Uint8>, Int32);
typedef _CompleteDart = int Function(Pointer<Utf8>, int, Pointer<Uint8>, int);
typedef _ResetNative = Void Function();
typedef _ResetDart = void Function();

/// Entry point of the worker isolate: binds the C API once, then serves
/// requests until `exit`.
void _needleWorker(SendPort handshake) {
  final rx = ReceivePort();
  handshake.send(rx.sendPort);

  _NeedleBindings? bindings;
  String? loadedPath;

  rx.listen((message) {
    final (op, args, reply) = message as (String, List<Object?>, SendPort);
    if (op == _opExit) {
      reply.send(('ok', null));
      rx.close();
      return;
    }
    try {
      bindings ??= _NeedleBindings.open();
      final b = bindings!;
      switch (op) {
        case _opLoad:
          final path = args[0] as String;
          // Load exactly once per isolate: the engine is process-global and
          // a re-load of the same weights would re-read 35 MB for nothing.
          if (loadedPath != path) {
            b.load(path);
            loadedPath = path;
          }
          reply.send(('ok', null));
        case _opInit:
          b.init(args[0] as String, args[1] as String);
          reply.send(('ok', null));
        case _opComplete:
          reply.send(('ok', b.complete(args[0] as String, args[1] as int)));
        case _opReset:
          b.reset();
          reply.send(('ok', null));
        default:
          reply.send(('err', 'unknown needle op "$op"'));
      }
    } on NeedleException catch (e) {
      reply.send(('err', e.message));
    } catch (e) {
      reply.send(('err', '$e'));
    }
  });
}

/// The bound C entry points plus the marshalling each one needs.
class _NeedleBindings {
  _NeedleBindings._(this._load, this._init, this._complete, this.reset);

  final _LoadDart _load;
  final _InitDart _init;
  final _CompleteDart _complete;
  final _ResetDart reset;

  factory _NeedleBindings.open() {
    final DynamicLibrary lib;
    try {
      lib = DynamicLibrary.open('libneedle_ffi.so');
    } catch (_) {
      throw const NeedleException(kNeedleUnsupportedAbi);
    }
    return _NeedleBindings._(
      lib.lookupFunction<_LoadNative, _LoadDart>('needle_load'),
      lib.lookupFunction<_InitNative, _InitDart>('needle_init'),
      lib.lookupFunction<_CompleteNative, _CompleteDart>('needle_complete'),
      lib.lookupFunction<_ResetNative, _ResetDart>('needle_reset'),
    );
  }

  void load(String path) {
    final bytes = File(path).readAsBytesSync();
    final buffer = malloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final rc = _load(buffer, bytes.length);
      if (rc < 0) throw NeedleException('needle_load failed ($rc)');
    } finally {
      malloc.free(buffer);
    }
  }

  void init(String system, String toolsJson) {
    final sys = system.toNativeUtf8();
    final tools = toolsJson.toNativeUtf8();
    try {
      // tool_index_path is the optional on-disk retrieval index; we hand the
      // declarations over inline instead.
      final rc = _init(sys, tools, nullptr);
      if (rc < 0) throw NeedleException('needle_init failed ($rc)');
    } finally {
      malloc.free(sys);
      malloc.free(tools);
    }
  }

  /// Runs one turn and returns the envelope text. Grows the output buffer and
  /// retries when the result does not parse: an undersized buffer truncates
  /// SILENTLY and still returns a non-negative code (observed: a 64-byte
  /// buffer returned 66 with half an envelope written), and the return value
  /// is not a byte count (a 568-byte envelope returned 129), so nothing can
  /// be sized from it.
  String complete(String input, int maxNewTokens) {
    final text = input.toNativeUtf8();
    try {
      for (var capacity = _initialOutBytes; ; capacity *= 4) {
        final out = malloc<Uint8>(capacity);
        final String raw;
        try {
          final rc = _complete(text, maxNewTokens, out, capacity);
          raw = _readCString(out, capacity);
          if (rc < 0) {
            throw NeedleException(
              raw.isEmpty ? 'needle_complete failed ($rc)' : raw,
            );
          }
        } finally {
          malloc.free(out);
        }
        try {
          jsonDecode(raw);
          return raw;
        } on FormatException {
          if (capacity >= _maxOutBytes) {
            throw const NeedleException('needle envelope did not parse');
          }
        }
      }
    } finally {
      malloc.free(text);
    }
  }
}

/// Decodes [buffer] as UTF-8 up to the first NUL (or [capacity]).
String _readCString(Pointer<Uint8> buffer, int capacity) {
  final bytes = buffer.asTypedList(capacity);
  var end = 0;
  while (end < capacity && bytes[end] != 0) {
    end++;
  }
  return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
}
