/// Where a tool's input file comes from on first open: the phone's recent
/// photos/videos (photo_manager), the camera (image_picker), the file picker,
/// or the clipboard (`anvil/clipboard` channel — Flutter's Clipboard is
/// text-only). One seam ([MediaSources]) so the picker widget stays
/// host-testable; [mediaSourcesProvider] is overridden in widget tests.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';

/// What a tool consumes, which decides the picker's sources and copy.
enum MediaKind { image, video, file }

const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'bmp'};
const _videoExts = {'mp4', 'mov', 'mkv', 'avi', 'webm', '3gp'};

/// [MediaKind.image] / [MediaKind.video] only when every accepted extension
/// is of that kind; mixed or non-media tools pick plain files.
MediaKind mediaKindFor(ToolMeta meta) {
  final exts = meta.acceptedExtensions;
  if (exts.isEmpty) return MediaKind.file;
  if (exts.every(_imageExts.contains)) return MediaKind.image;
  if (exts.every(_videoExts.contains)) return MediaKind.video;
  return MediaKind.file;
}

/// Access to the phone's recent media. [limited]: Android 14+ "selected
/// photos only" — or photos granted but not videos (READ_MEDIA_VISUAL_USER_SELECTED
/// alone); the grid shows what is visible and offers to allow more.
enum RecentAccess { granted, limited, denied }

/// One recent photo/video; the full file is only resolved when chosen.
class RecentMedia {
  const RecentMedia({
    required this.id,
    required this.thumbnail,
    required this.resolve,
    this.duration,
  });

  final String id;
  final Future<Uint8List?> Function() thumbnail;
  final Future<InputFile?> Function() resolve;

  /// Videos only.
  final Duration? duration;
}

/// The picker's input sources.
abstract class MediaSources {
  Future<RecentAccess> recentAccess(MediaKind kind);

  /// Prompts for media access (or opens settings when it was refused before).
  Future<RecentAccess> requestRecentAccess(MediaKind kind);

  /// Newest first, filtered to [extensions].
  Future<List<RecentMedia>> recent(
    MediaKind kind,
    List<String> extensions, {
    int limit = 30,
  });

  Future<InputFile?> camera(MediaKind kind);

  Future<List<InputFile>> files(List<String> extensions, {bool multiple});

  /// A copied image/video, or null when the clipboard holds none.
  Future<InputFile?> paste(MediaKind kind);
}

final mediaSourcesProvider = Provider<MediaSources>(
  (_) => DeviceMediaSources(),
);

/// Lowercase extension of [name] without the dot; 'jpeg' stays 'jpeg'.
String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// The real sources. Every call degrades to "nothing" on plugin failure
/// (host tests, OEM quirks) — a broken source must not break the picker.
class DeviceMediaSources implements MediaSources {
  static const _clipboard = MethodChannel('anvil/clipboard');

  PermissionRequestOption _option(MediaKind kind) => PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: kind == MediaKind.video ? RequestType.video : RequestType.image,
      mediaLocation: false,
    ),
  );

  static RecentAccess _map(PermissionState s) => switch (s) {
    PermissionState.authorized => RecentAccess.granted,
    PermissionState.limited => RecentAccess.limited,
    _ => RecentAccess.denied,
  };

  @override
  Future<RecentAccess> recentAccess(MediaKind kind) async {
    if (kind == MediaKind.file) return RecentAccess.denied;
    try {
      return _map(
        await PhotoManager.getPermissionState(requestOption: _option(kind)),
      );
    } catch (_) {
      return RecentAccess.denied;
    }
  }

  @override
  Future<RecentAccess> requestRecentAccess(MediaKind kind) async {
    if (kind == MediaKind.file) return RecentAccess.denied;
    try {
      final option = _option(kind);
      var state = await PhotoManager.requestPermissionExtend(
        requestOption: option,
      );
      if (state == PermissionState.limited) {
        // A limited grant never re-prompts through requestPermissionExtend
        // (e.g. photos-only selection while this tool wants videos); the
        // Android 14+ re-selection dialog is the documented way to widen it.
        await PhotoManager.presentLimited(
          type: kind == MediaKind.video ? RequestType.video : RequestType.image,
        );
        state = await PhotoManager.getPermissionState(requestOption: option);
      }
      // Android returns "denied" without a dialog once the user refused
      // twice; settings is then the only way back.
      if (!state.hasAccess) await PhotoManager.openSetting();
      return _map(state);
    } catch (e) {
      logWarning(logSourceTool, 'Media permission request failed: $e');
      return RecentAccess.denied;
    }
  }

  @override
  Future<List<RecentMedia>> recent(
    MediaKind kind,
    List<String> extensions, {
    int limit = 30,
  }) async {
    if (kind == MediaKind.file) return const [];
    try {
      final assets = await PhotoManager.getAssetListPaged(
        page: 0,
        // Over-fetch: formats the tool rejects (gif, heic…) are dropped below.
        pageCount: limit * 2,
        type: kind == MediaKind.video ? RequestType.video : RequestType.image,
        filterOption: FilterOptionGroup(
          orders: const [OrderOption(type: OrderOptionType.createDate)],
        ),
      );
      final accepted = extensions.map((e) => e.toLowerCase()).toSet();
      return [
        for (final a in assets)
          if (_acceptsMime(a.mimeType, accepted))
            RecentMedia(
              id: a.id,
              duration: kind == MediaKind.video ? a.videoDuration : null,
              thumbnail: () =>
                  a.thumbnailDataWithSize(const ThumbnailSize.square(240)),
              resolve: () async {
                final file = await a.originFile;
                if (file == null) return null;
                final title = await a.titleAsync;
                final name = title.isEmpty ? file.uri.pathSegments.last : title;
                return InputFile(path: file.path, name: name);
              },
            ),
      ].take(limit).toList();
    } catch (e) {
      logWarning(logSourceTool, 'Recent media unavailable: $e');
      return const [];
    }
  }

  /// Unknown MIME passes; the tool re-checks the extension on resolve.
  static bool _acceptsMime(String? mime, Set<String> accepted) {
    if (mime == null || !mime.contains('/')) return true;
    final sub = mime.split('/').last.toLowerCase();
    final ext = switch (sub) {
      'jpeg' => 'jpg',
      'quicktime' => 'mov',
      'x-matroska' => 'mkv',
      'x-msvideo' => 'avi',
      _ => sub,
    };
    return accepted.contains(ext) ||
        (ext == 'jpg' && accepted.contains('jpeg'));
  }

  @override
  Future<InputFile?> camera(MediaKind kind) async {
    try {
      final picker = ImagePicker();
      final x = kind == MediaKind.video
          ? await picker.pickVideo(source: ImageSource.camera)
          : await picker.pickImage(source: ImageSource.camera);
      if (x == null) return null;
      return InputFile(path: x.path, name: x.name);
    } catch (e) {
      logWarning(logSourceTool, 'Camera unavailable: $e');
      return null;
    }
  }

  @override
  Future<List<InputFile>> files(
    List<String> extensions, {
    bool multiple = false,
  }) async {
    final List<PlatformFile> picked;
    if (multiple) {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
      );
    } else {
      final one = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: extensions,
      );
      picked = one == null ? const [] : [one];
    }
    return [
      for (final f in picked)
        if (f.path != null) InputFile(path: f.path!, name: f.name),
    ];
  }

  @override
  Future<InputFile?> paste(MediaKind kind) async {
    if (kind == MediaKind.file) return null;
    try {
      final res = await _clipboard.invokeMapMethod<String, String>(
        'readMedia',
        {'mimePrefix': kind == MediaKind.video ? 'video/' : 'image/'},
      );
      final path = res?['path'];
      final name = res?['name'];
      if (path == null || name == null || _ext(name).isEmpty) return null;
      return InputFile(path: path, name: name);
    } catch (e) {
      logWarning(logSourceTool, 'Clipboard read failed: $e');
      return null;
    }
  }
}
