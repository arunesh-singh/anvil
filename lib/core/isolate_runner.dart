import 'dart:async';
import 'dart:isolate';

/// Runs [computation] on a background isolate so heavy work never blocks the UI
/// thread. Tools call this instead of `Isolate.run` directly for consistency and
/// to keep a single test seam.
///
/// The closure must capture ONLY sendable values (primitives, strings, plain
/// data). NEVER capture `getIt`, `File`, sockets, or widgets — they cannot cross
/// the isolate boundary and will throw at runtime.
Future<T> runOffThread<T>(FutureOr<T> Function() computation) =>
    Isolate.run(computation);
