/// Resumable, integrity-checked model downloads.
///
/// MODEL_DELIVERY.md: "resumable download (dio range) → sha256 verify →
/// corrupt → re-download once → fail gracefully".
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// Download kept failing after the single allowed integrity retry.
class ModelIntegrityException implements Exception {
  final String message;
  const ModelIntegrityException(this.message);
  @override
  String toString() => 'ModelIntegrityException: $message';
}

/// Network failure while fetching a model file.
class ModelDownloadException implements Exception {
  final String message;
  const ModelDownloadException(this.message);
  @override
  String toString() => 'ModelDownloadException: $message';
}

class ModelDownloader {
  ModelDownloader({
    required this.dio,
    this.maxNetworkRetries = 4,
    this.retryDelay = const Duration(seconds: 2),
  });

  final Dio dio;

  /// How many extra times a dropped transfer is retried before giving up. Each
  /// retry resumes the `.part` file via a Range request, so a flaky CDN
  /// connection (the common failure — HF xet-bridge closes mid-stream) no
  /// longer forces the user to restart a multi-GB download by hand.
  final int maxNetworkRetries;

  /// Backoff between network retries (0 in tests).
  final Duration retryDelay;

  /// Downloads [url] into [dest], resuming a partial `.part` file when the
  /// server honors Range requests, then verifies the streamed sha256 against
  /// [expectedSha256] (lowercase hex). Transient network drops are retried
  /// (resuming from `.part`); a hash mismatch gets one clean re-download.
  Future<void> download(
    String url,
    File dest, {
    required String expectedSha256,
    int? expectedSizeBytes,
    void Function(int received, int total)? onProgress,
  }) async {
    final part = File('${dest.path}.part');
    await dest.parent.create(recursive: true);

    for (var attempt = 0; attempt < 2; attempt++) {
      await _fetchWithRetry(url, part, onProgress);
      final digest = await _sha256Of(part);
      if (digest == expectedSha256) {
        if (await dest.exists()) await dest.delete();
        await part.rename(dest.path);
        return;
      }
      // Corrupt: throw the partial away so the retry starts clean.
      await part.delete();
    }
    throw const ModelIntegrityException(
        'The downloaded model failed its integrity check twice. '
        'Please try again later.');
  }

  /// Fetches into [part], retrying a dropped connection up to
  /// [maxNetworkRetries] times. The retry resumes from the bytes already on
  /// disk (see [_fetch]'s Range handling), so progress is never lost to a blip.
  Future<void> _fetchWithRetry(
    String url,
    File part,
    void Function(int, int)? onProgress,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _fetch(url, part, onProgress);
        return;
      } on ModelDownloadException {
        if (attempt >= maxNetworkRetries) rethrow;
        if (retryDelay > Duration.zero) await Future<void>.delayed(retryDelay);
      }
    }
  }

  Future<void> _fetch(
    String url,
    File part,
    void Function(int, int)? onProgress,
  ) async {
    final resumeFrom = await part.exists() ? await part.length() : 0;
    final Response<ResponseBody> response;
    try {
      response = await dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {if (resumeFrom > 0) 'Range': 'bytes=$resumeFrom-'},
          validateStatus: (s) => s == 200 || s == 206,
        ),
      );
    } on DioException catch (e) {
      throw ModelDownloadException(
          'Model download failed: ${e.message ?? e.type.name}');
    }

    // 200 means the server ignored the Range header — start over.
    final resumed = response.statusCode == 206 && resumeFrom > 0;
    final sink = await part.open(
        mode: resumed ? FileMode.writeOnlyAppend : FileMode.writeOnly);
    var received = resumed ? resumeFrom : 0;
    final contentLength =
        int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
    final total = resumed ? resumeFrom + contentLength : contentLength;
    try {
      await for (final chunk in response.data!.stream) {
        await sink.writeFrom(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } catch (e) {
      throw ModelDownloadException('Model download interrupted: $e');
    } finally {
      await sink.close();
    }
  }

  Future<String> _sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
