/// Pure geometry behind the crop screen (design `tools-workspace.html`,
/// frame "Crop"): ratio presets that snap the box, rotate/flip that apply
/// before the crop, corner drags that honour a locked ratio, and the mapping
/// between the on-screen stage and the oriented image's pixels.
///
/// Everything is in the ORIENTED image's pixel space — the image after
/// `rotate` (clockwise) then a horizontal `flip`, exactly what `image/crop`
/// crops (ImageChannel.orient).
library;

import 'dart:math' as math;
import 'dart:ui';

/// The ratio presets on the pill rail.
enum CropRatio {
  original('Original', null),
  free('Free', null),
  square('1:1', 1),
  portrait('4:5', 4 / 5),
  wide('16:9', 16 / 9),
  tall('9:16', 9 / 16);

  const CropRatio(this.label, this._aspect);

  final String label;
  final double? _aspect;

  /// Width / height this preset locks to inside an [oriented] image; null for
  /// [free].
  double? aspectIn(Size oriented) => switch (this) {
    CropRatio.original => oriented.width / oriented.height,
    CropRatio.free => null,
    _ => _aspect,
  };
}

/// The corner a drag grabs.
enum CropCorner { topLeft, topRight, bottomLeft, bottomRight }

/// [px] after rotating [rotate] degrees clockwise (90/270 swap the sides).
Size orientedSize(Size px, int rotate) =>
    (rotate ~/ 90).isOdd ? Size(px.height, px.width) : px;

/// The largest rect of [aspect] (w / h) centred in [bounds].
Rect largestCentred(Size bounds, double aspect) {
  var w = bounds.width;
  var h = w / aspect;
  if (h > bounds.height) {
    h = bounds.height;
    w = h * aspect;
  }
  return Rect.fromCenter(
    center: Offset(bounds.width / 2, bounds.height / 2),
    width: w,
    height: h,
  );
}

/// Stage ↔ pixel mapping for an image of [imagePx] drawn into [display].
class CropMapping {
  const CropMapping(this.display, this.imagePx);

  final Rect display;
  final Size imagePx;

  double get _scale => imagePx.width / display.width;

  Offset toPixel(Offset canvas) => (canvas - display.topLeft) * _scale;

  Offset deltaToPixel(Offset delta) => delta * _scale;

  Rect toCanvas(Rect px) => Rect.fromLTWH(
    display.left + px.left / _scale,
    display.top + px.top / _scale,
    px.width / _scale,
    px.height / _scale,
  );
}

/// One undoable crop state: the source's pixel size, the orientation, the
/// box (oriented pixels), the chosen preset and the locked aspect (null =
/// free corners).
class CropDraft {
  const CropDraft._({
    required this.source,
    required this.rotate,
    required this.flip,
    required this.rect,
    required this.ratio,
    required this.aspect,
  });

  /// Opens with a free box over the middle 80% of [source].
  factory CropDraft.initial(Size source) => CropDraft._(
    source: source,
    rotate: 0,
    flip: false,
    rect: Rect.fromCenter(
      center: Offset(source.width / 2, source.height / 2),
      width: source.width * 0.8,
      height: source.height * 0.8,
    ),
    ratio: CropRatio.free,
    aspect: null,
  );

  final Size source;

  /// Degrees clockwise: 0, 90, 180 or 270.
  final int rotate;

  /// Horizontal mirror, applied after [rotate].
  final bool flip;
  final Rect rect;
  final CropRatio ratio;
  final double? aspect;

  Size get bounds => orientedSize(source, rotate);

  bool get locked => aspect != null;

  CropDraft _copy({
    int? rotate,
    bool? flip,
    Rect? rect,
    CropRatio? ratio,
    double? Function()? aspect,
  }) => CropDraft._(
    source: source,
    rotate: rotate ?? this.rotate,
    flip: flip ?? this.flip,
    rect: rect ?? this.rect,
    ratio: ratio ?? this.ratio,
    aspect: aspect == null ? this.aspect : aspect(),
  );

  /// Snaps to the largest centred box of [r]; [CropRatio.free] keeps the box
  /// and unlocks.
  CropDraft withRatio(CropRatio r) {
    final a = r.aspectIn(bounds);
    if (a == null) return _copy(ratio: r, aspect: () => null);
    return _copy(ratio: r, aspect: () => a, rect: largestCentred(bounds, a));
  }

  /// The link toggle: locks to the current box's aspect, or unlocks (→ Free).
  CropDraft toggleLock() => locked
      ? _copy(ratio: CropRatio.free, aspect: () => null)
      : _copy(aspect: () => rect.width / rect.height);

  /// Turns what is on screen 90° counter-clockwise. A preset re-snaps in the
  /// new orientation; a free box turns with the image.
  CropDraft rotateLeft() {
    // rotCCW ∘ flipH = flipH ∘ rotCW, so a mirrored image turns the other way
    // in the underlying (rotate, then flip) parameters.
    final next = (rotate + (flip ? 90 : 270)) % 360;
    final w = bounds.width;
    final turned = Rect.fromLTWH(
      rect.top,
      w - rect.right,
      rect.height,
      rect.width,
    );
    final moved = _copy(
      rotate: next,
      rect: turned,
      aspect: aspect == null ? null : () => 1 / aspect!,
    );
    return ratio == CropRatio.free ? moved : moved.withRatio(ratio);
  }

  /// Mirrors what is on screen left↔right; the box mirrors with it.
  CropDraft toggleFlip() => _copy(
    flip: !flip,
    rect: Rect.fromLTRB(
      bounds.width - rect.right,
      rect.top,
      bounds.width - rect.left,
      rect.bottom,
    ),
  );

  /// Translates the box by [d] pixels, kept inside the image.
  CropDraft move(Offset d) {
    final l = (rect.left + d.dx).clamp(0.0, bounds.width - rect.width);
    final t = (rect.top + d.dy).clamp(0.0, bounds.height - rect.height);
    return _copy(rect: Rect.fromLTWH(l, t, rect.width, rect.height));
  }

  /// Drags [corner] by [d] pixels with the opposite corner pinned; keeps the
  /// locked aspect, the image bounds and a [minSide] floor.
  CropDraft dragCorner(CropCorner corner, Offset d, {double minSide = 16}) {
    final left =
        corner == CropCorner.topLeft || corner == CropCorner.bottomLeft;
    final top = corner == CropCorner.topLeft || corner == CropCorner.topRight;
    final ax = left ? rect.right : rect.left;
    final ay = top ? rect.bottom : rect.top;
    final maxW = left ? ax : bounds.width - ax;
    final maxH = top ? ay : bounds.height - ay;
    var w = (left ? rect.width - d.dx : rect.width + d.dx);
    var h = (top ? rect.height - d.dy : rect.height + d.dy);
    final a = aspect;
    if (a == null) {
      w = w.clamp(math.min(minSide, maxW), maxW);
      h = h.clamp(math.min(minSide, maxH), maxH);
    } else {
      // Follow whichever axis moved more, then fit inside both limits.
      if ((w - rect.width).abs() < (h - rect.height).abs()) w = h * a;
      final cap = math.min(maxW, maxH * a);
      w = w.clamp(math.min(minSide, cap), cap);
      h = w / a;
    }
    return _copy(
      rect: Rect.fromLTWH(left ? ax - w : ax, top ? ay - h : ay, w, h),
    );
  }

  /// The W/H number boxes: sets the size about the box's centre, keeping a
  /// locked aspect (the edited side wins) and the image bounds.
  CropDraft resize({int? width, int? height}) {
    final a = aspect;
    var w = width?.toDouble() ?? rect.width;
    var h = height?.toDouble() ?? rect.height;
    if (a != null) {
      if (width != null) {
        h = w / a;
      } else {
        w = h * a;
      }
      final cap = math.min(bounds.width, bounds.height * a);
      w = w.clamp(1.0, cap);
      h = w / a;
    } else {
      w = w.clamp(1.0, bounds.width);
      h = h.clamp(1.0, bounds.height);
    }
    final c = rect.center;
    final l = (c.dx - w / 2).clamp(0.0, bounds.width - w);
    final t = (c.dy - h / 2).clamp(0.0, bounds.height - h);
    return _copy(rect: Rect.fromLTWH(l, t, w, h));
  }

  /// The integer box sent to the tool, clamped inside the oriented image.
  ({int x, int y, int width, int height}) get pixels {
    final bw = bounds.width.round();
    final bh = bounds.height.round();
    final x = rect.left.round().clamp(0, bw - 1);
    final y = rect.top.round().clamp(0, bh - 1);
    return (
      x: x,
      y: y,
      width: rect.width.round().clamp(1, bw - x),
      height: rect.height.round().clamp(1, bh - y),
    );
  }

  /// `image/crop` params.
  Map<String, Object> get params {
    final p = pixels;
    return {
      'x': p.x,
      'y': p.y,
      'width': p.width,
      'height': p.height,
      'rotate': rotate,
      'flip': flip ? 'horizontal' : 'none',
    };
  }

  /// The stage's mono ratio pill: "1 : 1", "4 : 5", or "Free".
  String get ratioLabel {
    final a = aspect;
    if (a == null) return 'Free';
    for (final r in CropRatio.values) {
      final ra = r._aspect;
      if (ra != null && (ra - a).abs() < 0.005) {
        return r.label.replaceAll(':', ' : ');
      }
    }
    final b = bounds;
    final g = _gcd(b.width.round(), b.height.round());
    final rw = b.width.round() ~/ g;
    final rh = b.height.round() ~/ g;
    if ((rw / rh - a).abs() < 0.005 && rw <= 32 && rh <= 32) {
      return '$rw : $rh';
    }
    return a >= 1
        ? '${a.toStringAsFixed(2)} : 1'
        : '1 : ${(1 / a).toStringAsFixed(2)}';
  }
}

int _gcd(int a, int b) => b == 0 ? (a == 0 ? 1 : a) : _gcd(b, a % b);
