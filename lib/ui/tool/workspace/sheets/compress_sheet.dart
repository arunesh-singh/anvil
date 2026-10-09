/// Compress op: compresses the real document with the chosen settings and
/// shows the measured size and rendered output pages before anything is
/// applied — the estimate is a measurement, not a guess.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/tools/pdf/pdf_tools.dart' show compressPdfBytes;
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/workspace/workspace_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

class CompressSheet extends ConsumerStatefulWidget {
  const CompressSheet({super.key});

  @override
  ConsumerState<CompressSheet> createState() => _CompressSheetState();
}

typedef _Measure = ({
  String key,
  Uint8List base,
  Uint8List out,
  int basePages,
  List<Uint8List> previews,
});

class _CompressSheetState extends ConsumerState<CompressSheet> {
  late bool _raster;
  late int _quality;
  late int _dpi;

  Timer? _debounce;
  bool _running = false;
  bool _dirty = false;
  String? _progress;
  _Measure? _result;
  String? _error;

  String get _key => '$_raster/$_quality/$_dpi';
  bool get _fresh => _result?.key == _key;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(pdfWorkspaceProvider).doc.compress;
    _raster = existing?.method == 'raster';
    _quality = existing?.quality ?? 60;
    _dpi = existing?.dpi ?? 150;
    _measure();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _set(VoidCallback change) {
    setState(change);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _measure);
  }

  Future<void> _measure() async {
    if (_running) {
      _dirty = true;
      return;
    }
    _running = true;
    final key = _key;
    final raster = _raster;
    setState(() {
      _error = null;
      _progress = raster ? null : 'Measuring…';
    });
    try {
      final ctl = ref.read(pdfWorkspaceProvider.notifier);
      final e = getIt<PdfEngine>();
      final base = await ctl.baseBytes();
      final out = await compressPdfBytes(
        e,
        base,
        method: raster ? 'raster' : 'optimize',
        quality: _quality,
        dpi: _dpi,
        onPage: (page, total) {
          if (mounted && key == _key) {
            setState(() => _progress = 'Rasterizing $page/$total…');
          }
        },
      );
      final basePages = await e.pageCount(base);
      final order = ref.read(pdfWorkspaceProvider).doc.order;
      final previews = <Uint8List>[
        for (final r in order.take(3))
          (await e.renderPage(
            out,
            ctl.globalIndex(r),
            maxWidth: 200,
            maxHeight: 200,
          )).bytes,
      ];
      if (mounted && key == _key) {
        setState(
          () => _result = (
            key: key,
            base: base,
            out: out,
            basePages: basePages,
            previews: previews,
          ),
        );
      }
    } on ToolException catch (e) {
      if (mounted && key == _key) setState(() => _error = e.message);
    } finally {
      _running = false;
      // Params changed mid-run: measure again with the latest ones.
      if (mounted && _dirty) {
        _dirty = false;
        _measure();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final st = ref.watch(pdfWorkspaceProvider);
    final alive = st.doc.order.length;
    final totalPages = st.sources.fold<int>(0, (a, s) => a + s.pagesPt.length);
    final totalBytes = st.sources.fold<int>(0, (a, s) => a + s.sizeBytes);
    final r = _fresh ? _result : null;

    String value;
    String? delta;
    var notSmaller = false;
    if (r == null) {
      value = _error != null ? '—' : (_progress ?? 'Measuring…');
    } else {
      final from = (totalBytes * alive / totalPages).round();
      final to = (r.out.length * alive / r.basePages).round();
      value = '${formatBytes(from)} → ${formatBytes(to)}';
      notSmaller = identical(r.out, r.base);
      delta = notSmaller
          ? '0%'
          : '−${((1 - r.out.length / r.base.length) * 100).round()}%';
    }

    return WsSheetFrame(
      title: 'Compress',
      sub: _raster
          ? 'raster · q$_quality · $_dpi dpi'
          : 'optimize · q$_quality',
      children: [
        const SectionEyebrow('PREVIEW'),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Container(
                width: 64,
                height: 64 / 0.72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AnvilRadii.chip),
                  border: Border.all(color: c.containerHigh),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: r == null
                    ? (i == 0 && _error == null
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null)
                    : (i < r.previews.length
                          ? Image.memory(r.previews[i], fit: BoxFit.contain)
                          : null),
              ),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Rendered from the real file — this is the output, not a guess.',
                style: text.bodyMedium!.copyWith(color: c.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        WsSegmented(
          inSheet: true,
          labels: const ['Optimize', 'Rasterize'],
          selected: _raster ? 1 : 0,
          onChanged: (i) => _set(() => _raster = i == 1),
        ),
        const SizedBox(height: 6),
        Text(
          _raster
              ? 'Renders pages to images — smallest for scans, but '
                    'text becomes non-selectable.'
              : 'Re-encodes embedded images and keeps text selectable.',
          style: text.bodyMedium!.copyWith(color: c.muted),
        ),
        const SizedBox(height: 12),
        StepperField(
          label: 'Image quality (10-95)',
          value: _quality,
          min: 10,
          max: 95,
          step: 5,
          color: c.containerHigh,
          onChanged: (v) => _set(() => _quality = v),
        ),
        if (_raster) ...[
          const SizedBox(height: 12),
          Text('Resolution (DPI)', style: text.titleSmall),
          const SizedBox(height: 8),
          WsPillRail(
            children: [
              for (final d in const [96, 120, 150, 200])
                WsPill(
                  label: '$d',
                  small: true,
                  on: _dpi == d,
                  onTap: () => _set(() => _dpi = d),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        WsEstimate(label: 'ESTIMATED OUTPUT', value: value, delta: delta),
        if (notSmaller) ...[
          const SizedBox(height: 10),
          const InfoCard('Already optimally compressed.'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: text.bodyMedium!.copyWith(color: c.error)),
        ],
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Apply',
          icon: Icons.check,
          onPressed: r == null
              ? null
              : () {
                  ref
                      .read(pdfWorkspaceProvider.notifier)
                      .replaceSingleton(
                        CompressEdit(
                          method: _raster ? 'raster' : 'optimize',
                          quality: _quality,
                          dpi: _dpi,
                          measuredBytes: r.out.length,
                          measuredFrom: r.base.length,
                          measuredPages: r.basePages,
                        ),
                      );
                  Navigator.pop(context);
                },
        ),
      ],
    );
  }
}
