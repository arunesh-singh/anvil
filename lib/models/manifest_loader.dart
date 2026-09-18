/// Loads the model catalog: optional remote fetch with an ETag disk cache,
/// then the last good cached copy, then the manifest bundled in the app.
///
/// MODEL_DELIVERY.md flow step 1: "fetch manifest (cached, ETag)". Offline
/// falls back to the last good copy; no cache and no network is a typed error
/// the UI can phrase as "connect once to download this tool's model".
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/models/manifest.dart';

/// No cached manifest and the network fetch failed.
class ManifestUnavailableException implements Exception {
  final String message;
  const ManifestUnavailableException(this.message);
  @override
  String toString() => 'ManifestUnavailableException: $message';
}

class ManifestLoader {
  ManifestLoader({
    required this.dio,
    required this.cacheDir,
    this.manifestUrl,
    this.bundledManifest,
  });

  final Dio dio;
  final Directory cacheDir;
  final String? manifestUrl;

  /// Returns the JSON of a manifest shipped inside the app bundle. Used as the
  /// last-resort source when the network is unreachable and nothing has been
  /// cached yet, so the model catalog is populated on a fresh, offline
  /// install. Null in unit tests.
  final Future<String> Function()? bundledManifest;

  File get _bodyFile => File(p.join(cacheDir.path, 'manifest.json'));
  File get _etagFile => File(p.join(cacheDir.path, 'manifest.etag'));

  /// Fetches (or revalidates) the manifest when a URL is configured. A missing
  /// URL, a network failure, or a body that is not a valid manifest all fall
  /// back to the last cached copy, then to the bundled catalog; only the
  /// parsed result is ever cached.
  Future<Manifest> load() async {
    final url = manifestUrl;
    if (url == null || url.isEmpty) {
      return _fromCache('no remote catalog is configured');
    }
    final cachedEtag =
        await _etagFile.exists() ? await _etagFile.readAsString() : null;
    Response<String> response;
    try {
      response = await dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            if (cachedEtag != null && cachedEtag.isNotEmpty)
              'If-None-Match': cachedEtag,
          },
          // 304 must not throw; other non-2xx handled below.
          validateStatus: (s) => s != null && (s == 304 || s < 400),
        ),
      );
    } on DioException {
      return _fromCache('the manifest could not be downloaded');
    }

    if (response.statusCode == 304) {
      return _fromCache('the server returned 304 but no cached copy exists');
    }

    final body = response.data ?? '';
    final Manifest manifest;
    try {
      manifest = Manifest.fromJsonString(body);
    } on Exception {
      // A captive portal / parked domain answers 200 with HTML. Falling back
      // keeps every model-backed tool working; caching it would poison them.
      return _fromCache('the downloaded catalog was not a valid manifest');
    }
    await cacheDir.create(recursive: true);
    await _bodyFile.writeAsString(body);
    final etag = response.headers.value('etag');
    if (etag != null) {
      await _etagFile.writeAsString(etag);
    } else if (await _etagFile.exists()) {
      await _etagFile.delete();
    }
    return manifest;
  }

  Future<Manifest> _fromCache(String why) async {
    if (await _bodyFile.exists()) {
      return Manifest.fromJsonString(await _bodyFile.readAsString());
    }
    if (bundledManifest != null) {
      return Manifest.fromJsonString(await bundledManifest!());
    }
    throw ManifestUnavailableException(
        'No model catalog available — $why. Connect to the internet once '
        'to set up this tool.');
  }
}
