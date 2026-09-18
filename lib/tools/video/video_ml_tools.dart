/// ML-backed video/audio tools (Phase 1.5): sherpa_onnx ASR (models via
/// [ModelManager]) and frame OCR. Audio prep and frame sampling run through
/// the FFmpeg engine; pure SRT/summary text logic lives in `srt.dart`.
/// The single registration list for this block lives in [buildVideoMlTools].
library;

import 'dart:io';

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:path/path.dart' as p;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/asr_engine.dart';
import 'package:anvil/engines/ffmpeg_engine.dart';
import 'package:anvil/engines/mlkit_engine.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/tools/video/ffmpeg_cmd.dart' as cmd;
import 'package:anvil/tools/video/srt.dart';

const _asrModel = ModelSpec(taskId: 'asr.transcribe');

const _mediaExts = ['mp4', 'mov', 'mkv', 'avi', 'webm', 'mp3', 'wav', 'm4a',
  'aac', 'ogg', 'flac'];

String _outName(String input, String ext) {
  final dot = input.lastIndexOf('.');
  final base = dot <= 0 ? input : input.substring(0, dot);
  return '$base.$ext';
}

/// Converts any input to a temp 16 kHz mono WAV and transcribes it.
Future<List<AsrSegment>> _transcribe(InputFile f) async {
  final model = await getIt<ModelManager>().ensureReady(_asrModel);
  final wav = await getIt<FileService>().reserveFile('asr.wav');
  await getIt<FfmpegEngine>().run(cmd.toWav16k(f.path, wav.path));
  try {
    return await getIt<AsrEngine>()
        .transcribeWav(wav.path, encoderPath: model.filePath);
  } finally {
    if (await wav.exists()) await wav.delete();
  }
}

/// One ASR/OCR tool: media file in, text-family file out.
class _TextOutTool extends BaseToolModule {
  _TextOutTool(this.meta, this._engine, this._model, this._ext, this._body);
  @override
  final ToolMeta meta;
  final EngineKind _engine;
  final ModelSpec? _model;
  final String _ext;

  /// (input file) → output text (also shown inline).
  final Future<String> Function(InputFile f) _body;

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
    final f = input.files.single;
    yield const ToolRunning(message: 'Processing…');
    final text = await _body(f);
    yield const ToolRunning(fraction: 0.9, message: 'Saving…');
    final name = _outName(f.name, _ext);
    final file = await getIt<FileService>().writeString(name, text);
    yield ToolSucceeded(ToolResult(
      files: [
        OutputFile(
            path: file.path,
            name: name,
            mimeType: _ext == 'srt' ? 'application/x-subrip' : 'text/plain'),
      ],
      text: _ext == 'srt' ? null : text,
    ));
  }
}

ToolMeta _meta(
  String id,
  String label,
  IconData icon,
  String description,
  List<String> accepts,
) => ToolMeta(
  id: id,
  category: ToolCategory.video,
  label: label,
  icon: icon,
  description: description,
  tinywowSlug: id,
  acceptedExtensions: accepts,
);

String _stamp(int ms) {
  final m = ms ~/ 60000;
  final s = (ms ~/ 1000) % 60;
  return '[$m:${s.toString().padLeft(2, '0')}]';
}

/// Every ML video/audio tool. The single registration list for this block.
List<ToolModule> buildVideoMlTools() => [
  _TextOutTool(
    _meta('add-subtitles', 'Add Subtitles', Icons.subtitles,
        'Transcribe speech on-device and produce an .srt subtitle file.',
        _mediaExts),
    EngineKind.asr,
    _asrModel,
    'srt',
    (f) async => srtFrom(await _transcribe(f)),
  ),
  _TextOutTool(
    _meta('audio-to-text', 'Audio to Text', Icons.mic,
        'Transcribe speech to plain text on-device.', _mediaExts),
    EngineKind.asr,
    _asrModel,
    'txt',
    (f) async =>
        (await _transcribe(f)).map((s) => s.text).join(' ').trim(),
  ),
  _TextOutTool(
    _meta('summarize-podcast', 'Summarize Podcast', Icons.summarize,
        'Transcribe on-device, then produce a short extractive summary.',
        _mediaExts),
    EngineKind.asr,
    _asrModel,
    'txt',
    (f) async {
      final transcript =
          (await _transcribe(f)).map((s) => s.text).join(' ').trim();
      return extractiveSummary(transcript);
    },
  ),
  _TextOutTool(
    _meta('to-text', 'Video to Text', Icons.video_library,
        'Read on-screen text out of a video (frame OCR).',
        const ['mp4', 'mov', 'mkv', 'avi', 'webm']),
    EngineKind.mlkit,
    null,
    'txt',
    (f) async {
      final framesDir = Directory(p.join(
          (await getIt<FileService>().outputsDir()).path,
          'frames_${DateTime.now().millisecondsSinceEpoch}'));
      await framesDir.create(recursive: true);
      try {
        await getIt<FfmpegEngine>().run(
            cmd.extractFrames(f.path, p.join(framesDir.path, '%04d.png')));
        final frames = (await framesDir.list().toList())
            .whereType<File>()
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        if (frames.isEmpty) {
          throw const ToolException('Could not read frames from this video.');
        }
        final mlkit = getIt<MlKitEngine>();
        final texts = <String>[];
        for (final frame in frames) {
          texts.add((await mlkit.recognizeText(frame.path)).text);
        }
        return dedupeFrameTexts(texts);
      } finally {
        if (await framesDir.exists()) {
          await framesDir.delete(recursive: true);
        }
      }
    },
  ),
  _TextOutTool(
    _meta('transcribe-podcast', 'Transcribe Podcast', Icons.podcasts,
        'Transcribe speech on-device with timestamps.', _mediaExts),
    EngineKind.asr,
    _asrModel,
    'txt',
    (f) async => [
      for (final s in await _transcribe(f)) '${_stamp(s.startMs)} ${s.text}',
    ].join('\n'),
  ),
];
