/// The PDF workspace (design Direction A, "Document + op bar"): open one PDF,
/// the page grid is home, ops are bottom sheets over it, edits stack up as
/// undoable pending edits, and one Export (via Review) applies them all.
/// Replaces the per-tool editors for merge, delete, rearrange, rotate,
/// compress, add-text, sign, crop and split.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/workspace/page_thumb.dart';
import 'package:anvil/ui/tool/workspace/page_zoom.dart';
import 'package:anvil/ui/tool/workspace/pdf_review_screen.dart';
import 'package:anvil/ui/tool/workspace/sheets/compress_sheet.dart';
import 'package:anvil/ui/tool/workspace/sheets/crop_sheet.dart';
import 'package:anvil/ui/tool/workspace/sheets/organize_sheet.dart';
import 'package:anvil/ui/tool/workspace/sheets/sign_sheet.dart';
import 'package:anvil/ui/tool/workspace/sheets/split_sheet.dart';
import 'package:anvil/ui/tool/workspace/sheets/text_sheet.dart';
import 'package:anvil/ui/tool/workspace/workspace_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// The op sheet to open once the first document is loaded (tool entry points
/// such as "Merge PDFs" land on their op).
enum WorkspaceOp { none, organize, compress, text, sign, crop, split }

/// Recent PDF outputs for the Open view: newest first, existing files only,
/// distinct, at most 5. Names drop the outputs dir's epoch-ms prefix.
final recentPdfsProvider =
    FutureProvider.autoDispose<
      List<({String path, String name, int pages, int bytes})>
    >((ref) async {
      final out = <({String path, String name, int pages, int bytes})>[];
      final seen = <String>{};
      for (final r in await getIt<HistoryRepository>().all()) {
        for (final path in r.outputPaths) {
          if (out.length >= 5) return out;
          if (!path.toLowerCase().endsWith('.pdf') || !seen.add(path)) continue;
          final f = File(path);
          if (!await f.exists()) continue;
          final bytes = await f.readAsBytes();
          final int pages;
          try {
            pages = await getIt<PdfEngine>().pageCount(bytes);
          } on ToolException {
            continue;
          }
          out.add((
            path: path,
            name: p.basename(path).replaceFirst(RegExp(r'^\d+_'), ''),
            pages: pages,
            bytes: bytes.length,
          ));
        }
      }
      return out;
    });

Future<List<InputFile>> _pickPdfs() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  return [
    for (final f in files)
      if (f.path != null) InputFile(path: f.path!, name: f.name),
  ];
}

class PdfWorkspaceScreen extends ConsumerStatefulWidget {
  const PdfWorkspaceScreen({super.key, this.initialOp = WorkspaceOp.none});

  final WorkspaceOp initialOp;

  @override
  ConsumerState<PdfWorkspaceScreen> createState() => _PdfWorkspaceScreenState();
}

class _PdfWorkspaceScreenState extends ConsumerState<PdfWorkspaceScreen> {
  WorkspaceOp? _openOp;
  bool _initialOpShown = false;
  final _grid = ScrollController();
  double _gridWidth = 0;

  @override
  void initState() {
    super.initState();
    final shared = ref.read(pendingSharedInputProvider);
    if (shared != null && p.extension(shared.name).toLowerCase() == '.pdf') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pendingSharedInputProvider.notifier).state = null;
        ref.read(pdfWorkspaceProvider.notifier).open([shared]);
      });
    }
  }

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  PdfWorkspaceController get _ctl => ref.read(pdfWorkspaceProvider.notifier);

  Future<void> _openSheet(WorkspaceOp op) async {
    final sheet = switch (op) {
      WorkspaceOp.organize => const OrganizeSheet(),
      WorkspaceOp.compress => const CompressSheet(),
      WorkspaceOp.text => const TextSheet(),
      WorkspaceOp.sign => const SignSheet(),
      WorkspaceOp.crop => const CropSheet(),
      WorkspaceOp.split => const SplitSheet(),
      WorkspaceOp.none => null,
    };
    if (sheet == null) return;
    setState(() => _openOp = op);
    await showWsSheet<void>(context, sheet);
    if (mounted) setState(() => _openOp = null);
  }

  Future<void> _confirmDiscard() async {
    final n = ref.read(pdfWorkspaceProvider).edits.length;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard edits?'),
        content: Text(n == 1 ? '1 edit not applied.' : '$n edits not applied.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  Future<void> _goToPage() async {
    final order = ref.read(pdfWorkspaceProvider).doc.order;
    final field = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: '1-${order.length}'),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(field.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    field.dispose();
    if (n == null || order.isEmpty || !mounted) return;
    final i = n.clamp(1, order.length) - 1;
    _ctl.focus(order[i]);
    // Cells are built lazily, so scroll by geometry rather than by key.
    if (_grid.hasClients && _gridWidth > 0) {
      final cell = (_gridWidth - 20) / 3 / 0.72;
      final target = (i ~/ 3) * (cell + 10);
      await _grid.animateTo(
        target.clamp(0, _grid.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _zoom(PageRef r) async {
    final rotation = ref.read(pdfWorkspaceProvider).doc.rotation[r] ?? 0;
    final Uint8List png;
    try {
      png = await _ctl.pageRender(r);
    } on ToolException {
      return;
    }
    if (!mounted) return;
    await showPageZoom(context, png, quarterTurns: rotation ~/ 90);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final st = ref.watch(pdfWorkspaceProvider);

    ref.listen(pdfWorkspaceProvider, (prev, next) {
      if (next.error != null && next.sources.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
        _ctl.clearError();
      }
      if (!_initialOpShown &&
          (prev?.sources.isEmpty ?? true) &&
          next.sources.isNotEmpty) {
        _initialOpShown = true;
        if (widget.initialOp != WorkspaceOp.none) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openSheet(widget.initialOp);
          });
        }
      }
    });

    return PopScope(
      canPop: !st.hasUnsaved,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: st.sources.isEmpty,
          child: st.sources.isEmpty ? _openView(c, st) : _workspaceView(c, st),
        ),
      ),
    );
  }

  // ── Open ──────────────────────────────────────────────────────────────────

  Widget _openView(AnvilColors c, PdfWorkspaceState st) {
    final text = Theme.of(context).textTheme;
    final recent = ref.watch(recentPdfsProvider).asData?.value ?? const [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: WsChip(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onTap: () => Navigator.pop(context),
          ),
        ),
        const SizedBox(height: 18),
        Text('PDF workspace', style: text.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Open one document, then do everything to it.',
          style: text.bodyLarge!.copyWith(color: c.muted),
        ),
        const SizedBox(height: 20),
        if (st.loading)
          const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          )
        else
          _DropPanel(
            onTap: () async {
              final files = await _pickPdfs();
              if (files.isNotEmpty) await _ctl.open(files);
            },
          ),
        if (st.error != null) ...[
          const SizedBox(height: 10),
          Text(st.error!, style: text.bodyMedium!.copyWith(color: c.error)),
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 24),
          const SectionEyebrow('RECENT'),
          const SizedBox(height: 10),
          for (final r in recent) ...[
            ToolRow(
              icon: Icons.picture_as_pdf,
              title: r.name,
              subtitle: '${pageCountLabel(r.pages)} · ${formatBytes(r.bytes)}',
              mono: true,
              onTap: () => _ctl.open([InputFile(path: r.path, name: r.name)]),
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 16),
        const InfoCard('Everything runs on this device. Nothing is uploaded.'),
      ],
    );
  }

  // ── Workspace ─────────────────────────────────────────────────────────────

  Widget _workspaceView(AnvilColors c, PdfWorkspaceState st) {
    final doc = st.doc;
    final total = st.sources.fold<int>(0, (a, s) => a + s.sizeBytes);
    final first = st.sources.first.name;
    final title = st.sources.length > 1
        ? '$first +${st.sources.length - 1}'
        : first;
    final selection = st.selection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: WsHeader(
            title: title,
            sub: '${pageCountLabel(doc.order.length)} · ${formatBytes(total)}',
            actions: [
              WsChip(
                icon: Icons.undo,
                tooltip: 'Undo',
                onTap: st.edits.isEmpty ? null : _ctl.undoLast,
              ),
              WsChip(
                icon: Icons.search,
                tooltip: 'Go to page',
                onTap: _goToPage,
              ),
            ],
          ),
        ),
        if (st.loading) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: WsPillRail(
            children: [
              if (selection.isEmpty)
                WsPill(
                  icon: Icons.select_all,
                  label: 'Select all',
                  onTap: _ctl.selectAll,
                )
              else ...[
                WsPill(
                  label: '${selection.length} selected',
                  on: true,
                  onTap: _ctl.clearSelection,
                ),
                WsPill(
                  icon: Icons.rotate_right,
                  label: 'Rotate',
                  onTap: _ctl.rotateSelection,
                ),
                WsPill(
                  icon: Icons.delete,
                  label: 'Delete',
                  onTap: _ctl.deleteSelection,
                ),
                WsPill(
                  icon: Icons.call_split,
                  label: 'Extract',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PdfReviewScreen(only: {...selection}),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SlabPanel(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, cons) {
                  _gridWidth = cons.maxWidth;
                  return GridView.builder(
                    controller: _grid,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.72,
                        ),
                    itemCount: doc.order.length,
                    itemBuilder: (context, i) {
                      final r = doc.order[i];
                      return GestureDetector(
                        key: ValueKey(r),
                        onTap: () => _ctl.toggleSelect(r),
                        onLongPress: () => _zoom(r),
                        child: PageThumb(
                          pageRef: r,
                          label: i + 1,
                          selected: selection.contains(r),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _sheetBar(c, st),
      ],
    );
  }

  Widget _sheetBar(AnvilColors c, PdfWorkspaceState st) {
    final alive = st.doc.order.length;
    WsPill op(
      WorkspaceOp o,
      IconData icon,
      String label, {
      bool enabled = true,
    }) => WsPill(
      icon: icon,
      label: label,
      raised: true,
      on: _openOp == o,
      onTap: enabled ? () => _openSheet(o) : null,
    );
    return Container(
      decoration: BoxDecoration(
        color: c.container,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AnvilRadii.panel),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WsPillRail(
            children: [
              op(WorkspaceOp.organize, Icons.reorder, 'Organize'),
              op(WorkspaceOp.compress, Icons.compress, 'Compress'),
              op(WorkspaceOp.text, Icons.title, 'Text'),
              op(WorkspaceOp.sign, Icons.draw, 'Sign'),
              op(WorkspaceOp.crop, Icons.crop, 'Crop'),
              op(
                WorkspaceOp.split,
                Icons.call_split,
                'Split',
                enabled: alive >= 2,
              ),
            ],
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Export',
            detail: '· est. ${formatBytes(estimateBytes(st.sources, st.doc))}',
            onPressed: st.canExport
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PdfReviewScreen()),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// Dashed "Pick a PDF" panel.
class _DropPanel extends StatelessWidget {
  const _DropPanel({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    return Material(
      color: c.container,
      borderRadius: BorderRadius.circular(AnvilRadii.panel),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedBorder(c.faint),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Column(
              children: [
                const IconChip(icon: Icons.upload_file, box: 52, glyph: 26),
                const SizedBox(height: 10),
                Text('Pick a PDF', style: text.titleSmall),
                const SizedBox(height: 10),
                Text(
                  'or share one to Anvil',
                  style: text.bodyMedium!.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      const Radius.circular(AnvilRadii.panel),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
