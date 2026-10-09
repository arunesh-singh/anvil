/// Add-text op: type, style and tap the page to place vector text on this
/// page, the selection or every page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/pdf_doc_model.dart' show flutterFamily;
import 'package:anvil/ui/tool/workspace/page_preview.dart';
import 'package:anvil/ui/tool/workspace/workspace_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

class TextSheet extends ConsumerStatefulWidget {
  const TextSheet({super.key});

  @override
  ConsumerState<TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends ConsumerState<TextSheet> {
  final _text = TextEditingController();
  late PageRef _page;
  late ScopeChoice _scope;
  String _family = 'Helvetica';
  bool _bold = false;
  bool _italic = false;
  int _size = 18;
  Color _color = Colors.black;
  Offset _anchor = const Offset(0.1, 0.12);

  @override
  void initState() {
    super.initState();
    final st = ref.read(pdfWorkspaceProvider);
    _page = st.focused ?? st.doc.order.first;
    _scope = st.selection.isEmpty ? ScopeChoice.page : ScopeChoice.selection;
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  TextStyle _style(double px) => TextStyle(
    fontFamily: flutterFamily(_family),
    fontSize: px,
    fontWeight: _bold ? FontWeight.bold : FontWeight.normal,
    fontStyle: _italic ? FontStyle.italic : FontStyle.normal,
    color: _color,
  );

  Widget _overlay(Rect display, Size pagePt) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final scale = display.width / pagePt.width;
    final px = _size * scale;
    final label = _text.text.isEmpty ? 'Text to place' : _text.text;
    final tp = TextPainter(
      text: TextSpan(text: label, style: _style(px)),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline = tp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final padH = 10 * scale, padV = 6 * scale;
    final x = display.left + _anchor.dx * display.width;
    final y = display.top + _anchor.dy * display.height;
    void moveTo(Offset local) => setState(
      () => _anchor = Offset(
        ((local.dx - display.left) / display.width).clamp(0.0, 1.0),
        ((local.dy - display.top) / display.height).clamp(0.0, 1.0),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => moveTo(d.localPosition),
      onPanUpdate: (d) => setState(
        () => _anchor = Offset(
          (_anchor.dx + d.delta.dx / display.width).clamp(0.0, 1.0),
          (_anchor.dy + d.delta.dy / display.height).clamp(0.0, 1.0),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: x - padH,
            top: y - baseline - padV,
            child: IgnorePointer(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  border: Border.all(color: c.accent),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: _style(px).copyWith(
                    color: _text.text.isEmpty
                        ? _color.withValues(alpha: 0.4)
                        : _color,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final st = ref.watch(pdfWorkspaceProvider);
    final doc = st.doc;
    if (!doc.order.contains(_page)) _page = doc.order.first;
    final scope = resolveScope(_scope, doc, _page, st.selection);
    final button = scope.all
        ? 'Add to all ${doc.order.length}'
        : scope.pages.length == 1
        ? 'Add to page ${doc.labelOf(scope.pages.single)}'
        : 'Add to ${scope.pages.length} pages';

    Widget sizeBtn(IconData icon, VoidCallback? onTap) => Material(
      color: c.containerHigh,
      borderRadius: BorderRadius.circular(AnvilRadii.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            icon,
            size: 16,
            color: onTap == null ? c.faint : c.onSurface,
          ),
        ),
      ),
    );

    return WsSheetFrame(
      title: 'Add text',
      sub: 'tap the page to place',
      children: [
        PagePreview(
          pageRef: _page,
          overlay: _overlay,
          onPage: (p) => setState(() => _page = p),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          decoration: InputDecoration(
            hintText: 'Text to place',
            filled: true,
            fillColor: c.containerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AnvilRadii.search),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        WsPillRail(
          children: [
            for (final f in const ['Helvetica', 'Times', 'Courier'])
              WsPill(
                label: f,
                small: true,
                on: _family == f,
                onTap: () => setState(() => _family = f),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            WsPill(
              label: 'B',
              small: true,
              on: _bold,
              onTap: () => setState(() => _bold = !_bold),
            ),
            const SizedBox(width: 8),
            WsPill(
              label: 'I',
              small: true,
              on: _italic,
              onTap: () => setState(() => _italic = !_italic),
            ),
            const Spacer(),
            sizeBtn(
              Icons.remove,
              _size > 6 ? () => setState(() => _size -= 1) : null,
            ),
            SizedBox(
              width: 64,
              child: Text(
                '$_size pt',
                textAlign: TextAlign.center,
                style: AnvilText.mono(13, color: c.onSurface),
              ),
            ),
            sizeBtn(
              Icons.add,
              _size < 200 ? () => setState(() => _size += 1) : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final col in kTextPalette)
              WsSwatch(
                color: col,
                selected: col == _color,
                onTap: () => setState(() => _color = col),
              ),
          ],
        ),
        const SizedBox(height: 14),
        ScopeSegment(
          selectionLabels: doc.labelsOf(st.selection),
          total: doc.order.length,
          value: _scope,
          onChanged: (v) => setState(() => _scope = v),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: button,
          icon: Icons.check,
          onPressed: _text.text.trim().isEmpty
              ? null
              : () {
                  ref
                      .read(pdfWorkspaceProvider.notifier)
                      .addEdit(
                        TextEdit(
                          pages: scope.pages,
                          labels: doc.labelsOf(scope.pages),
                          all: scope.all,
                          text: _text.text.trim(),
                          family: _family,
                          bold: _bold,
                          italic: _italic,
                          size: _size.toDouble(),
                          color: _color.toARGB32(),
                          anchor: _anchor,
                        ),
                      );
                  Navigator.pop(context);
                },
        ),
      ],
    );
  }
}
