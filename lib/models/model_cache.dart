/// Versioned on-disk model cache with LRU eviction.
///
/// MODEL_DELIVERY.md: cache keyed by `taskId/version/variantId`; LRU with a
/// size ceiling; manual evict for the storage screen; offline once cached.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One cached model entry, as listed by the storage UI.
class CachedModel {
  final String taskId;
  final String version;
  final String variantId;
  final int bytes;
  final DateTime lastAccess;
  const CachedModel({
    required this.taskId,
    required this.version,
    required this.variantId,
    required this.bytes,
    required this.lastAccess,
  });
}

class ModelCache {
  ModelCache({required this.baseDir, this.maxBytes = 4 * 1024 * 1024 * 1024});

  final Directory baseDir;

  /// Cache ceiling in bytes; least-recently-used entries evict past it.
  final int maxBytes;

  Directory get _modelsDir => Directory(p.join(baseDir.path, 'models'));
  File get _indexFile => File(p.join(baseDir.path, 'models_index.json'));

  String _key(String taskId, String version, String variantId) =>
      '$taskId/$version/$variantId';

  /// Target file for one variant's payload.
  File fileFor(String taskId, String version, String variantId,
          String fileName) =>
      File(p.join(_modelsDir.path, taskId, version, variantId, fileName));

  /// Whether the variant's payload exists (non-empty).
  Future<bool> contains(
      String taskId, String version, String variantId, String fileName) async {
    final f = fileFor(taskId, version, variantId, fileName);
    return await f.exists() && await f.length() > 0;
  }

  /// Records an access (download completion or load) and evicts past the
  /// ceiling. Call AFTER the payload is fully written.
  Future<void> touch(String taskId, String version, String variantId) async {
    final index = await _readIndex();
    index[_key(taskId, version, variantId)] =
        DateTime.now().millisecondsSinceEpoch;
    await _writeIndex(index);
    await _evictOverCeiling(index);
  }

  /// Removes every cached version/variant of [taskId].
  Future<void> evict(String taskId) async {
    final dir = Directory(p.join(_modelsDir.path, taskId));
    if (await dir.exists()) await dir.delete(recursive: true);
    final index = await _readIndex();
    index.removeWhere((k, _) => k.startsWith('$taskId/'));
    await _writeIndex(index);
  }

  /// Lists cached entries, most recently used first.
  Future<List<CachedModel>> cachedModels() async {
    final index = await _readIndex();
    final out = <CachedModel>[];
    for (final entry in index.entries) {
      final parts = entry.key.split('/');
      if (parts.length != 3) continue;
      final dir = Directory(
          p.join(_modelsDir.path, parts[0], parts[1], parts[2]));
      final bytes = await _dirSize(dir);
      if (bytes == 0) continue;
      out.add(CachedModel(
        taskId: parts[0],
        version: parts[1],
        variantId: parts[2],
        bytes: bytes,
        lastAccess: DateTime.fromMillisecondsSinceEpoch(entry.value),
      ));
    }
    out.sort((a, b) => b.lastAccess.compareTo(a.lastAccess));
    return out;
  }

  Future<int> totalCacheBytes() => _dirSize(_modelsDir);

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<Map<String, int>> _readIndex() async {
    if (!await _indexFile.exists()) return {};
    try {
      final decoded =
          jsonDecode(await _indexFile.readAsString()) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } on FormatException {
      return {}; // Corrupt index self-heals; payloads re-register on touch.
    }
  }

  Future<void> _writeIndex(Map<String, int> index) async {
    await baseDir.create(recursive: true);
    await _indexFile.writeAsString(jsonEncode(index));
  }

  Future<void> _evictOverCeiling(Map<String, int> index) async {
    var total = await totalCacheBytes();
    if (total <= maxBytes) return;
    // Oldest first.
    final byAge = index.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final entry in byAge) {
      if (total <= maxBytes) break;
      final parts = entry.key.split('/');
      if (parts.length != 3) continue;
      final dir = Directory(
          p.join(_modelsDir.path, parts[0], parts[1], parts[2]));
      final size = await _dirSize(dir);
      if (await dir.exists()) await dir.delete(recursive: true);
      index.remove(entry.key);
      total -= size;
    }
    await _writeIndex(index);
  }

  Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final f in dir.list(recursive: true, followLinks: false)) {
      if (f is File) total += await f.length();
    }
    return total;
  }
}
