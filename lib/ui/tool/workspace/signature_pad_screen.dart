/// Finger-drawn signature for the workspace sign sheet. Pops the signature as
/// a transparent PNG (black ink), which the sheet saves for reuse.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/pdf_doc_model.dart';
import 'package:anvil/ui/tool/editors/pdf_overlay_painter.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  /// Strokes live in a 600×200 pt page; the pad maps touches into it.
  final _page = DocPage(sizePt: (w: 600, h: 200));
  bool _saving = false;

  Offset _toPt(Offset local, Size pad) =>
      Offset(local.dx * 600 / pad.width, local.dy * 200 / pad.height);

  Future<void> _save() async {
    setState(() => _saving = true);
    final png = await renderOverlayPng(_page, exportScale: 2);
    if (!mounted) return;
    Navigator.pop<Uint8List?>(context, png);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final hasInk = _page.elements.isNotEmpty;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  WsChip(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Draw signature',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AspectRatio(
                aspectRatio: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AnvilRadii.panel),
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      final pad = Size(cons.maxWidth, cons.maxHeight);
                      return GestureDetector(
                        onPanStart: (d) => setState(
                          () => _page.elements.add(
                            StrokeEl(
                              pointsPt: [_toPt(d.localPosition, pad)],
                              color: Colors.black,
                              widthPt: 3,
                            ),
                          ),
                        ),
                        onPanUpdate: (d) => setState(
                          () => (_page.elements.last as StrokeEl).pointsPt.add(
                            _toPt(d.localPosition, pad),
                          ),
                        ),
                        child: CustomPaint(
                          size: pad,
                          foregroundPainter: DocPagePainter(
                            page: _page,
                            displayRect: Offset.zero & pad,
                            images: const <Uint8List, ui.Image>{},
                          ),
                          child: const ColoredBox(color: Colors.white),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const Spacer(),
              SecondaryButton(
                label: 'Clear',
                onPressed: hasInk
                    ? () => setState(() => _page.elements.clear())
                    : null,
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: 'Save',
                icon: Icons.check,
                onPressed: hasInk && !_saving ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
