import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/editor_scaffold.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// WYSIWYG editor for `pdf/merge`: reorder the documents (each with a first-page
/// thumbnail) before concatenating. Reuses the `_ManyToPdf` merge module, which
/// concatenates in `input.files` order — so the display order is the output.
class PdfMergeEditorScreen extends ConsumerStatefulWidget {
  const PdfMergeEditorScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<PdfMergeEditorScreen> createState() =>
      _PdfMergeEditorScreenState();
}

class _PdfMergeEditorScreenState extends ConsumerState<PdfMergeEditorScreen> {
  final List<InputFile> _files = [];
  final List<Uint8List?> _thumbs = []; // null while a thumbnail is rendering

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final shared = ref.read(pendingSharedInputProvider);
    if (shared != null && _matches(shared)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pendingSharedInputProvider.notifier).state = null;
      });
      _add([shared]);
    }
  }

  bool _matches(InputFile f) {
    final dot = f.name.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = f.name.substring(dot + 1).toLowerCase();
    return widget.tool.meta.acceptedExtensions.contains(ext);
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.tool.meta.acceptedExtensions,
    );
    final picked = [
      for (final f in files)
        if (f.path != null) InputFile(path: f.path!, name: f.name),
    ];
    if (picked.isEmpty) return;
    await _add(picked);
  }

  Future<void> _add(List<InputFile> picked) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final fs = getIt<FileService>();
    final engine = getIt<PdfEngine>();
    final added = <(InputFile, Uint8List?)>[];
    for (final f in picked) {
      try {
        final bytes = await fs.readBytes(f.path) as Uint8List;
        final thumbs = await engine.renderThumbnails(bytes, maxWidth: 200);
        added.add((f, thumbs.first.bytes));
      } on ToolException catch (e) {
        setState(() => _error = e.message);
        added.add((f, null));
      }
    }
    setState(() {
      for (final (f, t) in added) {
        _files.add(f);
        _thumbs.add(t);
      }
      _loading = false;
    });
  }

  void _remove(int i) {
    setState(() {
      _files.removeAt(i);
      _thumbs.removeAt(i);
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      _files.insert(newIndex, _files.removeAt(oldIndex));
      _thumbs.insert(newIndex, _thumbs.removeAt(oldIndex));
    });
  }

  void _run() {
    if (_files.length < 2) return;
    ref.read(jobProvider.notifier).start(
          widget.tool,
          ToolInput(files: List.of(_files)),
        );
  }

  @override
  Widget build(BuildContext context) {
    return EditorScaffold(job: ref.watch(jobProvider), builder: _buildIdle);
  }

  Widget _buildIdle(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final job = ref.watch(jobProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          EditorHeader(title: widget.tool.meta.label),
          const SizedBox(height: 16),
          if (_files.isEmpty)
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 220,
                  child: PrimaryButton(
                    label: 'Pick PDFs',
                    icon: Icons.picture_as_pdf,
                    onPressed: _pick,
                  ),
                ),
              ),
            )
          else ...[
            Text('Drag to set the merge order.',
                style: TextStyle(color: c.muted)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: c.container,
                  borderRadius: BorderRadius.circular(AnvilRadii.panel),
                ),
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(12),
                child: _list(c),
              ),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Add PDFs',
              icon: Icons.add,
              onPressed: _loading ? null : _pick,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: c.error)),
          ],
          if (job is JobFailed) ...[
            const SizedBox(height: 12),
            Text(job.message, style: TextStyle(color: c.error)),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Run',
            icon: Icons.arrow_forward,
            onPressed: _files.length >= 2 ? _run : null,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _list(AnvilColors c) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: _files.length,
      onReorderItem: _reorder,
      itemBuilder: (context, i) {
        final f = _files[i];
        final thumb = _thumbs[i];
        return Padding(
          key: ValueKey(f.path + i.toString()),
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text('${i + 1}.',
                    style: AnvilText.mono(14, color: c.muted)),
              ),
              Container(
                width: 48,
                height: 64,
                decoration: BoxDecoration(
                  color: c.containerHigh,
                  borderRadius: BorderRadius.circular(AnvilRadii.chip),
                ),
                clipBehavior: Clip.antiAlias,
                child: thumb == null
                    ? const Center(child: Icon(Icons.picture_as_pdf))
                    : Image.memory(thumb, fit: BoxFit.contain),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(f.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.onSurface)),
              ),
              IconButton(
                icon: Icon(Icons.close, color: c.iconStrong),
                onPressed: () => _remove(i),
              ),
              ReorderableDelayedDragStartListener(
                index: i,
                child: Icon(Icons.drag_handle, color: c.iconStrong),
              ),
            ],
          ),
        );
      },
    );
  }
}
