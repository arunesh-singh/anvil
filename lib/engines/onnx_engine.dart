/// Runs curated image-restoration ONNX models via `onnxruntime` — the single
/// place the plugin is touched.
///
/// Model I/O contract the curated manifest (MODEL_DELIVERY.md) must satisfy:
/// - "enhance" models (upscale/deblur/colorize/…): ONE float32 NCHW RGB input
///   in [0,1] with dynamic H/W; ONE float32 NCHW RGB output in [0,1]. Any
///   output scale (e.g. 4× for Real-ESRGAN) is accepted.
/// - "inpaint" models (LaMa family): TWO inputs — image as above plus a
///   single-channel float32 NCHW mask (1 = fill) at the same size; ONE image
///   output.
///
/// Tensor packing/unpacking lives in `lib/tools/image/image_ml_helpers.dart`
/// (pure, host-tested); this class only owns sessions and inference.
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:onnxruntime/onnxruntime.dart';

import 'package:anvil/core/tool_io.dart';

/// A decoded image as a float32 NCHW tensor plus its dimensions.
class ImageTensor {
  final Float32List data; // length = channels*height*width
  final int channels;
  final int height;
  final int width;
  const ImageTensor(this.data, this.channels, this.height, this.width);
}

class OnnxEngine {
  OnnxEngine() {
    OrtEnv.instance.init();
  }

  final Map<String, OrtSession> _sessions = {};

  OrtSession _session(String modelPath) => _sessions.putIfAbsent(
        modelPath,
        () => OrtSession.fromFile(
          // fromFile reads the bytes itself; sessions cache per model path.
          // ignore: avoid_redundant_argument_values
          File(modelPath),
          OrtSessionOptions(),
        ),
      );

  /// Runs a one-in/one-out enhance model. Returns the output tensor.
  Future<ImageTensor> enhance(String modelPath, ImageTensor input) =>
      _run(modelPath, [input]);

  /// Runs a two-input inpaint model (image + mask).
  Future<ImageTensor> inpaint(
          String modelPath, ImageTensor image, ImageTensor mask) =>
      _run(modelPath, [image, mask]);

  Future<ImageTensor> _run(String modelPath, List<ImageTensor> inputs) async {
    final session = _session(modelPath);
    final names = session.inputNames;
    if (names.length < inputs.length) {
      throw ToolException(
          'This model expects ${names.length} inputs but the tool provides '
          '${inputs.length} — the manifest entry does not match the engine '
          'contract.');
    }
    final ortInputs = <String, OrtValue>{};
    final created = <OrtValueTensor>[];
    try {
      for (var i = 0; i < inputs.length; i++) {
        final t = inputs[i];
        final tensor = OrtValueTensor.createTensorWithDataList(
            t.data, [1, t.channels, t.height, t.width]);
        created.add(tensor);
        ortInputs[names[i]] = tensor;
      }
      final runOptions = OrtRunOptions();
      final outputs = await session.runAsync(runOptions, ortInputs);
      runOptions.release();
      final out = outputs?.firstOrNull;
      if (out == null) {
        throw const ToolException('The model produced no output.');
      }
      try {
        final value = out.value;
        final shape = _shapeOf(value);
        final flat = _flatten(value);
        return ImageTensor(flat, shape.$1, shape.$2, shape.$3);
      } finally {
        for (final o in outputs!) {
          o?.release();
        }
      }
    } finally {
      for (final t in created) {
        t.release();
      }
    }
  }

  /// (channels, height, width) of a nested NCHW list output.
  (int, int, int) _shapeOf(Object? value) {
    // Output arrives as nested List: [1][C][H][W].
    final batch = value as List;
    final chan = batch[0] as List;
    final rows = chan[0] as List;
    final cols = rows[0] as List;
    return (chan.length, rows.length, cols.length);
  }

  Float32List _flatten(Object? value) {
    final batch = (value as List)[0] as List;
    final c = batch.length;
    final h = (batch[0] as List).length;
    final w = ((batch[0] as List)[0] as List).length;
    final out = Float32List(c * h * w);
    var o = 0;
    for (var ci = 0; ci < c; ci++) {
      final plane = batch[ci] as List;
      for (var y = 0; y < h; y++) {
        final row = plane[y] as List;
        for (var x = 0; x < w; x++) {
          out[o++] = (row[x] as num).toDouble();
        }
      }
    }
    return out;
  }

  void dispose() {
    for (final s in _sessions.values) {
      s.release();
    }
    _sessions.clear();
    OrtEnv.instance.release();
  }
}
