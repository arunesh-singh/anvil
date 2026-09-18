import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anvil/core/tool_module.dart' show ModelSpec;
import 'package:anvil/models/device_caps.dart';
import 'package:anvil/models/downloader.dart';
import 'package:anvil/models/manifest.dart';
import 'package:anvil/models/manifest_loader.dart';
import 'package:anvil/models/model_cache.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scriptable HTTP adapter: each request pops the next handler.
class _FakeAdapter implements HttpClientAdapter {
  final _handlers = <ResponseBody Function(RequestOptions)>[];
  final requests = <RequestOptions>[];

  void enqueue(ResponseBody Function(RequestOptions) handler) =>
      _handlers.add(handler);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (_handlers.isEmpty) {
      throw DioException.connectionError(
          requestOptions: options, reason: 'no scripted response');
    }
    return _handlers.removeAt(0)(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(String s, int status, {Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(s, status,
        headers: headers ?? {}, );

ResponseBody _bytes(List<int> b, int status,
        {Map<String, List<String>>? headers}) =>
    ResponseBody.fromBytes(b, status, headers: headers ?? {});

/// A [ResponseBody] that emits [partial] then drops the connection mid-stream,
/// mimicking the HF CDN closing the socket while receiving data.
ResponseBody _dropBody(List<int> partial, int status,
    {Map<String, List<String>>? headers}) {
  final c = StreamController<Uint8List>();
  if (partial.isNotEmpty) c.add(Uint8List.fromList(partial));
  c.addError(const SocketException('Connection closed while receiving data'));
  c.close();
  return ResponseBody(c.stream, status, headers: headers ?? {});
}

Dio _dio(_FakeAdapter adapter) => Dio()..httpClientAdapter = adapter;

String _manifestJson({int version = 3}) => jsonEncode({
      'manifestVersion': version,
      'models': {
        'image.remove-bg': {
          'variants': [
            {
              'id': 'small',
              'tier': 'fast',
              'url': 'https://cdn.test/models/small.onnx',
              'sha256': 'a' * 64,
              'sizeBytes': 100,
              'runtime': 'onnx',
              'minRamGb': 2,
              'accelerator': 'cpu',
              'version': '1.0.0',
            },
            {
              'id': 'big',
              'tier': 'quality',
              'url': 'https://cdn.test/models/big.onnx',
              'sha256': 'b' * 64,
              'sizeBytes': 1000,
              'runtime': 'onnx',
              'minRamGb': 4,
              'accelerator': 'gpu',
              'version': '1.0.0',
            },
          ],
        },
      },
    });

/// A single `task`-runtime variant map, tunable per test. Omitting [family] or
/// [maxTokens] exercises the backward-compatible defaults.
Map<String, dynamic> _qwenVariant({
  String id = 'q',
  String tier = 'fast',
  int minRamGb = 6,
  Object? family = 'qwen3',
  Object? maxTokens = 8192,
}) => {
      'id': id,
      'tier': tier,
      'url': 'https://cdn.test/models/$id.litertlm',
      'sha256': 'c' * 64,
      'sizeBytes': 100,
      'runtime': 'task',
      'minRamGb': minRamGb,
      'accelerator': 'gpu',
      'version': '1.0.0',
      'family': ?family,
      'maxTokens': ?maxTokens,
    };

/// A manifest carrying a single `agent.llm.qwen` chat task with [variants].
String _qwenManifest(List<Map<String, dynamic>> variants, {int version = 4}) =>
    jsonEncode({
      'manifestVersion': version,
      'models': {
        'agent.llm.qwen': {'chat': true, 'variants': variants},
      },
    });

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('anvil_models');
  });

  tearDown(() => tmp.delete(recursive: true));

  group('manifest parsing', () {
    test('parses a valid manifest', () {
      final m = Manifest.fromJsonString(_manifestJson());
      final task = m.models['image.remove-bg']!;
      expect(task.variants, hasLength(2));
      expect(task.variants.first.tier, ModelTier.fast);
      expect(task.variants.last.runtime, ModelRuntime.onnx);
    });

    test('rejects a newer manifestVersion with a clear error', () {
      expect(
        () => Manifest.fromJsonString(_manifestJson(version: 99)),
        throwsA(isA<UnsupportedManifestVersionException>()),
      );
    });

    test('rejects missing fields and bad enums', () {
      expect(() => Manifest.fromJsonString('{"models":{}}'),
          throwsA(isA<ManifestFormatException>()));
      final bad = _manifestJson().replaceFirst('"tier":"fast"', '"tier":"warp"');
      expect(() => Manifest.fromJsonString(bad),
          throwsA(isA<ManifestFormatException>()));
    });

    test('parses family and maxTokens, defaulting gemma4/4096', () {
      final m = Manifest.fromJsonString(_qwenManifest([
        _qwenVariant(id: 'q3', family: 'qwen3', maxTokens: 8192),
        _qwenVariant(id: 'legacy', family: null, maxTokens: null),
      ]));
      final vs = m.models['agent.llm.qwen']!.variants;
      expect(vs[0].family, ModelFamily.qwen3);
      expect(vs[0].maxTokens, 8192);
      expect(vs[1].family, ModelFamily.gemma4);
      expect(vs[1].maxTokens, 4096);
    });

    test('rejects maxTokens below the litertlm minimum', () {
      expect(
        () => Manifest.fromJsonString(_qwenManifest([
          _qwenVariant(maxTokens: 512),
        ])),
        throwsA(isA<ManifestFormatException>()),
      );
    });

    test('rejects an unknown model family', () {
      expect(
        () => Manifest.fromJsonString(_qwenManifest([
          _qwenVariant(family: 'bogus'),
        ])),
        throwsA(isA<ManifestFormatException>()),
      );
    });
  });

  group('ManifestLoader', () {
    test('caches body + etag, then revalidates with If-None-Match', () async {
      final adapter = _FakeAdapter();
      adapter.enqueue((_) => _body(_manifestJson(), 200, headers: {
            'etag': ['"v1"'],
          }));
      adapter.enqueue((req) {
        expect(req.headers['If-None-Match'], '"v1"');
        return _body('', 304);
      });
      final loader = ManifestLoader(
          dio: _dio(adapter), cacheDir: tmp, manifestUrl: 'https://cdn.test/m');
      final first = await loader.load();
      expect(first.models, contains('image.remove-bg'));
      final second = await loader.load(); // 304 -> served from disk cache
      expect(second.models, contains('image.remove-bg'));
      expect(adapter.requests, hasLength(2));
    });

    test('offline falls back to the cached copy', () async {
      final adapter = _FakeAdapter();
      adapter.enqueue((_) => _body(_manifestJson(), 200));
      final loader = ManifestLoader(
          dio: _dio(adapter), cacheDir: tmp, manifestUrl: 'https://cdn.test/m');
      await loader.load();
      // No scripted response -> connection error -> cache.
      final offline = await loader.load();
      expect(offline.models, contains('image.remove-bg'));
    });

    test('offline with no cache is a typed error', () async {
      final loader = ManifestLoader(
          dio: _dio(_FakeAdapter()),
          cacheDir: tmp,
          manifestUrl: 'https://cdn.test/m');
      expect(loader.load, throwsA(isA<ManifestUnavailableException>()));
    });

    test('offline with no cache falls back to the bundled manifest', () async {
      final loader = ManifestLoader(
        dio: _dio(_FakeAdapter()),
        cacheDir: tmp,
        manifestUrl: 'https://cdn.test/m',
        bundledManifest: () async => _manifestJson(),
      );
      final m = await loader.load();
      expect(m.models, contains('image.remove-bg'));
    });

    test('no configured url serves the bundled catalog with no request',
        () async {
      final adapter = _FakeAdapter();
      final loader = ManifestLoader(
        dio: _dio(adapter),
        cacheDir: tmp,
        bundledManifest: () async => _manifestJson(),
      );
      final m = await loader.load();
      expect(m.models, contains('image.remove-bg'));
      expect(adapter.requests, isEmpty);
    });

    test('a 200 body that is not a manifest falls back instead of throwing',
        () async {
      final adapter = _FakeAdapter();
      adapter.enqueue((_) => _body('<!DOCTYPE html><html>portal</html>', 200));
      final loader = ManifestLoader(
        dio: _dio(adapter),
        cacheDir: tmp,
        manifestUrl: 'https://cdn.test/m',
        bundledManifest: () async => _manifestJson(),
      );
      final m = await loader.load();
      expect(m.models, contains('image.remove-bg'));
      expect(File('${tmp.path}/manifest.json').existsSync(), isFalse);
    });
  });

  group('device gating', () {
    final manifest = Manifest.fromJsonString(_manifestJson());
    final variants = manifest.models['image.remove-bg']!.variants;

    test('low-RAM device only fits the fast/cpu variant', () {
      const caps = DeviceCaps(ramGb: 3, accelerators: {'cpu'});
      expect(caps.isCompatibleWith(variants[0]), isTrue);
      expect(caps.isCompatibleWith(variants[1]), isFalse);
    });

    test('big device fits both; gpu variant needs >= 4 GB', () {
      const caps = DeviceCaps(ramGb: 8, accelerators: {'cpu', 'nnapi'});
      expect(caps.isCompatibleWith(variants[0]), isTrue);
      expect(caps.isCompatibleWith(variants[1]), isTrue);
    });
  });

  group('ModelDownloader', () {
    test('downloads and verifies sha256', () async {
      final payload = utf8.encode('model-payload');
      final digest = sha256.convert(payload).toString();
      final adapter = _FakeAdapter();
      adapter.enqueue((_) => _bytes(payload, 200, headers: {
            'content-length': ['${payload.length}'],
          }));
      final dest = File('${tmp.path}/m.onnx');
      final progress = <(int, int)>[];
      await ModelDownloader(dio: _dio(adapter)).download(
        'https://cdn.test/m.onnx',
        dest,
        expectedSha256: digest,
        onProgress: (r, t) => progress.add((r, t)),
      );
      expect(await dest.readAsBytes(), payload);
      expect(progress.last.$1, payload.length);
      expect(File('${dest.path}.part').existsSync(), isFalse);
    });

    test('resumes a partial download with a Range request', () async {
      final payload = utf8.encode('0123456789');
      final digest = sha256.convert(payload).toString();
      final dest = File('${tmp.path}/m.onnx');
      await File('${dest.path}.part').writeAsBytes(payload.sublist(0, 4));
      final adapter = _FakeAdapter();
      adapter.enqueue((req) {
        expect(req.headers['Range'], 'bytes=4-');
        return _bytes(payload.sublist(4), 206, headers: {
          'content-length': ['${payload.length - 4}'],
        });
      });
      await ModelDownloader(dio: _dio(adapter)).download(
          'https://cdn.test/m.onnx', dest, expectedSha256: digest);
      expect(await dest.readAsString(), '0123456789');
    });

    test('sha mismatch retries exactly once, then throws', () async {
      final adapter = _FakeAdapter();
      adapter.enqueue((_) => _bytes(utf8.encode('corrupt-1'), 200));
      adapter.enqueue((_) => _bytes(utf8.encode('corrupt-2'), 200));
      final dest = File('${tmp.path}/m.onnx');
      await expectLater(
        ModelDownloader(dio: _dio(adapter)).download(
            'https://cdn.test/m.onnx', dest, expectedSha256: 'f' * 64),
        throwsA(isA<ModelIntegrityException>()),
      );
      expect(adapter.requests, hasLength(2));
      expect(dest.existsSync(), isFalse);
    });

    test('retries a mid-stream drop, resuming from .part', () async {
      final payload = utf8.encode('0123456789abcdef');
      final digest = sha256.convert(payload).toString();
      final dest = File('${tmp.path}/m.onnx');
      final adapter = _FakeAdapter();
      // First transfer delivers 6 bytes, then the socket drops.
      adapter.enqueue((req) {
        expect(req.headers['Range'], isNull);
        return _dropBody(payload.sublist(0, 6), 200,
            headers: {'content-length': ['${payload.length}']});
      });
      // The retry resumes from byte 6 with a Range request.
      adapter.enqueue((req) {
        expect(req.headers['Range'], 'bytes=6-');
        return _bytes(payload.sublist(6), 206,
            headers: {'content-length': ['${payload.length - 6}']});
      });
      await ModelDownloader(dio: _dio(adapter), retryDelay: Duration.zero)
          .download('https://cdn.test/m.onnx', dest, expectedSha256: digest);
      expect(await dest.readAsBytes(), payload);
      expect(adapter.requests, hasLength(2));
    });

    test('gives up with ModelDownloadException after exhausting retries',
        () async {
      final dest = File('${tmp.path}/m.onnx');
      final adapter = _FakeAdapter()
        ..enqueue((_) => _dropBody(const [], 200))
        ..enqueue((_) => _dropBody(const [], 200));
      await expectLater(
        ModelDownloader(
          dio: _dio(adapter),
          maxNetworkRetries: 1,
          retryDelay: Duration.zero,
        ).download('https://cdn.test/m.onnx', dest, expectedSha256: 'f' * 64),
        throwsA(isA<ModelDownloadException>()),
      );
      expect(adapter.requests, hasLength(2));
    });
  });

  group('ModelCache', () {
    test('LRU evicts the oldest entries past the byte ceiling', () async {
      final cache = ModelCache(baseDir: tmp, maxBytes: 250);
      Future<void> put(String task, List<int> bytes) async {
        final f = cache.fileFor(task, '1', 'v', 'm.bin');
        await f.create(recursive: true);
        await f.writeAsBytes(bytes);
        await cache.touch(task, '1', 'v');
      }

      await put('a', List.filled(100, 1));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await put('b', List.filled(100, 2));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await put('c', List.filled(100, 3)); // 300 bytes > 250 -> evict 'a'

      final left = await cache.cachedModels();
      expect(left.map((m) => m.taskId).toSet(), {'b', 'c'});
      expect(await cache.totalCacheBytes(), 200);
    });

    test('evict removes a task and its index entries', () async {
      final cache = ModelCache(baseDir: tmp);
      final f = cache.fileFor('t', '1', 'v', 'm.bin');
      await f.create(recursive: true);
      await f.writeAsBytes([1, 2, 3]);
      await cache.touch('t', '1', 'v');
      await cache.evict('t');
      expect(await cache.cachedModels(), isEmpty);
      expect(await cache.totalCacheBytes(), 0);
    });
  });

  group('ModelManager', () {
    (ModelManager, _FakeAdapter) build({int ramGb = 8}) {
      final adapter = _FakeAdapter();
      final dio = _dio(adapter);
      final manager = ModelManager(
        loader: ManifestLoader(
            dio: dio,
            cacheDir: Directory('${tmp.path}/manifest'),
            manifestUrl: 'https://cdn.test/m'),
        downloader: ModelDownloader(dio: dio),
        cache: ModelCache(baseDir: Directory('${tmp.path}/cache')),
        capsProvider: FixedDeviceCapsProvider(
            DeviceCaps(ramGb: ramGb, accelerators: const {'cpu'})),
      );
      return (manager, adapter);
    }

    /// Manifest whose single variant hash matches [payload].
    String manifestFor(List<int> payload) => jsonEncode({
          'manifestVersion': 3,
          'models': {
            'image.remove-bg': {
              'variants': [
                {
                  'id': 'small',
                  'tier': 'fast',
                  'url': 'https://cdn.test/models/small.onnx',
                  'sha256': sha256.convert(payload).toString(),
                  'sizeBytes': payload.length,
                  'runtime': 'onnx',
                  'minRamGb': 2,
                  'accelerator': 'cpu',
                  'version': '1.0.0',
                },
              ],
            },
          },
        });

    test('ensureReady downloads once, then serves from cache', () async {
      final payload = utf8.encode('the-model');
      final (manager, adapter) = build();
      adapter.enqueue((_) => _body(manifestFor(payload), 200));
      adapter.enqueue((_) => _bytes(payload, 200));

      const spec = ModelSpec(taskId: 'image.remove-bg');
      final loaded = await manager.ensureReady(spec);
      expect(await File(loaded.filePath).readAsBytes(), payload);
      expect(loaded.variant.id, 'small');
      expect(await manager.status('image.remove-bg'), ModelStatus.cached);

      // 4 requests total: manifest + payload for the first ensureReady, one
      // (offline -> disk-cache fallback) revalidation attempt from status(),
      // and one manifest revalidation for the second ensureReady. No second
      // payload download.
      adapter.enqueue((_) => _body(manifestFor(payload), 200));
      final again = await manager.ensureReady(spec);
      expect(again.filePath, loaded.filePath);
      expect(adapter.requests, hasLength(4));
    });

    test('concurrent ensureReady calls coalesce into one flow', () async {
      final payload = utf8.encode('coalesced');
      final (manager, adapter) = build();
      adapter.enqueue((_) => _body(manifestFor(payload), 200));
      adapter.enqueue((_) => _bytes(payload, 200));

      const spec = ModelSpec(taskId: 'image.remove-bg');
      final results =
          await Future.wait([manager.ensureReady(spec), manager.ensureReady(spec)]);
      expect(results[0].filePath, results[1].filePath);
      // One manifest fetch + one payload fetch, not two of each.
      expect(adapter.requests, hasLength(2));
    });

    test('no compatible variant -> IncompatibleDeviceException', () async {
      final (manager, adapter) = build(ramGb: 1);
      adapter.enqueue((_) => _body(_manifestJson(), 200));
      expect(
        () => manager.ensureReady(const ModelSpec(taskId: 'image.remove-bg')),
        throwsA(isA<IncompatibleDeviceException>()),
      );
    });

    test('unknown task id -> UnknownModelTaskException', () async {
      final (manager, adapter) = build();
      adapter.enqueue((_) => _body(_manifestJson(), 200));
      expect(
        () => manager.ensureReady(const ModelSpec(taskId: 'nope')),
        throwsA(isA<UnknownModelTaskException>()),
      );
    });

    test('availableModels lists each task with the device-selected variant',
        () async {
      final (manager, adapter) = build(ramGb: 8); // >= 6 GB -> quality
      adapter.enqueue((_) => _body(_manifestJson(), 200));
      final list = await manager.availableModels();
      expect(list, hasLength(1));
      final m = list.single;
      expect(m.taskId, 'image.remove-bg');
      expect(m.compatible, isTrue);
      expect(m.cached, isFalse);
      expect(m.variant.id, 'big');
    });

    test('availableModels still lists an incompatible task as its leanest variant',
        () async {
      final (manager, adapter) = build(ramGb: 1);
      adapter.enqueue((_) => _body(_manifestJson(), 200));
      final m = (await manager.availableModels()).single;
      expect(m.compatible, isFalse);
      expect(m.variant.id, 'small');
    });

    test('importModel copies a matching local file into the cache', () async {
      final payload = utf8.encode('imported-model');
      final (manager, adapter) = build();
      adapter.enqueue((_) => _body(manifestFor(payload), 200));

      final src = File('${tmp.path}/picked.onnx')..writeAsBytesSync(payload);
      final loaded = await manager.importModel('image.remove-bg', src.path);

      expect(await File(loaded.filePath).readAsBytes(), payload);
      expect(loaded.variant.id, 'small');
      // No payload HTTP fetch — only the manifest load.
      expect(adapter.requests, hasLength(1));

      adapter.enqueue((_) => _body(manifestFor(payload), 200));
      expect(await manager.status('image.remove-bg'), ModelStatus.cached);
    });

    test('importModel rejects a file whose checksum does not match', () async {
      final payload = utf8.encode('the-real-model');
      final (manager, adapter) = build();
      adapter.enqueue((_) => _body(manifestFor(payload), 200));

      final wrong = File('${tmp.path}/wrong.onnx')
        ..writeAsBytesSync(utf8.encode('a different file'));
      await expectLater(
        () => manager.importModel('image.remove-bg', wrong.path),
        throwsA(isA<ModelIntegrityException>()),
      );
      // Nothing was committed to the cache.
      adapter.enqueue((_) => _body(manifestFor(payload), 200));
      expect(await manager.status('image.remove-bg'), ModelStatus.notCached);
    });

    test('an 8 GB device selects the Qwen3 quality variant', () async {
      final (manager, adapter) = build(ramGb: 8);
      adapter.enqueue((_) => _body(
          _qwenManifest([
            _qwenVariant(id: 'q17', tier: 'fast', minRamGb: 6),
            _qwenVariant(id: 'q4b', tier: 'quality', minRamGb: 8),
          ]),
          200));
      final m = (await manager.availableModels()).single;
      expect(m.variant.id, 'q4b');
      expect(m.variant.family, ModelFamily.qwen3);
      expect(m.variant.maxTokens, 8192);
      expect(m.compatible, isTrue);
    });

    test('a 6 GB device falls back to the Qwen3 fast variant', () async {
      final (manager, adapter) = build(ramGb: 6);
      adapter.enqueue((_) => _body(
          _qwenManifest([
            _qwenVariant(id: 'q17', tier: 'fast', minRamGb: 6),
            _qwenVariant(id: 'q4b', tier: 'quality', minRamGb: 8),
          ]),
          200));
      final m = (await manager.availableModels()).single;
      expect(m.variant.id, 'q17');
      expect(m.variant.family, ModelFamily.qwen3);
      expect(m.compatible, isTrue);
    });

    test('a 4 GB device fits no Qwen3 variant', () async {
      final (manager, adapter) = build(ramGb: 4);
      adapter.enqueue((_) => _body(
          _qwenManifest([
            _qwenVariant(id: 'q17', tier: 'fast', minRamGb: 6),
            _qwenVariant(id: 'q4b', tier: 'quality', minRamGb: 8),
          ]),
          200));
      expect(
        () => manager.ensureReady(const ModelSpec(taskId: 'agent.llm.qwen')),
        throwsA(isA<IncompatibleDeviceException>()),
      );
    });
  });
}
