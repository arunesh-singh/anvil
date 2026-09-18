import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/editor_scaffold.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Screen for `pdf/compress`: pick a PDF, choose a compression method
/// (Optimize keeps text, Rasterize is smaller), tune quality/DPI, then run.
/// Drives the `_PdfCompress` module (params `method,quality,dpi`).
class PdfCompressScreen extends ConsumerStatefulWidget {
  const PdfCompressScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<PdfCompressScreen> createState() => _PdfCompressScreenState();
}

class _PdfCompressScreenState extends ConsumerState<PdfCompressScreen> {
  InputFile? _file;
  int? _originalBytes;

  bool _raster = false;
  int _quality = 60;
  int _dpi = 150;

  @override
  void initState() {
    super.initState();
    final shared = ref.read(pendingSharedInputProvider);
    if (shared != null && _matches(shared)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pendingSharedInputProvider.notifier).state = null;
      });
      _adopt(shared);
    }
  }

  bool _matches(InputFile f) {
    final dot = f.name.lastIndexOf('.');
    return dot >= 0 && f.name.substring(dot + 1).toLowerCase() == 'pdf';
  }

  Future<void> _pick() async {
    final res = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = res?.path;
    final name = res?.name;
    if (path == null || name == null) return;
    _adopt(InputFile(path: path, name: name));
  }

  void _adopt(InputFile f) {
    int? size;
    try {
      size = File(f.path).lengthSync();
    } catch (_) {}
    setState(() {
      _file = f;
      _originalBytes = size;
    });
  }

  void _run() {
    final f = _file;
    if (f == null) return;
    ref.read(jobProvider.notifier).start(
          widget.tool,
          ToolInput(files: [f], params: {
            'method': _raster ? 'raster' : 'optimize',
            'quality': _quality,
            'dpi': _dpi,
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    return EditorScaffold(job: ref.watch(jobProvider), builder: _buildIdle);
  }

  Widget _buildIdle(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final job = ref.watch(jobProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          EditorHeader(title: widget.tool.meta.label),
          const SizedBox(height: 16),
          if (_file == null)
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 220,
                  child: PrimaryButton(
                    label: 'Pick PDF',
                    icon: Icons.picture_as_pdf,
                    onPressed: _pick,
                  ),
                ),
              ),
            )
          else ...[
            Expanded(
              child: ListView(
                children: [
                  SlabPanel(
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf, color: c.iconStrong),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_file!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AnvilText.mono(13, color: c.onSurface)),
                              if (_originalBytes != null)
                                Text('Original: ${formatBytes(_originalBytes!)}',
                                    style: text.bodyMedium!
                                        .copyWith(color: c.muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Method', style: text.titleSmall),
                  const SizedBox(height: 8),
                  _Segmented(
                    left: 'Optimize',
                    right: 'Rasterize',
                    rightSelected: _raster,
                    onChanged: (v) => setState(() => _raster = v),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _raster
                        ? 'Renders pages to images — smallest for scans, but '
                            'text becomes non-selectable.'
                        : 'Re-encodes embedded images and keeps text selectable.',
                    style: text.bodyMedium!.copyWith(color: c.muted),
                  ),
                  const SizedBox(height: 16),
                  Text('Quality  ·  $_quality', style: text.titleSmall),
                  Slider(
                    value: _quality.toDouble(),
                    min: 10,
                    max: 95,
                    divisions: 17,
                    label: '$_quality',
                    onChanged: (v) => setState(() => _quality = v.round()),
                  ),
                  if (_raster) ...[
                    const SizedBox(height: 8),
                    Text('Resolution (DPI)', style: text.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final d in const [96, 120, 150, 200])
                          _Chip(
                            label: '$d',
                            selected: _dpi == d,
                            onTap: () => setState(() => _dpi = d),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (job is JobFailed) ...[
            const SizedBox(height: 12),
            Text(job.message, style: TextStyle(color: c.error)),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Run',
            icon: Icons.arrow_forward,
            onPressed: _file != null ? _run : null,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Two-option segmented toggle sharing the editor palette.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.left,
    required this.right,
    required this.rightSelected,
    required this.onChanged,
  });

  final String left;
  final String right;
  final bool rightSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    Widget seg(String label, bool selected, VoidCallback onTap) => Expanded(
          child: Material(
            color: selected ? c.accent : c.container,
            borderRadius: BorderRadius.circular(AnvilRadii.control),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: 48,
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? c.onAccent : c.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    return Row(
      children: [
        seg(left, !rightSelected, () => onChanged(false)),
        const SizedBox(width: 8),
        seg(right, rightSelected, () => onChanged(true)),
      ],
    );
  }
}

/// Small selectable pill used for the DPI options.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return Material(
      color: selected ? c.accent : c.container,
      borderRadius: BorderRadius.circular(AnvilRadii.chip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? c.onAccent : c.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
