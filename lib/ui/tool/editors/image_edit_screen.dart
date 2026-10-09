/// Image picking + inline crop/rotate step shared by every editor that places
/// an image on a PDF page (the `pdf/add-images` stamp editor and the PDF
/// workspace sign sheet): choose Photos / Camera / Files, then trim and turn
/// the image before it is used.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/image_engine.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/rect_handles.dart';
import 'package:anvil/ui/tool/image_canvas.dart';
import 'package:anvil/ui/widgets/slab.dart';

enum _ImgSource { gallery, camera, files }

/// Asks for an image source (Photos / Camera / Files), reads the chosen image
/// and pushes [ImageEditScreen]. Returns the edited PNG bytes, or null when the
/// user cancels at any step. Throws [ToolException] when the image cannot be
/// read.
Future<Uint8List?> pickAndEditImage(
  BuildContext context,
  ImagePicker picker,
) async {
  final source = await showModalBottomSheet<_ImgSource>(
    context: context,
    builder: (ctx) {
      final c = Theme.of(ctx).extension<AnvilColors>()!;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library, color: c.iconStrong),
              title: const Text('Photos'),
              onTap: () => Navigator.pop(ctx, _ImgSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera, color: c.iconStrong),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, _ImgSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.folder_open, color: c.iconStrong),
              title: const Text('Files'),
              onTap: () => Navigator.pop(ctx, _ImgSource.files),
            ),
          ],
        ),
      );
    },
  );
  if (source == null) return null;
  Uint8List? bytes;
  try {
    if (source == _ImgSource.files) {
      final res = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg'],
      );
      final path = res?.path;
      if (path != null) {
        bytes = await getIt<FileService>().readBytes(path) as Uint8List;
      }
    } else {
      final x = await picker.pickImage(
        source: source == _ImgSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
      );
      if (x != null) bytes = await x.readAsBytes();
    }
  } catch (_) {
    throw const ToolException('Could not load the image.');
  }
  if (bytes == null || !context.mounted) return null;
  final picked = bytes;
  return Navigator.push<Uint8List>(
    context,
    MaterialPageRoute(builder: (_) => ImageEditScreen(bytes: picked)),
  );
}

/// Rotates PNG/JPEG bytes 90° clockwise, returning PNG bytes.
Future<Uint8List> _rotate90(Uint8List src) async {
  final codec = await ui.instantiateImageCodec(src);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.translate(image.height.toDouble(), 0);
  canvas.rotate(math.pi / 2);
  canvas.drawImage(image, Offset.zero, Paint());
  final picture = recorder.endRecording();
  final rotated = await picture.toImage(image.height, image.width);
  final data = await rotated.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  rotated.dispose();
  return data!.buffer.asUint8List();
}

/// Inline crop + rotate step shown after an image is chosen. Returns the edited
/// PNG bytes via [Navigator.pop], or null if the user backs out.
class ImageEditScreen extends StatefulWidget {
  const ImageEditScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<ImageEditScreen> createState() => _ImageEditState();
}

class _ImageEditState extends State<ImageEditScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  late Uint8List _bytes;
  Size _imagePx = Size.zero;
  Rect? _crop; // canvas coords
  Rect _displayRect = Rect.zero;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bytes = widget.bytes;
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(_bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final size = Size(img.width.toDouble(), img.height.toDouble());
    img.dispose();
    if (mounted) setState(() => _imagePx = size);
  }

  void _drag(RectGrip grip, Offset delta) {
    _crop = dragRect(_crop!, grip, delta, _displayRect);
  }

  Future<void> _rotate() async {
    setState(() => _busy = true);
    final out = await _rotate90(_bytes);
    setState(() {
      _bytes = out;
      _crop = null;
      _busy = false;
    });
    await _decode();
  }

  Future<void> _applyCrop() async {
    final crop = _crop;
    if (crop == null || _displayRect.width <= 0) return;
    final scale = _imagePx.width / _displayRect.width;
    final rel = crop.topLeft - _displayRect.topLeft;
    setState(() => _busy = true);
    try {
      final out = await getIt<ImageEngine>().crop(
        _bytes,
        x: (rel.dx * scale).round(),
        y: (rel.dy * scale).round(),
        width: (crop.width * scale).round(),
        height: (crop.height * scale).round(),
        format: 'png',
      );
      setState(() {
        _bytes = out;
        _crop = null;
        _busy = false;
      });
      await _decode();
    } on ToolException catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(AnvilRadii.control),
                    onTap: () => Navigator.pop(context),
                    child: IconChip(
                      icon: Icons.arrow_back,
                      bg: c.container,
                      fg: c.iconStrong,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Edit image',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: c.container,
                    borderRadius: BorderRadius.circular(AnvilRadii.panel),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _busy || _imagePx.width <= 0
                      ? const Center(child: CircularProgressIndicator())
                      : ImageCanvas(
                          imageBytes: _bytes,
                          imagePx: _imagePx,
                          builder: _overlay,
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Rotate 90°',
                      icon: Icons.rotate_90_degrees_cw,
                      onPressed: _busy ? null : _rotate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SecondaryButton(
                      label: 'Crop',
                      icon: Icons.crop,
                      onPressed: _busy ? null : _applyCrop,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: 'Use image',
                icon: Icons.check,
                onPressed: _busy ? null : () => Navigator.pop(context, _bytes),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overlay(BuildContext context, Rect displayRect, Size imagePx) {
    _displayRect = displayRect;
    _crop ??= Rect.fromCenter(
      center: displayRect.center,
      width: displayRect.width * 0.8,
      height: displayRect.height * 0.8,
    );
    final crop = _crop!;
    final c = Theme.of(context).extension<AnvilColors>()!;
    return SizedBox.expand(
      key: _canvasKey,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DimPainter(crop, Colors.black.withValues(alpha: 0.5)),
            ),
          ),
          Positioned.fromRect(
            rect: crop,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() => _drag(RectGrip.move, d.delta)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: c.accent, width: 2),
                ),
              ),
            ),
          ),
          _corner(crop.topLeft, RectGrip.tl, c),
          _corner(crop.topRight, RectGrip.tr, c),
          _corner(crop.bottomLeft, RectGrip.bl, c),
          _corner(crop.bottomRight, RectGrip.br, c),
        ],
      ),
    );
  }

  Widget _corner(Offset at, RectGrip grip, AnvilColors c) {
    return Positioned(
      left: at.dx - 14,
      top: at.dy - 14,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _drag(grip, d.delta)),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// Dims everything outside [hole].
class _DimPainter extends CustomPainter {
  _DimPainter(this.hole, this.color);
  final Rect hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(hole);
    final outside = Path.combine(PathOperation.difference, full, inner);
    canvas.drawPath(outside, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole || old.color != color;
}
