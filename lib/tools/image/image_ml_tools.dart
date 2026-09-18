/// ML-backed image tools (Phase 1.5): ML Kit subject segmentation / OCR /
/// translation plus curated ONNX restoration models delivered via
/// [ModelManager]. Pure mask/tensor logic lives in `image_ml_helpers.dart`.
/// The single registration list for this block lives in [buildImageMlTools].
library;

import 'dart:typed_data';

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:image/image.dart' as img;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/isolate_runner.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/mlkit_engine.dart';
import 'package:anvil/engines/onnx_engine.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/tools/image/image_ml_helpers.dart' as ml;

// ── Model task ids (curated manifest keys, MODEL_DELIVERY.md) ───────────────

const _upscaleModel = ModelSpec(taskId: 'image.upscale');
const _deblurModel = ModelSpec(taskId: 'image.deblur');
const _colorizeModel = ModelSpec(taskId: 'image.colorize');
const _inpaintModel = ModelSpec(taskId: 'image.inpaint');

// ── Helpers ──────────────────────────────────────────────────────────────────

int _intParam(Map<String, dynamic> p, String key, int fallback) =>
    switch (p[key]) { final int v => v, _ => fallback };

String _textParam(Map<String, dynamic> p, String key, String fallback) =>
    switch (p[key]) {
      final String v when v.trim().isNotEmpty => v.trim(),
      _ => fallback,
    };

String _outName(String input, String ext, [String suffix = '']) {
  final dot = input.lastIndexOf('.');
  final base = dot <= 0 ? input : input.substring(0, dot);
  return '$base$suffix.$ext';
}

Future<Uint8List> _readBytes(InputFile f) async =>
    await getIt<FileService>().readBytes(f.path) as Uint8List;

Future<img.Image> _decode(Uint8List bytes) => runOffThread(() {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const ToolException('Could not read the image.');
      }
      return decoded;
    });

/// Fetches the subject mask for a decoded image via ML Kit.
Future<List<double>> _subjectMask(InputFile f, img.Image decoded) async {
  final mask = await getIt<MlKitEngine>()
      .subjectMask(f.path, decoded.width, decoded.height);
  if (mask.confidence.length != decoded.width * decoded.height) {
    throw const ToolException(
        'Subject segmentation returned an unexpected mask size.');
  }
  return mask.confidence;
}

/// Runs one curated enhance-contract model over the whole image.
Future<img.Image> _runEnhance(ModelSpec spec, img.Image src) async {
  final model = await getIt<ModelManager>().ensureReady(spec);
  final input = await runOffThread(() => ml.imageToTensor(src));
  final output = await getIt<OnnxEngine>().enhance(model.filePath, input);
  return runOffThread(() => ml.tensorToImage(output));
}

/// Runs the inpaint-contract model with the given fill rectangles.
Future<img.Image> _runInpaint(
    img.Image src, List<(int, int, int, int)> rects) async {
  if (rects.isEmpty) {
    throw const ToolException('Nothing selected to remove.');
  }
  final model = await getIt<ModelManager>().ensureReady(_inpaintModel);
  final image = await runOffThread(() => ml.imageToTensor(src));
  final mask = ml.rectMask(src.width, src.height, rects);
  final output =
      await getIt<OnnxEngine>().inpaint(model.filePath, image, mask);
  return runOffThread(() => ml.tensorToImage(output));
}

// ── Generic tool shape ──────────────────────────────────────────────────────

/// One ML tool: single image (or none for OCR-only outputs) in, one file out.
class _MlTool extends BaseToolModule {
  _MlTool(this.meta, this._engine, this._model, this._body);
  @override
  final ToolMeta meta;
  final EngineKind _engine;
  final ModelSpec? _model;

  /// (input file, params) → (bytes, extension, mime, optional inline text).
  final Future<(Uint8List, String, String, String?)> Function(
      InputFile f, Map<String, dynamic> params) _body;

  @override
  EngineKind get engine => _engine;

  @override
  ModelSpec? get model => _model;

  @override
  Future<void> ensureReady() async {
    final spec = _model;
    if (spec != null) {
      await getIt<ModelManager>().ensureReady(spec);
    }
  }

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Processing…');
    final f = input.files.single;
    final (bytes, ext, mime, text) = await _body(f, input.params);
    yield const ToolRunning(fraction: 0.9, message: 'Saving…');
    final name = _outName(f.name, ext);
    final file = await getIt<FileService>().writeBytes(name, bytes);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: mime)],
      text: text,
    ));
  }
}

// ── Registration ─────────────────────────────────────────────────────────────

ToolMeta _meta(
  String id,
  String label,
  IconData icon,
  String description,
  List<String> accepts, {
  List<ToolParam> params = const [],
  List<String> keywords = const [],
}) => ToolMeta(
  id: id,
  category: ToolCategory.image,
  label: label,
  icon: icon,
  description: description,
  tinywowSlug: id,
  acceptedExtensions: accepts,
  params: params,
  keywords: keywords,
);

const _photos = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'];

const _rectParams = [
  ToolParam(key: 'x', label: 'Region left (px)'),
  ToolParam(key: 'y', label: 'Region top (px)'),
  ToolParam(key: 'width', label: 'Region width (px)', defaultValue: 200),
  ToolParam(key: 'height', label: 'Region height (px)', defaultValue: 200),
];

List<(int, int, int, int)> _rectFromParams(Map<String, dynamic> p) => [
      (
        _intParam(p, 'x', 0),
        _intParam(p, 'y', 0),
        _intParam(p, 'width', 200),
        _intParam(p, 'height', 200),
      ),
    ];

/// Segmentation tool over the shared cutout pipeline.
_MlTool _segTool(String id, String label, String description,
        {List<ToolParam> params = const [],
        required Future<img.Image> Function(
                img.Image decoded, List<double> mask, Map<String, dynamic> p)
            compose}) =>
    _MlTool(
      _meta(id, label, Icons.auto_fix_high, description, _photos,
          params: params),
      EngineKind.mlkit,
      null,
      (f, p) async {
        final decoded = await _decode(await _readBytes(f));
        final mask = await _subjectMask(f, decoded);
        final composed = await compose(decoded, mask, p);
        final png = await runOffThread(() => img.encodePng(composed));
        return (png, 'png', 'image/png', null);
      },
    );

/// Enhance-model tool (upscale/deblur/sharpen/colorize).
_MlTool _enhanceTool(String id, String label, String description,
        ModelSpec spec,
        {List<String> accepts = _photos, List<String> keywords = const []}) =>
    _MlTool(
      _meta(id, label, Icons.auto_awesome, description, accepts,
          keywords: keywords),
      EngineKind.onnx,
      spec,
      (f, p) async {
        final decoded = await _decode(await _readBytes(f));
        final out = await _runEnhance(spec, decoded);
        final png = await runOffThread(() => img.encodePng(out));
        return (png, 'png', 'image/png', null);
      },
    );

/// Rect-mask inpaint tool (remove-objects/watermark/cleanup/repair).
_MlTool _inpaintTool(String id, String label, IconData icon,
        String description) =>
    _MlTool(
      _meta(id, label, icon, description, _photos, params: _rectParams),
      EngineKind.onnx,
      _inpaintModel,
      (f, p) async {
        final decoded = await _decode(await _readBytes(f));
        final out = await _runInpaint(decoded, _rectFromParams(p));
        final png = await runOffThread(() => img.encodePng(out));
        return (png, 'png', 'image/png', null);
      },
    );

/// Every ML image tool. The single registration list for this block.
List<ToolModule> buildImageMlTools() => [
  _segTool(
    'blur-background', 'Blur Background',
    'Keep the subject sharp and blur everything behind it.',
    params: const [
      ToolParam(key: 'blurRadius', label: 'Blur strength', defaultValue: 12),
    ],
    compose: (decoded, mask, p) => runOffThread(() => ml.applyMask(
        decoded, mask,
        background: ml.MaskBackground.blur,
        blurRadius: _intParam(p, 'blurRadius', 12))),
  ),
  _segTool(
    'change-bg-photo', 'Change Background',
    'Replace the photo background with a solid color.',
    params: const [
      ToolParam(
          key: 'color',
          label: 'Background color (hex)',
          type: ToolParamType.text,
          defaultText: '#FFFFFFFF'),
    ],
    compose: (decoded, mask, p) => runOffThread(() => ml.applyMask(
        decoded, mask,
        background: ml.MaskBackground.color,
        color: ml.parseColor(_textParam(p, 'color', '#FFFFFFFF')))),
  ),
  _inpaintTool('cleanup-picture', 'Cleanup Picture', Icons.cleaning_services,
      'Remove a blemish or distraction from a chosen region.'),
  _enhanceTool('colorize-photo', 'Colorize Photo',
      'Colorize a black-and-white photo with an on-device model.',
      _colorizeModel),
  _MlTool(
    _meta('identify', 'Identify Photo', Icons.category,
        'Recognize what a photo shows — objects, scene, or food — and name it.',
        const ['jpg', 'jpeg', 'png', 'webp']),
    EngineKind.mlkit,
    null,
    (f, p) async {
      final tags = await getIt<MlKitEngine>().labelImage(f.path);
      if (tags.isEmpty) {
        throw const ToolException(
            "Couldn't recognize anything in this photo.");
      }
      final text = tags.map((t) => t.label).join(', ');
      return (Uint8List.fromList(text.codeUnits), 'txt', 'text/plain', text);
    },
  ),
  _segTool(
    'make-background-transparent', 'Transparent Background',
    'Cut out the subject onto a transparent background.',
    compose: (decoded, mask, p) => runOffThread(() => ml.applyMask(
        decoded, mask,
        background: ml.MaskBackground.transparent)),
  ),
  _segTool(
    'profile-photo', 'Profile Photo Maker',
    'Cut out the subject and place it on a round colored disc.',
    params: const [
      ToolParam(
          key: 'color',
          label: 'Disc color (hex)',
          type: ToolParamType.text,
          defaultText: '#FFE5E7EB'),
    ],
    compose: (decoded, mask, p) => runOffThread(() => ml.profilePhoto(
        decoded, mask,
        background: ml.parseColor(_textParam(p, 'color', '#FFE5E7EB')))),
  ),
  _segTool(
    'remove-bg', 'Remove Background',
    'Erase the photo background, keeping only the subject.',
    compose: (decoded, mask, p) => runOffThread(() => ml.applyMask(
        decoded, mask,
        background: ml.MaskBackground.transparent)),
  ),
  _inpaintTool('remove-objects', 'Remove Objects', Icons.auto_fix_normal,
      'Erase an object inside a chosen region and fill the gap.'),
  _MlTool(
    _meta('remove-person', 'Remove Person', Icons.person_remove,
        'Detect the main person and erase them from the photo.', _photos),
    EngineKind.onnx,
    _inpaintModel,
    (f, p) async {
      final decoded = await _decode(await _readBytes(f));
      final mask = await _subjectMask(f, decoded);
      // Subject confidence -> fill mask for the inpainter.
      final model = await getIt<ModelManager>().ensureReady(_inpaintModel);
      final image = await runOffThread(() => ml.imageToTensor(decoded));
      final fill = Float32List(decoded.width * decoded.height);
      for (var i = 0; i < fill.length; i++) {
        fill[i] = mask[i] >= 0.5 ? 1.0 : 0.0;
      }
      final out = await getIt<OnnxEngine>().inpaint(model.filePath, image,
          ImageTensor(fill, 1, decoded.height, decoded.width));
      final png = await runOffThread(() => img.encodePng(ml.tensorToImage(out)));
      return (png, 'png', 'image/png', null);
    },
  ),
  _MlTool(
    _meta('remove-text-photo', 'Remove Text from Photo', Icons.font_download_off,
        'Find text in the photo (OCR) and erase it.', _photos),
    EngineKind.onnx,
    _inpaintModel,
    (f, p) async {
      final decoded = await _decode(await _readBytes(f));
      final ocr = await getIt<MlKitEngine>().recognizeText(f.path);
      if (ocr.blocks.isEmpty) {
        throw const ToolException('No text found in this photo.');
      }
      final out = await _runInpaint(decoded, [
        for (final b in ocr.blocks) (b.left, b.top, b.width, b.height),
      ]);
      final png = await runOffThread(() => img.encodePng(out));
      return (png, 'png', 'image/png', null);
    },
  ),
  _inpaintTool('remove-watermark-photo', 'Remove Watermark', Icons.layers_clear,
      'Erase a watermark inside a chosen region and fill the gap.'),
  _inpaintTool('repair-defects', 'Repair Old Photo', Icons.healing,
      'Fill scratches or damage inside a chosen region.'),
  _enhanceTool('sharpen', 'Sharpen Image',
      'Sharpen a soft photo with an on-device restoration model.',
      _deblurModel),
  _MlTool(
    _meta('tiff-to-text', 'TIFF to Text', Icons.text_snippet,
        'Read the text out of a TIFF scan (OCR).', const ['tiff', 'tif']),
    EngineKind.mlkit,
    null,
    (f, p) async {
      // ML Kit cannot read TIFF; normalize to PNG on disk first.
      final decoded = await _decode(await _readBytes(f));
      final png = await runOffThread(() => img.encodePng(decoded));
      final tmp = await getIt<FileService>().writeBytes('ocr.png', png);
      final ocr = await getIt<MlKitEngine>().recognizeText(tmp.path);
      if (ocr.text.trim().isEmpty) {
        throw const ToolException('No text found in this image.');
      }
      return (
        Uint8List.fromList(ocr.text.codeUnits),
        'txt',
        'text/plain',
        ocr.text,
      );
    },
  ),
  _MlTool(
    _meta('to-text', 'Image to Text', Icons.image_search,
        'Read the text out of a photo or screenshot (OCR).',
        ['jpg', 'jpeg', 'png', 'webp']),
    EngineKind.mlkit,
    null,
    (f, p) async {
      final ocr = await getIt<MlKitEngine>().recognizeText(f.path);
      if (ocr.text.trim().isEmpty) {
        throw const ToolException('No text found in this image.');
      }
      return (
        Uint8List.fromList(ocr.text.codeUnits),
        'txt',
        'text/plain',
        ocr.text,
      );
    },
  ),
  _MlTool(
    _meta('translate', 'Translate Image Text', Icons.translate,
        'Read the text in a photo and translate it on-device.',
        ['jpg', 'jpeg', 'png', 'webp'],
        params: const [
          ToolParam(
              key: 'from',
              label: 'From language (code, e.g. es)',
              type: ToolParamType.text,
              defaultText: ''),
          ToolParam(
              key: 'to',
              label: 'To language (code)',
              type: ToolParamType.text,
              defaultText: 'en'),
        ]),
    EngineKind.mlkit,
    null,
    (f, p) async {
      final from = _textParam(p, 'from', '');
      if (from.isEmpty) {
        throw const ToolException(
            "Enter the source language code (e.g. 'es' for Spanish).");
      }
      final mlkit = getIt<MlKitEngine>();
      final ocr = await mlkit.recognizeText(f.path);
      if (ocr.text.trim().isEmpty) {
        throw const ToolException('No text found in this image.');
      }
      final translated = await mlkit.translate(ocr.text,
          from: from, to: _textParam(p, 'to', 'en'));
      return (
        Uint8List.fromList(translated.codeUnits),
        'txt',
        'text/plain',
        translated,
      );
    },
  ),
  _enhanceTool('unblur', 'Unblur Image',
      'Deblur a shaky or out-of-focus photo with an on-device model.',
      _deblurModel),
  _enhanceTool('upscale', 'Upscale Image',
      'Upscale a photo 4× with an on-device super-resolution model.',
      _upscaleModel,
      keywords: ['bigger', 'enlarge', 'sharper', 'resolution', 'hd']),
];
