/// Review before the workspace's single Export: every pending edit with its
/// own Undo, the estimated result, then one `pdf/workspace` run. With [only]
/// set it is the Extract flow for the selected pages.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/editor_scaffold.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Maps [describeEdit]'s icon names to glyphs.
IconData editIcon(String name) => switch (name) {
  'add' => Icons.add,
  'reorder' => Icons.reorder,
  'delete' => Icons.delete,
  'rotate_right' => Icons.rotate_right,
  'title' => Icons.title,
  'gesture' => Icons.gesture,
  'crop' => Icons.crop,
  'compress' => Icons.compress,
  'call_split' => Icons.call_split,
  _ => Icons.edit,
};

class PdfReviewScreen extends ConsumerWidget {
  const PdfReviewScreen({super.key, this.only});

  /// Extract: export just these pages (no split).
  final Set<PageRef>? only;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobProvider);
    ref.listen(jobProvider, (_, next) {
      if (next is JobSuccess) {
        ref.read(pdfWorkspaceProvider.notifier).markExported();
      }
    });
    return EditorScaffold(
      job: job,
      builder: (context) => _body(context, ref, job),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, JobState job) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final st = ref.watch(pdfWorkspaceProvider);
    final ctl = ref.read(pdfWorkspaceProvider.notifier);
    final doc = st.doc;
    final only = this.only;
    final pages = only == null
        ? doc.order.length
        : doc.order.where(only.contains).length;
    final split = only == null ? doc.split : null;
    final files = split == null ? 1 : splitFileCount(pages, split.every);
    final estimate = estimateBytes(st.sources, doc, only: only);
    final original =
        (st.sources.fold<int>(0, (a, s) => a + s.sizeBytes) *
                (pages /
                    st.sources.fold<int>(0, (a, s) => a + s.pagesPt.length)))
            .round();
    final saved = original > 0 && estimate < original
        ? '−${((1 - estimate / original) * 100).round()}%'
        : null;
    final raster = doc.compress?.method == 'raster';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Row(
          children: [
            WsChip(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                only == null ? 'Review' : 'Extract ${pageCountLabel(pages)}',
                style: text.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (st.edits.isNotEmpty) ...[
          SectionEyebrow('PENDING EDITS · ${st.edits.length}'),
          const SizedBox(height: 10),
          for (final e in st.edits) ...[
            () {
              final d = describeEdit(
                e,
                st.sources,
                formatBytes,
                alive: doc.order.length,
              );
              return WsRow(
                leading: IconChip(icon: editIcon(d.icon)),
                title: d.title,
                sub: d.sub,
                trailing: WsPill(
                  icon: Icons.undo,
                  label: 'Undo',
                  small: true,
                  onTap: () {
                    ctl.removeEdit(e);
                    final after = ref.read(pdfWorkspaceProvider);
                    final emptied =
                        only != null && !after.doc.order.any(only.contains);
                    if (!after.canExport || emptied) Navigator.pop(context);
                  },
                ),
              );
            }(),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
        ],
        SlabPanel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionEyebrow('RESULT'),
                    const SizedBox(height: 6),
                    Text(
                      formatBytes(estimate),
                      style: AnvilText.mono(
                        22,
                        weight: FontWeight.w500,
                        color: c.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${pageCountLabel(pages)} · '
                      '${raster ? 'pages become images' : 'text kept selectable'}'
                      '${split == null ? '' : ' · $files files'}',
                      style: text.bodyMedium!.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              if (saved != null)
                Text(
                  saved,
                  style: text.titleMedium!.copyWith(color: c.accentText),
                ),
            ],
          ),
        ),
        if (job is JobFailed) ...[
          const SizedBox(height: 12),
          Text(job.message, style: text.bodyMedium!.copyWith(color: c.error)),
        ],
        const SizedBox(height: 20),
        PrimaryButton(
          label: split == null ? 'Export PDF' : 'Export $files files',
          icon: Icons.arrow_forward,
          onPressed: pages == 0
              ? null
              : () => ref
                    .read(jobProvider.notifier)
                    .start(
                      getIt<ToolRegistry>().byId('pdf/workspace')!,
                      ctl.exportInput(only: only),
                    ),
        ),
        const SizedBox(height: 10),
        SecondaryButton(
          label: 'Keep editing',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
