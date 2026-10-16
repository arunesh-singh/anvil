/// Wraps the on-device ML Kit plugins (subject segmentation, text
/// recognition, language identification, translation) — the single place they
/// are touched, so a future engine swap is one file. ML Kit manages its own
/// model downloads via Play services; ONNX/ASR models go through
/// [ModelManager] instead.
///
/// Device-only: the plugins need Android. Tools depend on this class through
/// getIt, so tests re-register a fake.
library;

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'package:anvil/core/tool_io.dart';

/// Subject mask for an image: confidence per pixel, row-major [width]×[height].
class SubjectMask {
  final int width;
  final int height;
  final List<double> confidence;
  const SubjectMask({
    required this.width,
    required this.height,
    required this.confidence,
  });
}

/// One recognized text block with its bounding box (pixel coordinates).
class OcrBlock {
  final String text;
  final int left;
  final int top;
  final int width;
  final int height;
  const OcrBlock({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

class OcrResult {
  final String text;
  final List<OcrBlock> blocks;
  const OcrResult({required this.text, required this.blocks});
}

/// One recognized label for an image with the model's confidence (0..1).
class ImageTag {
  final String label;
  final double confidence;
  const ImageTag({required this.label, required this.confidence});
}

/// The photo has no detectable subject — a normal outcome the Background
/// screen handles (the user can paint one in), unlike a segmentation failure.
class NoSubjectException extends ToolException {
  const NoSubjectException() : super('No subject found in this photo.');
}

class MlKitEngine {
  /// Segments the main subject of the image at [path]; the mask is sized to
  /// the decoded input image.
  Future<SubjectMask> subjectMask(String path, int width, int height) async {
    final segmenter = SubjectSegmenter(
      options: SubjectSegmenterOptions(
        enableForegroundBitmap: false,
        enableForegroundConfidenceMask: true,
        enableMultipleSubjects: SubjectResultOptions(
          enableConfidenceMask: false,
          enableSubjectBitmap: false,
        ),
      ),
    );
    try {
      final result = await _waitingForModule(
        () => segmenter.processImage(InputImage.fromFilePath(path)),
      );
      final mask = result.foregroundConfidenceMask;
      if (mask == null || mask.isEmpty) {
        throw const NoSubjectException();
      }
      return SubjectMask(
        width: width,
        height: height,
        confidence: List<double>.from(mask),
      );
    } on ToolException {
      rethrow;
    } catch (e) {
      throw ToolException('Subject segmentation failed: $e');
    } finally {
      await segmenter.close();
    }
  }

  /// ML Kit installs some models (subject segmentation) as Play-services
  /// optional modules on first use and fails fast with "Waiting for … to be
  /// downloaded" until the module lands; retry for a while instead of
  /// failing the first run on every phone.
  static Future<T> _waitingForModule<T>(Future<T> Function() body) async {
    const step = Duration(seconds: 2);
    for (var waited = Duration.zero; ; waited += step) {
      try {
        return await body();
      } catch (e) {
        final downloading = '$e'.contains('to be downloaded');
        if (!downloading || waited >= const Duration(seconds: 90)) rethrow;
      }
      await Future<void>.delayed(step);
    }
  }

  /// Recognizes text (Latin script) in the image at [path].
  Future<OcrResult> recognizeText(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      return OcrResult(
        text: result.text,
        blocks: [
          for (final block in result.blocks)
            OcrBlock(
              text: block.text,
              left: block.boundingBox.left.round(),
              top: block.boundingBox.top.round(),
              width: block.boundingBox.width.round(),
              height: block.boundingBox.height.round(),
            ),
        ],
      );
    } catch (e) {
      throw ToolException('Text recognition failed: $e');
    } finally {
      await recognizer.close();
    }
  }

  /// Identifies the main language of [text] on-device. Returns its BCP-47
  /// code (e.g. `es`, `hi-Latn`), or null when ML Kit cannot tell ('und').
  Future<String?> identifyLanguage(String text) async {
    final identifier = LanguageIdentifier(confidenceThreshold: 0.5);
    try {
      final code = await identifier.identifyLanguage(text);
      return code == identifier.undeterminedLanguageCode ? null : code;
    } catch (e) {
      throw ToolException('Language detection failed: $e');
    } finally {
      await identifier.close();
    }
  }

  /// Whether both translation models for [from] → [to] are already on the
  /// device (false means [translate] will download first). Unknown codes
  /// report false.
  Future<bool> translationModelsReady(String from, String to) async {
    final manager = OnDeviceTranslatorModelManager();
    for (final code in [from, to]) {
      final lang = TranslateLanguage.values
          .where((l) => l.bcpCode == code.toLowerCase())
          .firstOrNull;
      if (lang == null) return false;
      if (!await manager.isModelDownloaded(lang.bcpCode)) return false;
    }
    return true;
  }

  /// Translates [text] from [from] to [to] (BCP-47 codes ML Kit knows),
  /// downloading the language models on first use.
  Future<String> translate(
    String text, {
    required String from,
    required String to,
  }) async {
    final source = TranslateLanguage.values
        .where((l) => l.bcpCode == from.toLowerCase())
        .firstOrNull;
    final target = TranslateLanguage.values
        .where((l) => l.bcpCode == to.toLowerCase())
        .firstOrNull;
    if (source == null || target == null) {
      throw ToolException(
        "Unsupported language pair '$from' → '$to' for on-device "
        'translation.',
      );
    }
    final manager = OnDeviceTranslatorModelManager();
    final translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: target,
    );
    try {
      // The plugin defaults to Wi-Fi-only, which on mobile data waits
      // forever; the user asked for this translation now. ~30 MB per language.
      if (!await manager.isModelDownloaded(source.bcpCode)) {
        await manager.downloadModel(source.bcpCode, isWifiRequired: false);
      }
      if (!await manager.isModelDownloaded(target.bcpCode)) {
        await manager.downloadModel(target.bcpCode, isWifiRequired: false);
      }
      return await translator.translateText(text);
    } catch (e) {
      throw ToolException('Translation failed: $e');
    } finally {
      await translator.close();
    }
  }

  /// Recognizes what an image at [path] depicts (objects, scene, food) with
  /// the bundled on-device labeler. Returns tags scoring at least
  /// [minConfidence] (0..1), highest first; empty when nothing clears the bar.
  Future<List<ImageTag>> labelImage(
    String path, {
    double minConfidence = 0.6,
  }) async {
    final labeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: minConfidence),
    );
    try {
      final labels = await labeler.processImage(InputImage.fromFilePath(path));
      return [
        for (final l in labels)
          ImageTag(label: l.label, confidence: l.confidence),
      ]..sort((a, b) => b.confidence.compareTo(a.confidence));
    } catch (e) {
      throw ToolException('Image recognition failed: $e');
    } finally {
      await labeler.close();
    }
  }
}
