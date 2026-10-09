/// Clamped move/resize math for a draggable rectangle with four corner grips.
/// Shared by the watermark-erase editor, the image crop step and the PDF
/// workspace crop sheet so every rectangle editor drags the same way.
library;

import 'dart:ui';

/// Which part of the rectangle a drag is attached to: the body or a corner.
enum RectGrip { move, tl, tr, bl, br }

/// Moves/resizes [r] by [delta] for [grip], clamped inside [bounds], keeping
/// each side at least [minSize]. A [RectGrip.move] keeps the size unchanged.
Rect dragRect(
  Rect r,
  RectGrip grip,
  Offset delta,
  Rect bounds, {
  double minSize = 24,
}) {
  final Rect moved = switch (grip) {
    RectGrip.move => r.shift(delta),
    RectGrip.tl => Rect.fromLTRB(
      r.left + delta.dx,
      r.top + delta.dy,
      r.right,
      r.bottom,
    ),
    RectGrip.tr => Rect.fromLTRB(
      r.left,
      r.top + delta.dy,
      r.right + delta.dx,
      r.bottom,
    ),
    RectGrip.bl => Rect.fromLTRB(
      r.left + delta.dx,
      r.top,
      r.right,
      r.bottom + delta.dy,
    ),
    RectGrip.br => Rect.fromLTRB(
      r.left,
      r.top,
      r.right + delta.dx,
      r.bottom + delta.dy,
    ),
  };
  if (grip == RectGrip.move) {
    final w = r.width;
    final h = r.height;
    final l = moved.left.clamp(bounds.left, bounds.right - w);
    final t = moved.top.clamp(bounds.top, bounds.bottom - h);
    return Rect.fromLTRB(l, t, l + w, t + h);
  }
  final l = moved.left.clamp(bounds.left, bounds.right - minSize);
  final t = moved.top.clamp(bounds.top, bounds.bottom - minSize);
  final rt = moved.right.clamp(l + minSize, bounds.right);
  final b = moved.bottom.clamp(t + minSize, bounds.bottom);
  return Rect.fromLTRB(l, t, rt, b);
}
