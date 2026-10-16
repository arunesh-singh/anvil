import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/ui/tool/editors/collage_layout.dart';
import 'package:anvil/ui/tool/editors/split_presets.dart';

SplitPlan _plan(SplitPreset p, int w, int h) =>
    SplitPlan(width: w, height: h, rows: p.rows, cols: p.cols);

CollageItem _item(String name, double w, double h) => CollageItem(
  file: InputFile(path: '/tmp/$name', name: name),
  size: Size(w, h),
  bytes: Uint8List(0),
);

void main() {
  group('split presets', () {
    test('tile size and file count per preset', () {
      expect(
        _plan(SplitPreset.grid3x3, 3024, 3024).readout,
        'Each tile 1008 × 1008 px · 9 files',
      );
      expect(
        _plan(SplitPreset.grid2x3, 3240, 2160).readout,
        'Each tile 1080 × 1080 px · 6 files',
      );
      expect(
        _plan(SplitPreset.row1x3, 3240, 1350).readout,
        'Each tile 1080 × 1350 px · 3 files',
      );
      expect(
        _plan(SplitPreset.row1x2, 2160, 1080).readout,
        'Each tile 1080 × 1080 px · 2 files',
      );
    });

    test('uneven edges are flagged; params carry rows/cols', () {
      final p = _plan(SplitPreset.grid3x3, 1000, 1000);
      expect(p.tileWidth, 333);
      expect(p.uneven, isTrue);
      expect(p.readout, startsWith('Each tile ~333 × 333 px'));
      expect(_plan(SplitPreset.grid2x3, 10, 10).params, {'rows': 2, 'cols': 3});
      expect(SplitPreset.grid3x3.feed, isTrue);
      expect(SplitPreset.row1x3.feed, isFalse);
    });
  });

  group('collage', () {
    test('output size follows ImageChannel.grid', () {
      const sizes = [Size(100, 50), Size(80, 120), Size(60, 60)];
      expect(collageOutputSize(sizes, 0, 0), const Size(300, 120));
      expect(collageOutputSize(sizes, 0, 10), const Size(340, 140));
      // 2 columns, 2 rows.
      expect(collageOutputSize(sizes, 2, 10), const Size(230, 270));
      // Columns beyond n clamp to n.
      expect(collageOutputSize(sizes, 5, 0), const Size(300, 120));
      expect(collageOutputSize(sizes, 1, 4), const Size(108, 376));
      expect(collageOutputSize(const [], 2, 4), Size.zero);
    });

    test('param map after reorder and remove', () {
      final d =
          CollageDraft(
                layout: CollageLayout.twoColumns,
                background: '#00000000',
              )
              .add([_item('a.png', 10, 10), _item('b.png', 10, 10)])
              .add([_item('c.png', 10, 10)])
              .reorder(2, 0) // c a b
              .remove(1) // c b
              .copyWith(
                layout: CollageLayout.threeColumns,
                gap: 12,
                background: '#FFE1E5FF',
              );
      final input = d.input;
      expect(input.files.map((f) => f.name), ['c.png', 'b.png']);
      expect(input.params, {
        'columns': 3,
        'gap': 12,
        'background': '#FFE1E5FF',
      });
      expect(d.canRun, isTrue);
      expect(d.remove(0).canRun, isFalse);
    });

    test('layouts map to columns', () {
      expect(CollageLayout.values.map((l) => l.columns), [0, 2, 3, 1]);
    });
  });
}
