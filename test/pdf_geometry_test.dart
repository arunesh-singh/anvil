import 'package:anvil/ui/tool/pdf_geometry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // displayRect 100×200, page 300×600 points ⇒ s = 3 (points per canvas px).
  const displayRect = Rect.fromLTWH(0, 0, 100, 200);
  const pagePt = Size(300, 600);

  test('canvasRectToPdf maps size and flips Y to bottom-left origin', () {
    final r = canvasRectToPdf(
        const Rect.fromLTWH(10, 20, 40, 60), displayRect, pagePt);
    expect(r.x, 30);
    expect(r.width, 120);
    expect(r.height, 180);
    // y = pageH - topFromTop - h = 600 - 60 - 180 = 360.
    expect(r.y, 360);
  });

  test('canvasRectToMargins gives per-edge distances in points', () {
    final m = canvasRectToMargins(
        const Rect.fromLTRB(10, 20, 90, 180), displayRect, pagePt);
    expect(m.left, 30);
    expect(m.top, 60);
    expect(m.right, 30); // (100 - 90) * 3
    expect(m.bottom, 60); // (200 - 180) * 3
  });

  test('canvasPointToPdf flips Y for the bottom-left anchor', () {
    final p = canvasPointToPdf(const Offset(10, 20), displayRect, pagePt);
    expect(p.dx, 30);
    expect(p.dy, 540); // 600 - 60
  });
}
