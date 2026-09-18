/// PDF tools. Every op funnels through [PdfEngine] (pdf_manipulator); exotic
/// raster inputs (gif/tiff/webp) normalize to PNG via the pure codecs in
/// `image_codecs.dart`; HEIC decodes through the native [ImageEngine]; and
/// URL→PDF renders through the Kotlin `anvil/pdf` channel.
/// The single registration list for this category lives in [buildPdfTools].
library;

import 'dart:convert';

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/services.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart' show PdfRect, PdfColor;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/isolate_runner.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/image_engine.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/tools/image/image_codecs.dart' as codecs;
import 'package:anvil/tools/pdf/pdf_text.dart';

const _pdfMime = 'application/pdf';
const _txtMime = 'text/plain';
const _csvMime = 'text/csv';

/// One produced file from a many-output PDF op: its bytes plus extension/mime.
typedef _OutItem = ({Uint8List bytes, String ext, String mime});

// ── Helpers ──────────────────────────────────────────────────────────────────

String _outName(String input, String ext, {int? index}) {
  final dot = input.lastIndexOf('.');
  final base = dot <= 0 ? input : input.substring(0, dot);
  return index == null ? '$base.$ext' : '${base}_${index + 1}.$ext';
}

int _intParam(Map<String, dynamic> params, String key, int fallback) =>
    switch (params[key]) { final int v => v, _ => fallback };

String _textParam(Map<String, dynamic> params, String key, String fallback) =>
    switch (params[key]) {
      final String v when v.trim().isNotEmpty => v.trim(),
      _ => fallback,
    };

String _requiredText(Map<String, dynamic> params, String key, String what) =>
    switch (params[key]) {
      final String v when v.trim().isNotEmpty => v.trim(),
      _ => throw ToolException('Enter $what.'),
    };

Future<Uint8List> _readBytes(InputFile f) async =>
    await getIt<FileService>().readBytes(f.path) as Uint8List;

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  final e = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return e == 'jpeg' ? 'jpg' : (e == 'tif' ? 'tiff' : e);
}

/// Normalizes any accepted raster input to bytes `imagesToPdf` understands
/// (jpg/png pass through; gif/tiff/webp/psd transcode; heic decodes natively).
Future<Uint8List> _toPdfReadyImage(Uint8List src, String ext) => switch (ext) {
      'jpg' || 'png' => Future.value(src),
      'heic' || 'heif' =>
        getIt<ImageEngine>().convert(src, format: 'png', quality: 100),
      _ => runOffThread(() => codecs.transcode(src, ext, 'png')),
    };

// ── Generic tool shapes ──────────────────────────────────────────────────────

/// Single PDF → single PDF (rotate, compress, protect, watermark, …).
class _PdfToPdf extends BaseToolModule {
  _PdfToPdf(this.meta, this._fn);
  @override
  final ToolMeta meta;
  final Future<Uint8List> Function(
      PdfEngine e, Uint8List bytes, Map<String, dynamic> params) _fn;

  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading PDF…');
    final f = input.files.single;
    final bytes = await _readBytes(f);
    yield const ToolRunning(fraction: 0.3, message: 'Processing…');
    final out = await _fn(getIt<PdfEngine>(), bytes, input.params);
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(f.name, 'pdf');
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _pdfMime)],
    ));
  }
}

/// Many files → single PDF (merge, image→pdf converts).
class _ManyToPdf extends BaseToolModule {
  _ManyToPdf(this.meta, this._fn, {this.minFiles = 1});
  @override
  final ToolMeta meta;
  final Future<Uint8List> Function(PdfEngine e, List<InputFile> files) _fn;
  final int minFiles;

  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    if (input.files.length < minFiles) {
      throw ToolException('Select at least $minFiles files.');
    }
    yield const ToolRunning(message: 'Reading files…');
    yield const ToolRunning(fraction: 0.3, message: 'Building PDF…');
    final out = await _fn(getIt<PdfEngine>(), input.files);
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(input.files.first.name, 'pdf');
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _pdfMime)],
    ));
  }
}

/// Single PDF → many files (split, page renders, extract-img).
class _PdfToMany extends BaseToolModule {
  _PdfToMany(this.meta, this._fn);
  @override
  final ToolMeta meta;
  final Future<List<_OutItem>> Function(
      PdfEngine e, Uint8List bytes, Map<String, dynamic> params) _fn;

  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading PDF…');
    final f = input.files.single;
    final bytes = await _readBytes(f);
    yield const ToolRunning(fraction: 0.3, message: 'Processing…');
    final items = await _fn(getIt<PdfEngine>(), bytes, input.params);
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final files = <OutputFile>[];
    for (var i = 0; i < items.length; i++) {
      final name = _outName(f.name, items[i].ext, index: i);
      final file = await getIt<FileService>().writeBytes(name, items[i].bytes);
      files.add(OutputFile(path: file.path, name: name, mimeType: items[i].mime));
    }
    yield ToolSucceeded(ToolResult(files: files));
  }
}

/// Single PDF → text file; the text also shows inline on the result screen.
class _PdfToTextFile extends BaseToolModule {
  _PdfToTextFile(this.meta, {this.toCsv = false});
  @override
  final ToolMeta meta;
  final bool toCsv;

  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading PDF…');
    final f = input.files.single;
    final bytes = await _readBytes(f);
    yield const ToolRunning(fraction: 0.3, message: 'Extracting text…');
    final raw = await getIt<PdfEngine>().extractText(bytes);
    if (raw.trim().isEmpty) {
      throw const ToolException(
          'No selectable text found — this PDF may be scanned images.');
    }
    final text = toCsv ? raw : _formatExtracted(raw);
    final out = toCsv ? await runOffThread(() => pdfTextToCsv(raw)) : text;
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(f.name, toCsv ? 'csv' : 'txt');
    final file = await getIt<FileService>().writeString(name, out);
    yield ToolSucceeded(ToolResult(
      files: [
        OutputFile(
            path: file.path, name: name, mimeType: toCsv ? _csvMime : _txtMime),
      ],
      text: toCsv ? null : text,
    ));
  }
}

/// PDF (first file) + image (second file) → PDF with the image stamped on one
/// page (sign, add-images).
class _PdfPlusImage extends BaseToolModule {
  _PdfPlusImage(this.meta);
  @override
  final ToolMeta meta;

  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    final pdfFile = input.files
        .where((f) => _ext(f.name) == 'pdf')
        .firstOrNull;
    final imageFile = input.files
        .where((f) => const ['png', 'jpg'].contains(_ext(f.name)))
        .firstOrNull;
    if (pdfFile == null || imageFile == null) {
      throw const ToolException('Select one PDF and one PNG/JPG image.');
    }
    yield const ToolRunning(message: 'Reading files…');
    final pdf = await _readBytes(pdfFile);
    final image = await _readBytes(imageFile);
    final e = getIt<PdfEngine>();
    final p = input.params;
    final page = _intParam(p, 'page', 1);
    final pages = await e.pageCount(pdf);
    if (page < 1 || page > pages) {
      throw ToolException('Page $page is out of range — the PDF has $pages pages.');
    }
    yield const ToolRunning(fraction: 0.4, message: 'Stamping…');
    Future<Uint8List> stamp(Uint8List img) => e.addImageStamp(
          pdf,
          img,
          pageIndex: page - 1,
          x: _intParam(p, 'x', 40).toDouble(),
          y: _intParam(p, 'y', 40).toDouble(),
          width: _intParam(p, 'width', 160).toDouble(),
          height: _intParam(p, 'height', 80).toDouble(),
        );
    final Uint8List out = await () async {
      try {
        return await stamp(image);
      } on ToolException {
        // The native PDF lib rejects some PNG/JPG encodings with a generic
        // "invalid image: Unsupported image format" (the same file can stamp
        // on another page). Re-encode to a canonical 8-bit PNG and retry once;
        // a decode failure here means the image really is unreadable.
        final Uint8List canonical;
        try {
          canonical = await runOffThread(
              () => codecs.transcode(image, _ext(imageFile.name), 'png'));
        } catch (_) {
          throw const ToolException(
              "Couldn't read this image — try a standard PNG or JPG.");
        }
        return stamp(canonical);
      }
    }();
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(pdfFile.name, 'pdf');
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _pdfMime)],
    ));
  }
}

/// Single image → one-page PDF with the photo centered and a caption below.
/// A composite so the agent turns "photo + name → PDF" into ONE reliable step
/// (identify → this) instead of a fragile create/add-image/add-text chain.
class _PhotoCaption extends BaseToolModule {
  _PhotoCaption(this.meta);
  @override
  final ToolMeta meta;

  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    final f = input.files.single;
    final caption = _textParam(input.params, 'caption', '');
    yield const ToolRunning(message: 'Reading image…');
    final ext = _ext(f.name);
    final ready = await _toPdfReadyImage(
        await _readBytes(f), ext == 'jpeg' ? 'jpg' : ext);
    yield const ToolRunning(fraction: 0.6, message: 'Building PDF…');
    final out = await _photoCaptionPdf(ready, caption);
    yield const ToolRunning(fraction: 0.9, message: 'Saving…');
    final name = _outName(f.name, 'pdf');
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _pdfMime)],
    ));
  }
}

/// Zero-input: renders a web page to PDF via the Kotlin `anvil/pdf` channel
/// (Android WebView print pipeline). Device-only by nature.
class _UrlToPdf extends BaseToolModule {
  _UrlToPdf(this.meta);
  @override
  final ToolMeta meta;

  static const _channel = MethodChannel('anvil/pdf');

  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    var url = _requiredText(input.params, 'url', 'a web page URL');
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final out = await getIt<FileService>().reserveFile('webpage.pdf');
    yield const ToolRunning(message: 'Loading page…');
    try {
      await _channel.invokeMethod<void>('fromUrl', {
        'url': url,
        'outPath': out.path,
      });
    } on PlatformException catch (e) {
      throw ToolException(e.message ?? 'Could not render the page.');
    } on MissingPluginException {
      throw const ToolException(
          'URL to PDF is not available on this platform.');
    }
    if (!await out.exists() || await out.length() == 0) {
      throw const ToolException('Could not render the page.');
    }
    yield ToolSucceeded(ToolResult(
      files: [
        OutputFile(path: out.path, name: 'webpage.pdf', mimeType: _pdfMime),
      ],
    ));
  }
}

/// Compress PDF with a user-selected method. `optimize` re-encodes embedded
/// images (keeps selectable text); `raster` renders each page to a JPEG at a
/// chosen DPI (much smaller for scans, but text stops being selectable). The
/// output never exceeds the input.
class _PdfCompress extends BaseToolModule {
  _PdfCompress(this.meta);
  @override
  final ToolMeta meta;
  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading PDF…');
    final f = input.files.single;
    final bytes = await _readBytes(f);
    final e = getIt<PdfEngine>();
    final p = input.params;
    final method = _textParam(p, 'method', 'optimize');
    final quality = _intParam(p, 'quality', 60).clamp(10, 95).toInt();
    Uint8List out;
    if (method == 'raster') {
      final dpi = _intParam(p, 'dpi', 150).clamp(72, 300).toInt();
      final infos = await e.pageInfos(bytes);
      final img = getIt<ImageEngine>();
      final jpgs = <Uint8List>[];
      for (var i = 0; i < infos.length; i++) {
        yield ToolRunning(
            fraction: 0.1 + 0.7 * (i / infos.length),
            message: 'Rasterizing page ${i + 1}/${infos.length}…');
        final w = (infos[i].width / 72 * dpi).round().clamp(1, 3000).toInt();
        final h = (infos[i].height / 72 * dpi).round().clamp(1, 3000).toInt();
        final png =
            (await e.renderPage(bytes, i, maxWidth: w, maxHeight: h)).bytes;
        jpgs.add(await img.compress(png, quality: quality, format: 'jpg'));
      }
      yield const ToolRunning(fraction: 0.85, message: 'Assembling…');
      out = await e.imagesToPdf(jpgs);
    } else {
      yield const ToolRunning(fraction: 0.4, message: 'Optimizing images…');
      out = await e.compress(bytes, quality);
    }
    if (out.length >= bytes.length) {
      out = bytes;
      yield const ToolRunning(
          fraction: 0.9, message: 'Already optimally compressed.');
    }
    yield const ToolRunning(fraction: 0.92, message: 'Saving…');
    final name = _outName(f.name, 'pdf');
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _pdfMime)],
    ));
  }
}

/// A4 (595×842pt) / US Letter (612×792pt) point dimensions for a named size;
/// anything unrecognised falls back to A4.
({double w, double h}) _pageSize(String name) => switch (name.toLowerCase()) {
      'letter' => (w: 612, h: 792),
      _ => (w: 595, h: 842),
    };

/// Composes a PDF from per-page transparent PNG overlays flattened by the
/// WYSIWYG editor. `create` builds blank pages of the given point sizes;
/// `edit` stamps overlays onto an existing document (base content preserved).
/// Params: `mode` (`create`|`edit`), `overlayIndexJson` (page index per overlay
/// file), and for create `pageSizesJson` (`[[w,h],…]`).
class _PdfCompose extends BaseToolModule {
  _PdfCompose(this.meta, {this.defaultMode = 'edit'});
  @override
  final ToolMeta meta;

  /// Mode when the caller omits `mode`: the editor always sets it, but the
  /// agent does not, so `pdf/create` defaults to `create` and `pdf/edit` to
  /// `edit`.
  final String defaultMode;
  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    final p = input.params;
    final mode = _textParam(p, 'mode', defaultMode);
    final idx = [
      for (final v in jsonDecode(_textParam(p, 'overlayIndexJson', '[]')) as List)
        (v as num).toInt(),
    ];
    final e = getIt<PdfEngine>();
    yield const ToolRunning(message: 'Reading…');
    Uint8List pdf;
    List<InputFile> overlayFiles;
    if (mode == 'create') {
      // The editor supplies explicit per-page sizes; the agent supplies a
      // simple page count + named size instead.
      final explicit =
          jsonDecode(_textParam(p, 'pageSizesJson', '[]')) as List;
      final sizes = explicit.isNotEmpty
          ? [
              for (final s in explicit)
                (
                  w: ((s as List)[0] as num).toDouble(),
                  h: (s[1] as num).toDouble(),
                ),
            ]
          : List.filled(
              _intParam(p, 'pages', 1).clamp(1, 50),
              _pageSize(_textParam(p, 'size', 'a4')),
            );
      pdf = await e.createBlankPdf(sizes);
      overlayFiles = input.files;
    } else {
      if (input.files.isEmpty) {
        throw const ToolException('Pick a PDF to edit.');
      }
      pdf = await _readBytes(input.files.first);
      overlayFiles = input.files.skip(1).toList();
    }
    if (idx.length != overlayFiles.length) {
      throw const ToolException('Overlay page mapping is invalid.');
    }
    yield const ToolRunning(fraction: 0.5, message: 'Stamping…');
    final overlays = <({int page, Uint8List png})>[
      for (var k = 0; k < overlayFiles.length; k++)
        (page: idx[k], png: await _readBytes(overlayFiles[k])),
    ];
    final out = await e.stampOverlays(pdf, overlays);
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = mode == 'create'
        ? 'document.pdf'
        : _outName(input.files.first.name, 'pdf');
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _pdfMime)],
    ));
  }
}

/// Per-page crop. `marginsJson` is a JSON array (one entry per page) of
/// `{l,t,r,b}` point margins, or `null` to leave that page uncropped.
class _PdfCrop extends BaseToolModule {
  _PdfCrop(this.meta);
  @override
  final ToolMeta meta;
  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading PDF…');
    final f = input.files.single;
    final bytes = await _readBytes(f);
    final raw = jsonDecode(
        _requiredText(input.params, 'marginsJson', 'a crop region')) as List;
    final perPage = <({double left, double top, double right, double bottom})?>[
      for (final m in raw)
        m == null
            ? null
            : (
                left: (m['l'] as num).toDouble(),
                top: (m['t'] as num).toDouble(),
                right: (m['r'] as num).toDouble(),
                bottom: (m['b'] as num).toDouble(),
              ),
    ];
    yield const ToolRunning(fraction: 0.4, message: 'Cropping…');
    final out = await getIt<PdfEngine>().cropPerPage(bytes, perPage);
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(f.name, 'pdf');
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _pdfMime)],
    ));
  }
}

/// Cleans extracted text: strips trailing whitespace per line and collapses
/// runs of 3+ blank lines to a single blank line.
String _formatExtracted(String text) => text
    .split('\n')
    .map((l) => l.replaceAll(RegExp(r'[ \t]+$'), ''))
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n');

/// Maps a family + style flags to a PDF base-14 font name. Helvetica/Courier
/// use `-Oblique` for italic; Times uses `-Italic`.
String _base14Font(String family, bool bold, bool italic) => switch (family) {
      'Times' => bold && italic
          ? 'Times-BoldItalic'
          : bold
              ? 'Times-Bold'
              : italic
                  ? 'Times-Italic'
                  : 'Times-Roman',
      'Courier' => bold && italic
          ? 'Courier-BoldOblique'
          : bold
              ? 'Courier-Bold'
              : italic
                  ? 'Courier-Oblique'
                  : 'Courier',
      _ => bold && italic
          ? 'Helvetica-BoldOblique'
          : bold
              ? 'Helvetica-Bold'
              : italic
                  ? 'Helvetica-Oblique'
                  : 'Helvetica',
    };

/// Parses `#RRGGBB` (0..1 components) for the PDF text engine.
PdfColor _pdfColorFromHex(String hex) {
  final h = hex.replaceFirst('#', '').trim();
  final v = h.length == 6 ? int.tryParse(h, radix: 16) : null;
  if (v == null) return PdfColor.black;
  return PdfColor(
      ((v >> 16) & 0xFF) / 255, ((v >> 8) & 0xFF) / 255, (v & 0xFF) / 255);
}

/// Builds a one-page A4 PDF: [image] (PNG/JPG bytes from [_toPdfReadyImage])
/// centered on the page, with [caption] centered beneath it when non-empty.
Future<Uint8List> _photoCaptionPdf(Uint8List image, String caption) {
  final doc = pw.Document();
  final photo = pw.MemoryImage(image);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Center(child: pw.Image(photo, fit: pw.BoxFit.contain)),
          ),
          if (caption.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              caption,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ],
      ),
    ),
  );
  return doc.save();
}

// ── Registration ─────────────────────────────────────────────────────────────

ToolMeta _meta(
  String id,
  String label,
  IconData icon,
  String description,
  List<String> accepts, {
  List<ToolParam> params = const [],
  bool acceptsMultiple = false,
  bool requiresInput = true,
  bool agentCallable = true,
  List<String> keywords = const [],
}) => ToolMeta(
  id: id,
  category: ToolCategory.pdf,
  label: label,
  icon: icon,
  description: description,
  tinywowSlug: id,
  acceptedExtensions: accepts,
  params: params,
  acceptsMultiple: acceptsMultiple,
  requiresInput: requiresInput,
  agentCallable: agentCallable,
  keywords: keywords,
);

const _pdf = ['pdf'];

const _stampParams = [
  ToolParam(key: 'page', label: 'Page (1-based)', defaultValue: 1),
  ToolParam(key: 'x', label: 'X (points from left)', defaultValue: 40),
  ToolParam(key: 'y', label: 'Y (points from bottom)', defaultValue: 40),
  ToolParam(key: 'width', label: 'Width (points)', defaultValue: 160),
  ToolParam(key: 'height', label: 'Height (points)', defaultValue: 80),
];

/// `from-<format>` image→PDF tool (one page per selected image).
_ManyToPdf _fromImages(String slug, String format, List<String> accepts) =>
    _ManyToPdf(
      _meta(
        'from-$slug',
        '${format.toUpperCase()} to PDF',
        Icons.picture_as_pdf,
        'Combine $format images into a single PDF, one image per page.',
        accepts,
        acceptsMultiple: true,
      ),
      (e, files) async {
        final ready = <Uint8List>[];
        for (final f in files) {
          ready.add(await _toPdfReadyImage(await _readBytes(f), _ext(f.name)));
        }
        return e.imagesToPdf(ready);
      },
    );

/// Page renders → raster files tool (to-png / to-jpg / to-tiff).
_PdfToMany _toImages(String slug, String format) => _PdfToMany(
      _meta(
        'to-$slug',
        'PDF to ${format.toUpperCase()}',
        Icons.collections,
        'Render each PDF page as a ${format.toUpperCase()} image.',
        _pdf,
      ),
      (e, b, p) async => [
        for (final im in await e.renderToPng(b))
          format == 'png'
              ? (bytes: im.bytes, ext: 'png', mime: 'image/png')
              : (
                  bytes: await runOffThread(
                      () => codecs.transcode(im.bytes, 'png', format)),
                  ext: format,
                  mime: format == 'jpg' ? 'image/jpeg' : 'image/tiff',
                ),
      ],
    );

/// Add-text tool: vector, selectable text placed at a chosen position with
/// base-14 font family, bold/italic, color, size, and opacity.
_PdfToPdf _textOverlay(String id, String label, IconData icon,
        String description) =>
    _PdfToPdf(
      _meta(id, label, icon, description, _pdf, params: [
        const ToolParam(
            key: 'text',
            label: 'Text',
            type: ToolParamType.text,
            defaultText: ''),
        const ToolParam(
            key: 'page', label: 'Page (1-based, 0 = all pages)', defaultValue: 1),
        const ToolParam(key: 'x', label: 'X (points from left)', defaultValue: 40),
        const ToolParam(key: 'y', label: 'Y (points from bottom)', defaultValue: 40),
        const ToolParam(key: 'fontSize', label: 'Font size (pt)', defaultValue: 18),
        const ToolParam(
            key: 'opacity', label: 'Opacity (%)', defaultValue: 100),
        const ToolParam(
            key: 'fontFamily',
            label: 'Font family',
            type: ToolParamType.text,
            defaultText: 'Helvetica'),
        const ToolParam(key: 'bold', label: 'Bold (0/1)', defaultValue: 0),
        const ToolParam(key: 'italic', label: 'Italic (0/1)', defaultValue: 0),
        const ToolParam(
            key: 'color',
            label: 'Color (#RRGGBB)',
            type: ToolParamType.text,
            defaultText: '#000000'),
      ]),
      (e, b, p) async {
        final text = _requiredText(p, 'text', 'the text to add');
        final page = _intParam(p, 'page', 1);
        if (page > 0) {
          final pages = await e.pageCount(b);
          if (page > pages) {
            throw ToolException(
                'Page $page is out of range — the PDF has $pages pages.');
          }
        }
        final family = _textParam(p, 'fontFamily', 'Helvetica');
        final bold = _intParam(p, 'bold', 0) == 1;
        final italic = _intParam(p, 'italic', 0) == 1;
        return e.addText(
          b,
          text,
          pageIndex: page <= 0 ? -1 : page - 1,
          x: _intParam(p, 'x', 40).toDouble(),
          y: _intParam(p, 'y', 40).toDouble(),
          fontSize: _intParam(p, 'fontSize', 18).toDouble(),
          opacity: (_intParam(p, 'opacity', 100).clamp(1, 100)) / 100.0,
          fontName: _base14Font(family, bold, italic),
          color: _pdfColorFromHex(_textParam(p, 'color', '#000000')),
        );
      },
    );

/// Every PDF tool. The single registration list for this category.
List<ToolModule> buildPdfTools() => [
  _PdfPlusImage(
    _meta('add-images', 'Add Image to PDF', Icons.add_photo_alternate,
        'Stamp an image onto a page of an existing PDF.', const ['pdf', 'png', 'jpg'],
        params: _stampParams, acceptsMultiple: true),
  ),
  _PdfToPdf(
    _meta('add-pages', 'Add Pages', Icons.post_add,
        'Append blank pages to the end of a PDF.', _pdf,
        params: const [
          ToolParam(key: 'count', label: 'Blank pages to add', defaultValue: 1),
        ]),
    (e, b, p) {
      final count = _intParam(p, 'count', 1);
      if (count < 1 || count > 100) {
        throw const ToolException('Add between 1 and 100 pages.');
      }
      return e.appendBlankPages(b, count);
    },
  ),
  _textOverlay('add-text', 'Add Text to PDF', Icons.text_increase,
      'Place text at a chosen position on a PDF page.'),
  _PhotoCaption(_meta(
    'photo-caption',
    'Image in a PDF',
    Icons.image,
    'Make a PDF with the image centered on the page, and an optional caption below it.',
    const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
    params: const [
      ToolParam(
          key: 'caption',
          label: 'Caption',
          type: ToolParamType.text,
          helperText: 'Optional text shown centered below the image'),
    ],
  )),
  _PdfCompress(
    _meta('compress', 'Compress PDF', Icons.compress,
        'Shrink a PDF — optimize images (keeps text) or rasterize pages.', _pdf,
        params: const [
          ToolParam(
              key: 'method',
              label: 'Method',
              type: ToolParamType.text,
              defaultText: 'optimize',
              helperText: 'optimize = keep selectable text; '
                  'raster = smaller, images only'),
          ToolParam(
              key: 'quality',
              label: 'Image quality',
              defaultValue: 60,
              min: 10,
              max: 95,
              helperText: 'lower = smaller file'),
          ToolParam(
              key: 'dpi',
              label: 'Raster DPI',
              defaultValue: 150,
              min: 72,
              max: 300,
              helperText: 'only used when method = raster'),
        ]),
  ),
  _PdfCompose(
    _meta('create', 'Create PDF', Icons.note_add,
        'Create a new PDF from scratch — a blank document of the chosen size '
        'and page count, ready to add images or text.',
        const [],
        requiresInput: false,
        params: const [
          ToolParam(
              key: 'pages', label: 'Pages', defaultValue: 1, min: 1, max: 50),
          ToolParam(
              key: 'size',
              label: 'Page size',
              type: ToolParamType.text,
              defaultText: 'a4',
              helperText: 'a4 or letter'),
        ]),
    defaultMode: 'create',
  ),
  _PdfCrop(
    _meta('crop', 'Crop PDF', Icons.crop,
        'Trim page margins — shared or per-page, on selected pages.', _pdf,
        agentCallable: false),
  ),
  _PdfToPdf(
    _meta('delete', 'Delete Pages', Icons.delete_sweep,
        'Remove chosen pages from a PDF.', _pdf,
        params: const [
          ToolParam(
              key: 'pages',
              label: 'Pages to delete (e.g. 2,4-6)',
              type: ToolParamType.text,
              defaultText: ''),
        ]),
    (e, b, p) async {
      final spec = _requiredText(p, 'pages', 'the pages to delete (e.g. 2,4-6)');
      final count = await e.pageCount(b);
      final pages = parsePageList(spec, count);
      if (pages.length >= count) {
        throw const ToolException('Cannot delete every page of the PDF.');
      }
      return e.deletePages(b, pages);
    },
  ),
  _PdfCompose(
    _meta('edit', 'Edit PDF', Icons.edit_document,
        'Full editor — add text, images, highlights, shapes, and signatures.',
        _pdf, agentCallable: false),
  ),
  _PdfToMany(
    _meta('extract-img', 'Extract Images', Icons.image,
        'Pull every embedded image out of a PDF.', _pdf),
    (e, b, p) async => [
      for (final im in await e.extractImages(b))
        (bytes: im.bytes, ext: im.ext, mime: im.mime),
    ],
  ),
  _PdfToTextFile(
    _meta('extract-text', 'Extract Text', Icons.text_snippet,
        'Extract selectable text from a PDF.', _pdf),
  ),
  _fromImages('gif', 'GIF', const ['gif']),
  _fromImages('heic', 'HEIC', const ['heic', 'heif']),
  _fromImages('jpg', 'JPG', const ['jpg', 'jpeg']),
  _fromImages('png', 'PNG', const ['png']),
  _fromImages('tiff', 'TIFF', const ['tiff', 'tif']),
  _UrlToPdf(
    _meta('from-url', 'Website to PDF', Icons.public,
        'Render a web page into a PDF.', const [],
        params: const [
          ToolParam(
              key: 'url',
              label: 'Page URL',
              type: ToolParamType.text,
              defaultText: ''),
        ],
        requiresInput: false),
  ),
  _fromImages('webp', 'WebP', const ['webp']),
  _ManyToPdf(
    _meta('merge', 'Merge PDFs', Icons.merge,
        'Combine several PDF files into one document.', _pdf,
        acceptsMultiple: true),
    (e, files) async =>
        e.merge([for (final f in files) await _readBytes(f)]),
    minFiles: 2,
  ),
  _PdfToPdf(
    _meta('protect', 'Protect PDF', Icons.lock,
        'Encrypt a PDF with a password (AES-256).', _pdf,
        params: const [
          ToolParam(
              key: 'password',
              label: 'Password',
              type: ToolParamType.text,
              defaultText: ''),
        ]),
    (e, b, p) => e.protect(b, _requiredText(p, 'password', 'a password')),
  ),
  _PdfToPdf(
    _meta('rearrange', 'Rearrange Pages', Icons.low_priority,
        'Reorder (or subset) PDF pages.', _pdf,
        params: const [
          ToolParam(
              key: 'order',
              label: 'New page order (e.g. 3,1,2)',
              type: ToolParamType.text,
              defaultText: ''),
        ]),
    (e, b, p) async {
      final spec = _requiredText(p, 'order', 'the new page order (e.g. 3,1,2)');
      final count = await e.pageCount(b);
      final order = [
        for (final part in spec.split(','))
          switch (int.tryParse(part.trim())) {
            final int v when v >= 1 && v <= count => v - 1,
            _ => throw ToolException(
                "Invalid page '${part.trim()}' — the PDF has $count pages."),
          },
      ];
      return e.reorderPages(b, order);
    },
  ),
  _PdfToPdf(
    _meta('remove-watermark', 'Remove Watermark', Icons.layers_clear,
        'Erase the same rectangular region on every page (covers stamped '
        'watermarks).', _pdf,
        params: const [
          ToolParam(key: 'x', label: 'X (points from left)', defaultValue: 150),
          ToolParam(key: 'y', label: 'Y (points from bottom)', defaultValue: 350),
          ToolParam(key: 'width', label: 'Width (points)', defaultValue: 300),
          ToolParam(key: 'height', label: 'Height (points)', defaultValue: 150),
        ]),
    (e, b, p) => e.eraseRegionAllPages(
      b,
      PdfRect(
        x: _intParam(p, 'x', 150).toDouble(),
        y: _intParam(p, 'y', 350).toDouble(),
        width: _intParam(p, 'width', 300).toDouble(),
        height: _intParam(p, 'height', 150).toDouble(),
      ),
    ),
  ),
  _PdfToPdf(
    _meta('rotate', 'Rotate PDF', Icons.rotate_right,
        'Rotate every page of a PDF.', _pdf,
        params: const [
          ToolParam(key: 'degrees', label: 'Rotation (degrees)', defaultValue: 90),
        ]),
    (e, b, p) {
      final d = _intParam(p, 'degrees', 90);
      if (d % 90 != 0) {
        throw const ToolException('Rotation must be a multiple of 90 degrees.');
      }
      return e.rotateAll(b, d);
    },
  ),
  _PdfPlusImage(
    _meta('sign', 'Sign PDF', Icons.draw,
        'Stamp a signature image onto a page of a PDF.',
        const ['pdf', 'png', 'jpg'],
        params: _stampParams, acceptsMultiple: true),
  ),
  _PdfToMany(
    _meta('split', 'Split PDF', Icons.call_split,
        'Split a PDF into smaller files by page count.', _pdf,
        params: const [
          ToolParam(key: 'every', label: 'Pages per file', defaultValue: 5),
        ]),
    (e, b, p) async => [
      for (final pdf in await e.split(b, _intParam(p, 'every', 5)))
        (bytes: pdf, ext: 'pdf', mime: _pdfMime),
    ],
  ),
  _PdfToTextFile(
    _meta('to-csv', 'PDF to CSV', Icons.grid_on,
        'Extract PDF text into CSV rows (splits columns on wide gaps).', _pdf,
        keywords: ['table', 'tables', 'spreadsheet', 'excel', 'rows']),
    toCsv: true,
  ),
  _toImages('jpg', 'jpg'),
  _toImages('png', 'png'),
  _PdfToTextFile(
    _meta('to-text', 'PDF to Text', Icons.notes,
        'Convert a PDF into a plain-text file.', _pdf),
  ),
  _toImages('tiff', 'tiff'),
  _PdfToPdf(
    _meta('unlock', 'Unlock PDF', Icons.lock_open,
        'Remove password protection from a PDF (requires the password).', _pdf,
        params: const [
          ToolParam(
              key: 'password',
              label: 'Current password',
              type: ToolParamType.text,
              defaultText: ''),
        ]),
    (e, b, p) => e.unlock(b, _requiredText(p, 'password', 'the password')),
  ),
  _PdfToPdf(
    _meta('watermark', 'Watermark PDF', Icons.branding_watermark,
        'Tile a text watermark across every page.', _pdf,
        params: const [
          ToolParam(
              key: 'text',
              label: 'Watermark text',
              type: ToolParamType.text,
              defaultText: 'CONFIDENTIAL'),
        ]),
    (e, b, p) => e.watermark(b, _textParam(p, 'text', 'CONFIDENTIAL')),
  ),
];
