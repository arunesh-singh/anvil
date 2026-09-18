/// On-device speech-to-text via `sherpa_onnx` (offline Whisper-family
/// models delivered through [ModelManager]) — the single place the plugin is
/// touched.
///
/// Model contract for the curated manifest: an `asr.transcribe` variant is a
/// tar/zip-free single directory download? No — v1 keeps it simple: the
/// variant URL points at a Whisper ONNX **encoder** file named
/// `<stem>-encoder.onnx`, and the sibling files `<stem>-decoder.onnx` and
/// `<stem>-tokens.txt` must ship in the same directory (multi-file variants
/// list the encoder; the manifest curator uploads all three next to each
/// other and the downloader fetches siblings by URL convention).
///
/// Long audio is decoded in fixed windows so each cue maps to a time range for
/// SRT output; pure SRT/summary helpers live in `lib/tools/video/srt.dart`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:anvil/core/tool_io.dart';

/// One transcribed window.
class AsrSegment {
  final int startMs;
  final int endMs;
  final String text;
  const AsrSegment(
      {required this.startMs, required this.endMs, required this.text});
}

class AsrEngine {
  bool _initialized = false;

  void _ensureBindings() {
    if (_initialized) return;
    sherpa.initBindings();
    _initialized = true;
  }

  /// Transcribes a 16 kHz mono PCM16 WAV file in [windowSeconds] chunks.
  /// [encoderPath] follows the manifest contract documented above.
  Future<List<AsrSegment>> transcribeWav(
    String wavPath, {
    required String encoderPath,
    int windowSeconds = 15,
    void Function(double fraction)? onProgress,
  }) async {
    _ensureBindings();
    final stem = encoderPath.replaceAll(RegExp(r'-encoder\.onnx$'), '');
    final decoderPath = '$stem-decoder.onnx';
    final tokensPath = '$stem-tokens.txt';
    for (final path in [encoderPath, decoderPath, tokensPath]) {
      if (!File(path).existsSync()) {
        throw ToolException(
            'Speech model file missing: ${path.split('/').last}. '
            'Re-download the model from Settings.');
      }
    }

    final recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: encoderPath,
          decoder: decoderPath,
        ),
        tokens: tokensPath,
        modelType: 'whisper',
      ),
    ));
    try {
      final wave = sherpa.readWave(wavPath);
      final samples = wave.samples;
      final rate = wave.sampleRate;
      final window = windowSeconds * rate;
      final segments = <AsrSegment>[];
      for (var off = 0; off < samples.length; off += window) {
        final end =
            off + window < samples.length ? off + window : samples.length;
        final chunk = Float32List.sublistView(samples, off, end);
        final stream = recognizer.createStream();
        stream.acceptWaveform(samples: chunk, sampleRate: rate);
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        stream.free();
        if (text.isNotEmpty) {
          segments.add(AsrSegment(
            startMs: off * 1000 ~/ rate,
            endMs: end * 1000 ~/ rate,
            text: text,
          ));
        }
        onProgress?.call(end / samples.length);
      }
      if (segments.isEmpty) {
        throw const ToolException('No speech found in this audio.');
      }
      return segments;
    } finally {
      recognizer.free();
    }
  }
}
