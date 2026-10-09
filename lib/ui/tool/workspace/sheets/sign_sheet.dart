/// Sign op: pick a saved signature (or draw / import a new one, kept for next
/// time), drop it on the page, size it, and place it on this page, the
/// selection or every page.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/signature_store.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/image_edit_screen.dart';
import 'package:anvil/ui/tool/workspace/page_preview.dart';
import 'package:anvil/ui/tool/workspace/signature_pad_screen.dart';
import 'package:anvil/ui/tool/workspace/workspace_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

class SignSheet extends ConsumerStatefulWidget {
  const SignSheet({super.key});

  @override
  ConsumerState<SignSheet> createState() => _SignSheetState();
}

class _SignSheetState extends ConsumerState<SignSheet> {
  final _store = getIt<SignatureStore>();
  final _picker = ImagePicker();
  List<File> _saved = const [];
  File? _selected;
  ui.Image? _image;
  late PageRef _page;
  ScopeChoice _scope = ScopeChoice.page;

  /// Fractions of the unrotated page, top-left origin; null until a signature
  /// is chosen and no earlier placement exists.
  Rect? _rect;
  String? _error;

  @override
  void initState() {
    super.initState();
    final st = ref.read(pdfWorkspaceProvider);
    _page = st.focused ?? st.doc.order.first;
    _rect = st.lastSignRect;
    _reload(selectFirst: true);
  }

  Future<void> _reload({bool selectFirst = false, File? select}) async {
    final saved = await _store.list();
    if (!mounted) return;
    setState(() => _saved = saved);
    final pick = select ?? (selectFirst ? saved.firstOrNull : null);
    if (pick != null) await _select(pick);
  }

  Future<void> _select(File f) async {
    setState(() {
      _selected = f;
      _image = null;
    });
    try {
      final img = await ref
          .read(pdfWorkspaceProvider.notifier)
          .fileImage(f.path);
      if (!mounted || _selected != f) return;
      setState(() {
        _image = img;
        _rect ??= _defaultRect(img);
        // Keep a carried-over rect's width but match this image's aspect.
        _rect = _fitAspect(_rect!, img);
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the image.');
    }
  }

  Size get _pagePt {
    final s = pageSizeOf(ref.read(pdfWorkspaceProvider).sources, _page);
    return Size(s.w, s.h);
  }

  /// Height fraction for width fraction [w] that preserves [img]'s aspect.
  double _heightFor(double w, ui.Image img) {
    final pt = _pagePt;
    return w * pt.width / pt.height * img.height / img.width;
  }

  Rect _defaultRect(ui.Image img) {
    const w = 0.3;
    final h = _heightFor(w, img);
    return Rect.fromLTWH(0.5 - w / 2, 0.88 - h, w, h);
  }

  Rect _fitAspect(Rect r, ui.Image img) {
    final h = _heightFor(r.width, img);
    final top = (r.top).clamp(0.0, (1 - h).clamp(0.0, 1.0));
    return Rect.fromLTWH(r.left, top, r.width, h);
  }

  Rect _clampInside(Rect r) => r.shift(
    Offset(
      r.left < 0 ? -r.left : (r.right > 1 ? 1 - r.right : 0),
      r.top < 0 ? -r.top : (r.bottom > 1 ? 1 - r.bottom : 0),
    ),
  );

  Future<void> _drawNew() async {
    final png = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(builder: (_) => const SignaturePadScreen()),
    );
    if (png == null) return;
    final f = await _store.save(png);
    await _reload(select: f);
  }

  Future<void> _fromImage() async {
    try {
      final png = await pickAndEditImage(context, _picker);
      if (png == null) return;
      final f = await _store.save(png);
      await _reload(select: f);
    } on ToolException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _confirmDelete(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this signature?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.delete(f);
    if (_selected?.path == f.path) {
      setState(() {
        _selected = null;
        _image = null;
      });
    }
    await _reload();
  }

  Widget _overlay(Rect display, Size pagePt) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final img = _image;
    final r = _rect;
    Rect toDisplay(Rect f) => Rect.fromLTRB(
      display.left + f.left * display.width,
      display.top + f.top * display.height,
      display.left + f.right * display.width,
      display.top + f.bottom * display.height,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        if (img == null || r == null) return;
        final fx = (d.localPosition.dx - display.left) / display.width;
        final fy = (d.localPosition.dy - display.top) / display.height;
        setState(
          () => _rect = _clampInside(
            Rect.fromCenter(
              center: Offset(fx, fy),
              width: r.width,
              height: r.height,
            ),
          ),
        );
      },
      child: Stack(
        children: [
          if (img != null && r != null && _selected != null) ...[
            Positioned.fromRect(
              rect: toDisplay(r),
              child: GestureDetector(
                onPanUpdate: (d) => setState(
                  () => _rect = _clampInside(
                    r.shift(
                      Offset(
                        d.delta.dx / display.width,
                        d.delta.dy / display.height,
                      ),
                    ),
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: c.accent),
                  ),
                  child: Image.file(_selected!, fit: BoxFit.fill),
                ),
              ),
            ),
            Positioned(
              left: toDisplay(r).left - 5,
              top: toDisplay(r).top - 5,
              child: IgnorePointer(
                child: Container(width: 10, height: 10, color: c.accent),
              ),
            ),
            Positioned(
              left: toDisplay(r).right - 12,
              top: toDisplay(r).bottom - 12,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => setState(() {
                  final w = (r.width + d.delta.dx / display.width).clamp(
                    0.05,
                    1.0 - r.left,
                  );
                  final h = _heightFor(w, img);
                  if (r.top + h <= 1) {
                    _rect = Rect.fromLTWH(r.left, r.top, w, h);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Container(width: 10, height: 10, color: c.accent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final st = ref.watch(pdfWorkspaceProvider);
    final doc = st.doc;
    if (!doc.order.contains(_page)) _page = doc.order.first;
    final scope = resolveScope(_scope, doc, _page, st.selection);

    return WsSheetFrame(
      title: 'Sign',
      children: [
        PagePreview(
          pageRef: _page,
          overlay: _overlay,
          onPage: (p) => setState(() => _page = p),
        ),
        const SizedBox(height: 8),
        const SectionEyebrow('SAVED SIGNATURES'),
        const SizedBox(height: 10),
        WsPillRail(
          children: [
            for (final f in _saved)
              GestureDetector(
                onTap: () => _select(f),
                onLongPress: () => _confirmDelete(f),
                child: Container(
                  width: 64,
                  height: 40,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _selected?.path == f.path
                        ? c.accentContainer
                        : c.containerHigh,
                    borderRadius: BorderRadius.circular(AnvilRadii.control),
                  ),
                  child: Image.file(f, fit: BoxFit.contain),
                ),
              ),
            WsPill(
              icon: Icons.add,
              label: 'Draw new',
              small: true,
              onTap: _drawNew,
            ),
            WsPill(
              icon: Icons.image,
              label: 'From image',
              small: true,
              onTap: _fromImage,
            ),
          ],
        ),
        const SizedBox(height: 14),
        const InfoCard(
          'Tap the page to drop it, drag a corner to size. Position is kept '
          'for the next page.',
          icon: Icons.touch_app,
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: text.bodyMedium!.copyWith(color: c.error)),
        ],
        const SizedBox(height: 14),
        ScopeSegment(
          selectionLabels: doc.labelsOf(st.selection),
          total: doc.order.length,
          value: _scope,
          onChanged: (v) => setState(() => _scope = v),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: 'Place signature',
          icon: Icons.check,
          onPressed: _selected == null || _image == null || _rect == null
              ? null
              : () {
                  final ctl = ref.read(pdfWorkspaceProvider.notifier);
                  ctl.addEdit(
                    SignEdit(
                      pages: scope.pages,
                      labels: doc.labelsOf(scope.pages),
                      all: scope.all,
                      imagePath: _selected!.path,
                      rect: _rect!,
                    ),
                  );
                  ctl.setLastSignRect(_rect!);
                  Navigator.pop(context);
                },
        ),
      ],
    );
  }
}
