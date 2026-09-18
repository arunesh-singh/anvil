import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Data model for the WYSIWYG PDF editor (Create + Edit).
///
/// All element coordinates are in PAGE-POINT space with a top-left origin (the
/// same convention as the on-screen canvas). At export the elements are painted
/// into a transparent PNG the size of the page and stamped upright over it, so
/// no Y-flip is needed anywhere.

/// Maps a base-14 family name to a Flutter font family (null = default sans).
String? flutterFamily(String family) => switch (family) {
      'Times' => 'serif',
      'Courier' => 'monospace',
      _ => null,
    };

/// A shape primitive kind.
enum ShapeKind { rect, line }

/// One placed element. Sealed so the painter/exporter switch is exhaustive.
sealed class DocElement {
  const DocElement();
  DocElement copy();
}

class TextEl extends DocElement {
  TextEl({
    required this.text,
    required this.posPt,
    required this.sizePt,
    required this.family,
    required this.bold,
    required this.italic,
    required this.color,
    required this.opacity,
  });

  String text;
  Offset posPt; // top-left of the text box, page points
  double sizePt;
  String family;
  bool bold;
  bool italic;
  Color color;
  double opacity;

  @override
  TextEl copy() => TextEl(
        text: text,
        posPt: posPt,
        sizePt: sizePt,
        family: family,
        bold: bold,
        italic: italic,
        color: color,
        opacity: opacity,
      );
}

class ImageEl extends DocElement {
  ImageEl({required this.png, required this.rectPt});

  Uint8List png;
  Rect rectPt;

  @override
  ImageEl copy() => ImageEl(png: png, rectPt: rectPt);
}

class StrokeEl extends DocElement {
  StrokeEl({required this.pointsPt, required this.color, required this.widthPt});

  List<Offset> pointsPt;
  Color color;
  double widthPt;

  @override
  StrokeEl copy() =>
      StrokeEl(pointsPt: List.of(pointsPt), color: color, widthPt: widthPt);
}

class HighlightEl extends DocElement {
  HighlightEl({required this.rectPt, required this.color});

  Rect rectPt;
  Color color; // alpha ~0.35 baked in

  @override
  HighlightEl copy() => HighlightEl(rectPt: rectPt, color: color);
}

class BlackoutEl extends DocElement {
  BlackoutEl({required this.rectPt, required this.color});

  Rect rectPt;
  Color color;

  @override
  BlackoutEl copy() => BlackoutEl(rectPt: rectPt, color: color);
}

class ShapeEl extends DocElement {
  ShapeEl({
    required this.kind,
    required this.rectPt,
    required this.color,
    required this.strokePt,
    required this.filled,
  });

  ShapeKind kind;
  Rect rectPt;
  Color color;
  double strokePt;
  bool filled;

  @override
  ShapeEl copy() => ShapeEl(
        kind: kind,
        rectPt: rectPt,
        color: color,
        strokePt: strokePt,
        filled: filled,
      );
}

/// One page: its point size, an optional rendered background (Edit), and the
/// list of placed elements.
class DocPage {
  DocPage({required this.sizePt, this.background, List<DocElement>? elements})
      : elements = elements ?? [];

  final ({double w, double h}) sizePt;
  Uint8List? background;
  List<DocElement> elements;

  DocPage copy() => DocPage(
        sizePt: sizePt,
        background: background,
        elements: [for (final e in elements) e.copy()],
      );
}

/// The whole document. Deep-copied onto an undo/redo stack per mutation.
class DocModel {
  DocModel(this.pages);

  List<DocPage> pages;

  DocModel copy() => DocModel([for (final p in pages) p.copy()]);
}
