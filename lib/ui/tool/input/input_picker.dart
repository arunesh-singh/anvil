/// The first-open body every tool screen shows before it has a file: what the
/// tool accepts, the phone's recent photos/videos, Camera / Files / Paste, and
/// Continue. Replaces the lone centred "Pick file" button (design: "Every
/// tool · first open" in `explorations/tools-workspace.html`).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/input/media_sources.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Whether [f]'s extension is one [meta] accepts.
bool toolAccepts(ToolMeta meta, InputFile f) {
  final dot = f.name.lastIndexOf('.');
  if (dot < 0) return false;
  return meta.acceptedExtensions.contains(
    f.name.substring(dot + 1).toLowerCase(),
  );
}

/// The pending shared file (Android share intent or an agent hand-off) when
/// it fits [meta]; clears it after this frame so it is consumed once. Call
/// from `initState`.
InputFile? takeSharedInput(WidgetRef ref, ToolMeta meta) {
  final shared = ref.read(pendingSharedInputProvider);
  if (shared == null || !toolAccepts(meta, shared)) return null;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.read(pendingSharedInputProvider.notifier).state = null;
  });
  return shared;
}

const _typeLabels = {
  'jpg': 'JPG',
  'jpeg': 'JPG',
  'png': 'PNG',
  'webp': 'WebP',
  'heic': 'HEIC',
  'heif': 'HEIC',
  'webm': 'WebM',
  'xlsx': 'Excel',
  'md': 'Markdown',
  'txt': 'text',
};

/// "JPG, PNG, WebP or HEIC" for [extensions].
String acceptedTypesLabel(List<String> extensions) {
  final labels = <String>[];
  for (final e in extensions) {
    final l = _typeLabels[e.toLowerCase()] ?? e.toUpperCase();
    if (!labels.contains(l)) labels.add(l);
  }
  if (labels.length < 2) return labels.join();
  return '${labels.sublist(0, labels.length - 1).join(', ')} or ${labels.last}';
}

String _defaultPrompt(ToolMeta meta, MediaKind kind) {
  final noun = switch (kind) {
    MediaKind.image => 'image',
    MediaKind.video => 'video',
    MediaKind.file => 'file',
  };
  return meta.acceptsMultiple ? 'Pick 2 or more ${noun}s.' : 'Pick the $noun.';
}

/// First-open picker. [onPicked] receives the chosen files (one unless the
/// tool accepts several). [prompt] replaces the default "Pick the image."
/// sentence; the accepted types are always appended. [footer] renders above
/// the info line (the model gate for model-backed tools).
class ToolInputPicker extends ConsumerStatefulWidget {
  const ToolInputPicker({
    super.key,
    required this.tool,
    required this.onPicked,
    this.prompt,
    this.footer,
  });

  final ToolModule tool;
  final ValueChanged<List<InputFile>> onPicked;
  final String? prompt;
  final Widget? footer;

  @override
  ConsumerState<ToolInputPicker> createState() => _ToolInputPickerState();
}

class _ToolInputPickerState extends ConsumerState<ToolInputPicker> {
  late final MediaKind _kind = mediaKindFor(widget.tool.meta);
  RecentAccess? _access;
  List<RecentMedia> _recent = const [];
  final List<RecentMedia> _chosen = [];
  bool _resolving = false;

  MediaSources get _sources => ref.read(mediaSourcesProvider);
  ToolMeta get _meta => widget.tool.meta;

  @override
  void initState() {
    super.initState();
    if (_kind != MediaKind.file) _loadRecent();
  }

  Future<void> _loadRecent() async {
    final access = await _sources.recentAccess(_kind);
    // Three rows keep Camera / Files / Paste on screen; Files covers the rest.
    final recent = access == RecentAccess.granted
        ? await _sources.recent(_kind, _meta.acceptedExtensions, limit: 9)
        : const <RecentMedia>[];
    if (!mounted) return;
    setState(() {
      _access = access;
      _recent = recent;
    });
  }

  Future<void> _allowRecent() async {
    final access = await _sources.requestRecentAccess(_kind);
    if (access != RecentAccess.denied) await _loadRecent();
  }

  void _toggle(RecentMedia m) {
    setState(() {
      if (_chosen.contains(m)) {
        _chosen.remove(m);
      } else {
        if (!_meta.acceptsMultiple) _chosen.clear();
        _chosen.add(m);
      }
    });
  }

  void _deliver(List<InputFile> files) {
    final ok = [
      for (final f in files)
        if (toolAccepts(_meta, f)) f,
    ];
    if (ok.isEmpty) {
      if (files.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.tool.meta.label} takes '
              '${acceptedTypesLabel(_meta.acceptedExtensions)}.',
            ),
          ),
        );
      }
      return;
    }
    widget.onPicked(ok);
  }

  Future<void> _continue() async {
    setState(() => _resolving = true);
    final files = <InputFile>[];
    for (final m in _chosen) {
      final f = await m.resolve();
      if (f != null) files.add(f);
    }
    if (!mounted) return;
    setState(() => _resolving = false);
    _deliver(files);
  }

  Future<void> _camera() async {
    final f = await _sources.camera(_kind);
    if (f != null) _deliver([f]);
  }

  Future<void> _files() async {
    _deliver(
      await _sources.files(
        _meta.acceptedExtensions,
        multiple: _meta.acceptsMultiple,
      ),
    );
  }

  Future<void> _paste() async {
    final f = await _sources.paste(_kind);
    if (f != null) {
      _deliver([f]);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _kind == MediaKind.video
                ? 'No copied video on the clipboard.'
                : 'No copied image on the clipboard.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    final media = _kind != MediaKind.file;
    final prompt = widget.prompt ?? _defaultPrompt(_meta, _kind);
    final types = acceptedTypesLabel(_meta.acceptedExtensions);
    final noun = switch (_kind) {
      MediaKind.image => 'Images',
      MediaKind.video => 'Videos',
      MediaKind.file => 'Files',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              const SizedBox(height: 14),
              Text(
                types.isEmpty ? prompt : '$prompt $types.',
                style: theme.textTheme.bodyLarge?.copyWith(color: c.muted),
              ),
              if (media) ...[
                const SizedBox(height: 14),
                SectionEyebrow('Recent on this phone'),
                const SizedBox(height: 8),
                _recentBody(context, c),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (media) ...[
                    Expanded(
                      child: _SourceButton(
                        icon: Icons.photo_camera,
                        label: 'Camera',
                        onTap: _camera,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.folder_open,
                      label: 'Files',
                      onTap: _files,
                    ),
                  ),
                  if (media) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SourceButton(
                        icon: Icons.content_paste,
                        label: 'Paste',
                        onTap: _paste,
                      ),
                    ),
                  ],
                ],
              ),
              if (widget.footer != null) ...[
                const SizedBox(height: 16),
                widget.footer!,
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        InfoCard('$noun never leave the phone.'),
        if (media) ...[
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Continue',
            icon: Icons.arrow_forward,
            onPressed: _chosen.isEmpty || _resolving ? null : _continue,
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _recentBody(BuildContext context, AnvilColors c) {
    final theme = Theme.of(context);
    final access = _access;
    if (access == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final noun = _kind == MediaKind.video ? 'videos' : 'photos';
    Widget allow(String label) => InkWell(
      borderRadius: BorderRadius.circular(AnvilRadii.row),
      onTap: _allowRecent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.container,
          borderRadius: BorderRadius.circular(AnvilRadii.row),
        ),
        child: Row(
          children: [
            Icon(Icons.photo_library_outlined, color: c.iconStrong),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
            Text(
              'Allow',
              style: theme.textTheme.titleSmall?.copyWith(color: c.accentText),
            ),
          ],
        ),
      ),
    );
    if (access == RecentAccess.denied) return allow('Show recent $noun');
    final limited = access == RecentAccess.limited;
    if (_recent.isEmpty) {
      return limited
          ? allow('Show all recent $noun')
          : Text(
              'Nothing recent on this phone.',
              style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
            );
    }
    final grid = GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final m in _recent)
          _RecentTile(
            key: ValueKey(m.id),
            media: m,
            order: _meta.acceptsMultiple && _chosen.contains(m)
                ? _chosen.indexOf(m) + 1
                : null,
            selected: _chosen.contains(m),
            onTap: () => _toggle(m),
          ),
      ],
    );
    if (!limited) return grid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [grid, const SizedBox(height: 8), allow('Show more $noun')],
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return Material(
      color: c.container,
      borderRadius: BorderRadius.circular(AnvilRadii.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: c.onSurface),
              const SizedBox(width: 8),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatefulWidget {
  const _RecentTile({
    super.key,
    required this.media,
    required this.selected,
    required this.onTap,
    this.order,
  });

  final RecentMedia media;
  final bool selected;
  final int? order;
  final VoidCallback onTap;

  @override
  State<_RecentTile> createState() => _RecentTileState();
}

class _RecentTileState extends State<_RecentTile> {
  late final Future<Uint8List?> _thumb = widget.media.thumbnail();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final d = widget.media.duration;
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AnvilRadii.chip),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: c.containerHigh),
            FutureBuilder<Uint8List?>(
              future: _thumb,
              builder: (_, snap) => snap.data == null
                  ? const SizedBox.shrink()
                  : Image.memory(
                      snap.data!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
            if (d != null)
              Positioned(
                left: 6,
                bottom: 6,
                child: Text(
                  '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: AnvilText.mono(11, color: Colors.white),
                ),
              ),
            if (widget.selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AnvilRadii.chip),
                  border: Border.all(color: c.accent, width: 2.5),
                ),
              ),
            if (widget.selected)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                  child: widget.order != null
                      ? Text(
                          '${widget.order}',
                          style: AnvilText.mono(11, color: c.onAccent),
                        )
                      : Icon(Icons.check, size: 15, color: c.onAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
