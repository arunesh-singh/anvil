/// Wraps the on-device ML Kit plugins (subject segmentation, text
/// recognition, translation) — the single place they are touched, so a future
/// engine swap is one file. ML Kit manages its own model downloads via Play
/// services; ONNX/ASR models go through [ModelManager] instead.
///
/// Device-only: the plugins need Android. Tools depend on this class through
/// getIt, so tests re-register a fake.
library;

import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
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
      final result =
          await segmenter.processImage(InputImage.fromFilePath(path));
      final mask = result.foregroundConfidenceMask;
      if (mask == null || mask.isEmpty) {
        throw const ToolException('No subject found in this photo.');
      }
      return SubjectMask(
          width: width, height: height, confidence: List<double>.from(mask));
    } on ToolException {
      rethrow;
    } catch (e) {
      throw ToolException('Subject segmentation failed: $e');
    } finally {
      await segmenter.close();
    }
  }

  /// Recognizes text (Latin script) in the image at [path].
  Future<OcrResult> recognizeText(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(path));
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

  /// Translates [text] from [from] to [to] (BCP-47 codes ML Kit knows),
  /// downloading the language models on first use.
  Future<String> translate(String text,
      {required String from, required String to}) async {
    final source = TranslateLanguage.values
        .where((l) => l.bcpCode == from.toLowerCase())
        .firstOrNull;
    final target = TranslateLanguage.values
        .where((l) => l.bcpCode == to.toLowerCase())
        .firstOrNull;
    if (source == null || target == null) {
      throw ToolException(
          "Unsupported language pair '$from' → '$to' for on-device "
          'translation.');
    }
    final manager = OnDeviceTranslatorModelManager();
    final translator =
        OnDeviceTranslator(sourceLanguage: source, targetLanguage: target);
    try {
      if (!await manager.isModelDownloaded(source.bcpCode)) {
        await manager.downloadModel(source.bcpCode);
      }
      if (!await manager.isModelDownloaded(target.bcpCode)) {
        await manager.downloadModel(target.bcpCode);
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
  Future<List<ImageTag>> labelImage(String path,
      {double minConfidence = 0.6}) async {
    final labeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: minConfidence),
    );
    try {
      final labels =
          await labeler.processImage(InputImage.fromFilePath(path));
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
