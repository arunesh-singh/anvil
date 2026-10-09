/// Organize op: drag pages into a new order (applied as one reorder edit) and
/// append more PDFs (merge; each added file is its own edit right away).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/workspace/page_thumb.dart';
import 'package:anvil/ui/tool/workspace/workspace_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

class OrganizeSheet extends ConsumerStatefulWidget {
  const OrganizeSheet({super.key});

  @override
  ConsumerState<OrganizeSheet> createState() => _OrganizeSheetState();
}

class _OrganizeSheetState extends ConsumerState<OrganizeSheet> {
  late List<PageRef> _order = [...ref.read(pdfWorkspaceProvider).doc.order];

  /// Order when the sheet opened (or after an add), for "moved from n".
  late List<PageRef> _start = [..._order];

  bool get _changed {
    if (_order.length != _start.length) return true;
    for (var i = 0; i < _order.length; i++) {
      if (_order[i] != _start[i]) return true;
    }
    return false;
  }

  Future<void> _addPdfs() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final picked = [
      for (final f in files)
        if (f.path != null) InputFile(path: f.path!, name: f.name),
    ];
    if (picked.isEmpty) return;
    final ctl = ref.read(pdfWorkspaceProvider.notifier);
    await ctl.addSources(picked);
    if (!mounted) return;
    // Keep the local arrangement and append the new pages at the end.
    final now = ref.read(pdfWorkspaceProvider).doc.order;
    final known = _order.toSet();
    setState(() {
      final added = now.where((p) => !known.contains(p)).toList();
      _order = [..._order, ...added];
      _start = [..._start, ...added];
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final st = ref.watch(pdfWorkspaceProvider);
    final doc = st.doc;
    return WsSheetFrame(
      title: 'Organize',
      sub: pageCountLabel(_order.length),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: WsPill(
            icon: Icons.add,
            label: 'Add PDFs',
            small: true,
            onTap: st.loading ? null : _addPdfs,
          ),
        ),
        if (st.loading) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 12),
        // Its own bounded scroller, so dragging a row auto-scrolls the list.
        SizedBox(
          height: (_order.length * 90.0).clamp(
            90.0,
            MediaQuery.of(context).size.height * 0.45,
          ),
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _order.length,
            onReorderItem: (from, to) => setState(() {
              _order.insert(to, _order.removeAt(from));
            }),
            itemBuilder: (context, i) {
              final r = _order[i];
              final size = pageSizeOf(st.sources, r);
              final turned = ((doc.rotation[r] ?? 0) ~/ 90).isOdd;
              final w = (turned ? size.h : size.w).round();
              final h = (turned ? size.w : size.h).round();
              final name = pageSizeName(size.w, size.h);
              final from = _start.indexOf(r);
              final sub = from != i && from >= 0
                  ? 'moved from ${from + 1}'
                  : '${name == null ? '' : '$name · '}$w×${h}pt';
              return Padding(
                key: ValueKey(r),
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.containerHigh,
                    borderRadius: BorderRadius.circular(AnvilRadii.row),
                  ),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: Icon(Icons.drag_indicator, color: c.hint),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 48,
                        height: 48 / 0.72,
                        child: PageThumb(
                          pageRef: r,
                          label: i + 1,
                          showLabel: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Page ${i + 1}', style: text.titleSmall),
                            Text(
                              sub,
                              style: AnvilText.mono(12, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: 'Apply',
          icon: Icons.check,
          onPressed: _changed
              ? () {
                  ref
                      .read(pdfWorkspaceProvider.notifier)
                      .addEdit(ReorderEdit([..._order]));
                  Navigator.pop(context);
                }
              : null,
        ),
      ],
    );
  }
}
