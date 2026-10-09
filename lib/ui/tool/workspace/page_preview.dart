/// Enlarged single-page stage for the placement sheets (text, sign, crop):
/// the rendered page with a caller overlay laid out in unrotated page space,
/// plus prev/next navigation through the alive pages.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/image_canvas.dart';
import 'package:anvil/ui/tool/workspace/workspace_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';

class PagePreview extends ConsumerWidget {
  const PagePreview({
    super.key,
    required this.pageRef,
    required this.overlay,
    required this.onPage,
  });

  final PageRef pageRef;

  /// Builds the overlay; [displayRect] is where the (unrotated) page sits and
  /// [pagePt] its size in points. The stage rotates the page and overlay
  /// together, so hit-testing inside the overlay is in unrotated page space.
  final Widget Function(Rect displayRect, Size pagePt) overlay;
  final ValueChanged<PageRef> onPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final st = ref.watch(pdfWorkspaceProvider);
    final ctl = ref.read(pdfWorkspaceProvider.notifier);
    final order = st.doc.order;
    final i = order.indexOf(pageRef);
    final size = pageSizeOf(st.sources, pageRef);
    final pagePt = Size(size.w, size.h);
    return Column(
      children: [
        Container(
          height: 260,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.containerHigh,
            borderRadius: BorderRadius.circular(AnvilRadii.panel),
          ),
          child: FutureBuilder<Uint8List>(
            future: ctl.pageRender(pageRef),
            builder: (context, snap) {
              final png = snap.data;
              if (png == null) {
                return snap.hasError
                    ? Center(
                        child: Text(
                          'Could not render this page.',
                          style: TextStyle(color: c.error),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator());
              }
              return RotatedBox(
                quarterTurns: (st.doc.rotation[pageRef] ?? 0) ~/ 90,
                child: ImageCanvas(
                  imageBytes: png,
                  imagePx: pagePt,
                  builder: (context, displayRect, _) =>
                      Positioned.fill(child: overlay(displayRect, pagePt)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous page',
              icon: Icon(Icons.chevron_left, color: c.iconStrong),
              onPressed: i > 0 ? () => onPage(order[i - 1]) : null,
            ),
            Text(
              '${i + 1} / ${order.length}',
              style: AnvilText.mono(13, color: c.muted),
            ),
            IconButton(
              tooltip: 'Next page',
              icon: Icon(Icons.chevron_right, color: c.iconStrong),
              onPressed: i >= 0 && i < order.length - 1
                  ? () => onPage(order[i + 1])
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
