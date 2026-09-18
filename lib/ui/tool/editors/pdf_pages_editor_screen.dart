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

/// Which page-organization op the editor drives.
enum PdfPagesMode { delete, rearrange }

/// WYSIWYG editor for `pdf/delete` and `pdf/rearrange`: organize pages via a
/// thumbnail grid. `delete` toggles pages for removal; `rearrange` drags them
/// into a new order. Underlying `_PdfToPdf` modules unchanged (`delete`: text
/// `pages`; `rearrange`: text `order`, both 1-based comma lists).
class PdfPagesEditorScreen extends ConsumerStatefulWidget {
  const PdfPagesEditorScreen({
    super.key,
    required this.tool,
    required this.mode,
  });

  final ToolModule tool;
  final PdfPagesMode mode;

  @override
  ConsumerState<PdfPagesEditorScreen> createState() =>
      _PdfPagesEditorScreenState();
}

class _PdfPagesEditorScreenState extends ConsumerState<PdfPagesEditorScreen> {
  InputFile? _file;
  List<Uint8List> _thumbs = const [];
  Uint8List? _pdfBytes;

  /// delete: 1-based page numbers marked for removal.
  final Set<int> _marked = {};

  /// rearrange: current display order, holding original 1-based page numbers.
  List<int> _order = [];

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
      _load(shared);
    }
  }

  bool _matches(InputFile f) {
    final dot = f.name.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = f.name.substring(dot + 1).toLowerCase();
    return widget.tool.meta.acceptedExtensions.contains(ext);
  }

  Future<void> _pick() async {
    final res = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: widget.tool.meta.acceptedExtensions,
    );
    final path = res?.path;
    final name = res?.name;
    if (path == null || name == null) return;
    await _load(InputFile(path: path, name: name));
  }

  Future<void> _load(InputFile f) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await getIt<FileService>().readBytes(f.path) as Uint8List;
      final thumbs = await getIt<PdfEngine>().renderThumbnails(bytes);
      setState(() {
        _file = f;
        _pdfBytes = bytes;
        _thumbs = [for (final t in thumbs) t.bytes];
        _marked.clear();
        _order = [for (var i = 1; i <= thumbs.length; i++) i];
        _loading = false;
      });
    } on ToolException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _showPage(int pageIndex) async {
    final bytes = _pdfBytes;
    if (bytes == null) return;
    final Uint8List png;
    try {
      png = (await getIt<PdfEngine>()
              .renderPage(bytes, pageIndex, maxWidth: 2000, maxHeight: 2000))
          .bytes;
    } on ToolException {
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Center(child: Image.memory(png)),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canRun {
    if (_file == null || _thumbs.isEmpty) return false;
    if (widget.mode == PdfPagesMode.delete) {
      return _marked.isNotEmpty && _marked.length < _thumbs.length;
    }
    return true;
  }

  void _run() {
    final f = _file;
    if (f == null || !_canRun) return;
    if (widget.mode == PdfPagesMode.delete) {
      final spec = (_marked.toList()..sort()).join(',');
      ref.read(jobProvider.notifier).start(
            widget.tool,
            ToolInput(files: [f], params: {'pages': spec}),
          );
    } else {
      final spec = _order.join(',');
      ref.read(jobProvider.notifier).start(
            widget.tool,
            ToolInput(files: [f], params: {'order': spec}),
          );
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() => _order.insert(newIndex, _order.removeAt(oldIndex)));
  }

  @override
  Widget build(BuildContext context) {
    return EditorScaffold(job: ref.watch(jobProvider), builder: _buildIdle);
  }

  Widget _buildIdle(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final job = ref.watch(jobProvider);
    final isDelete = widget.mode == PdfPagesMode.delete;
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
            if (isDelete)
              Text(
                'Tap pages to mark them for deletion.',
                style: TextStyle(color: c.muted),
              )
            else
              Text(
                'Drag pages to set the new order.',
                style: TextStyle(color: c.muted),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: c.container,
                  borderRadius: BorderRadius.circular(AnvilRadii.panel),
                ),
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(12),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : (isDelete ? _deleteGrid(c) : _rearrangeGrid(c)),
              ),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Swap PDF',
              icon: Icons.swap_horiz,
              onPressed: _pick,
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
            onPressed: _canRun ? _run : null,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _deleteGrid(AnvilColors c) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        childAspectRatio: 0.72,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _thumbs.length,
      itemBuilder: (context, i) {
        final page = i + 1;
        final marked = _marked.contains(page);
        return GestureDetector(
          onTap: () => setState(() {
            if (!_marked.remove(page)) _marked.add(page);
          }),
          child: _pageCard(
            c,
            i,
            label: '$page',
            marked: marked,
          ),
        );
      },
    );
  }

  Widget _rearrangeGrid(AnvilColors c) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: _order.length,
      onReorderItem: _reorder,
      itemBuilder: (context, i) {
        final page = _order[i];
        return ReorderableDelayedDragStartListener(
          key: ValueKey('page-$page'),
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text('${i + 1}.',
                      style: AnvilText.mono(14, color: c.muted)),
                ),
                Expanded(
                  child: SizedBox(
                    height: 120,
                    child: _pageCard(c, page - 1,
                        label: 'p$page', marked: false),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.drag_handle, color: c.iconStrong),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pageCard(AnvilColors c, int thumbIndex,
      {required String label, required bool marked}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AnvilRadii.chip),
        border: Border.all(
          color: marked ? c.error : c.faint,
          width: marked ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: c.containerHigh,
            child: Image.memory(_thumbs[thumbIndex], fit: BoxFit.contain),
          ),
          if (marked)
            Positioned.fill(
              child: Container(color: c.error.withValues(alpha: 0.35)),
            ),
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              color: c.accent.withValues(alpha: 0.85),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              child: Text(label, style: AnvilText.mono(10, color: c.onAccent)),
            ),
          ),
          if (marked)
            Positioned(
              right: 4,
              top: 4,
              child: Icon(Icons.delete, size: 18, color: c.error),
            ),
          Positioned(
            right: 2,
            bottom: 2,
            child: Material(
              color: c.container.withValues(alpha: 0.9),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _showPage(thumbIndex),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.zoom_out_map, size: 16, color: c.iconStrong),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
