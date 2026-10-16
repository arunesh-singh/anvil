import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/ui/tool/editors/crop_geometry.dart';

void main() {
  const portrait = Size(3024, 4032);
  const landscape = Size(4000, 3000);

  group('ratio snapping picks the largest centred rect', () {
    final cases = <(Size, CropRatio, Rect)>[
      (portrait, CropRatio.square, const Rect.fromLTWH(0, 504, 3024, 3024)),
      (portrait, CropRatio.portrait, const Rect.fromLTWH(0, 126, 3024, 3780)),
      (portrait, CropRatio.wide, const Rect.fromLTWH(0, 1165.5, 3024, 1701)),
      (portrait, CropRatio.tall, const Rect.fromLTWH(378, 0, 2268, 4032)),
      (portrait, CropRatio.original, const Rect.fromLTWH(0, 0, 3024, 4032)),
      (landscape, CropRatio.square, const Rect.fromLTWH(500, 0, 3000, 3000)),
      (landscape, CropRatio.portrait, const Rect.fromLTWH(800, 0, 2400, 3000)),
      (landscape, CropRatio.wide, const Rect.fromLTWH(0, 375, 4000, 2250)),
      (
        landscape,
        CropRatio.tall,
        const Rect.fromLTWH(1156.25, 0, 1687.5, 3000),
      ),
    ];
    for (final (size, ratio, want) in cases) {
      test('${ratio.label} in ${size.width}×${size.height}', () {
        final d = CropDraft.initial(size).withRatio(ratio);
        expect(d.rect.left, closeTo(want.left, 0.01));
        expect(d.rect.top, closeTo(want.top, 0.01));
        expect(d.rect.width, closeTo(want.width, 0.01));
        expect(d.rect.height, closeTo(want.height, 0.01));
        expect(d.locked, isTrue);
      });
    }

    test('free unlocks and keeps the box', () {
      final d = CropDraft.initial(portrait).withRatio(CropRatio.square);
      final f = d.withRatio(CropRatio.free);
      expect(f.locked, isFalse);
      expect(f.rect, d.rect);
      expect(f.ratioLabel, 'Free');
      expect(d.ratioLabel, '1 : 1');
    });

    test('after a 90° rotation presets re-snap in the swapped bounds', () {
      final d = CropDraft.initial(portrait).withRatio(CropRatio.portrait);
      final r = d.rotateLeft();
      expect(r.bounds, const Size(4032, 3024));
      expect(r.rect.width, closeTo(2419.2, 0.01));
      expect(r.rect.height, closeTo(3024, 0.01));
      expect(r.rect.left, closeTo((4032 - 2419.2) / 2, 0.01));
      final o = CropDraft.initial(
        portrait,
      ).withRatio(CropRatio.original).rotateLeft();
      expect(o.rect, const Rect.fromLTWH(0, 0, 4032, 3024));
      expect(o.ratioLabel, '4 : 3');
    });
  });

  group('rotate and flip', () {
    test('rotate-left adds 270 clockwise, or 90 while mirrored', () {
      final d = CropDraft.initial(landscape);
      expect(d.rotateLeft().params['rotate'], 270);
      expect(d.rotateLeft().rotateLeft().params['rotate'], 180);
      expect(d.toggleFlip().rotateLeft().params['rotate'], 90);
      expect(d.toggleFlip().params['flip'], 'horizontal');
      expect(d.params['flip'], 'none');
    });

    test('a free box turns with the image', () {
      final d = CropDraft.initial(landscape)
          .resize(width: 1000, height: 500)
          .move(const Offset(-10000, -10000)); // (0,0,1000,500)
      final r = d.rotateLeft();
      // Top-left of a 4000-wide image goes to bottom-left after CCW.
      expect(r.rect, const Rect.fromLTWH(0, 3000, 500, 1000));
      expect(r.params, containsPair('y', 3000));
    });

    test('flip mirrors the box', () {
      final d = CropDraft.initial(
        landscape,
      ).resize(width: 1000, height: 500).move(const Offset(-10000, 0));
      expect(d.toggleFlip().rect.left, 3000);
    });
  });

  group('canvas ↔ pixel mapping', () {
    test('maps through the display rect with the rotation swap', () {
      final d = CropDraft.initial(landscape).rotateLeft();
      // Oriented 3000×4000 drawn at 300×400 offset by (10, 20).
      final m = CropMapping(const Rect.fromLTWH(10, 20, 300, 400), d.bounds);
      expect(m.toPixel(const Offset(160, 220)), const Offset(1500, 2000));
      expect(m.deltaToPixel(const Offset(1, 2)), const Offset(10, 20));
      expect(
        m.toCanvas(const Rect.fromLTWH(1000, 1000, 500, 500)),
        const Rect.fromLTWH(110, 120, 50, 50),
      );
    });
  });

  group('drags and number boxes', () {
    test('locked corner drag keeps the ratio and stays in bounds', () {
      final d = CropDraft.initial(landscape).withRatio(CropRatio.square);
      final g = d.dragCorner(CropCorner.bottomRight, const Offset(5000, 10));
      expect(g.rect.width, g.rect.height);
      expect(g.rect.right, lessThanOrEqualTo(4000));
      expect(g.rect.bottom, lessThanOrEqualTo(3000));
      expect(g.rect.topLeft, d.rect.topLeft);
    });

    test('free corner drag pins the opposite corner', () {
      final d = CropDraft.initial(landscape);
      final g = d.dragCorner(CropCorner.topLeft, const Offset(100, 50));
      expect(g.rect.bottomRight, d.rect.bottomRight);
      expect(g.rect.width, d.rect.width - 100);
    });

    test('width box under a lock moves height too', () {
      final d = CropDraft.initial(
        landscape,
      ).withRatio(CropRatio.square).resize(width: 1000);
      expect(d.pixels.width, 1000);
      expect(d.pixels.height, 1000);
    });

    test('params are integers clamped inside the oriented image', () {
      final d = CropDraft.initial(
        const Size(101, 51),
      ).withRatio(CropRatio.original);
      expect(d.params, {
        'x': 0,
        'y': 0,
        'width': 101,
        'height': 51,
        'rotate': 0,
        'flip': 'none',
      });
    });
  });
}
