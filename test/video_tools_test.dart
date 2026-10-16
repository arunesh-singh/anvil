import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/agent/arg_validator.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/ffmpeg_engine.dart';
import 'package:anvil/tools/video/video_tools.dart';

/// Records the args each run receives and writes a non-empty output file so
/// the tool body completes; probes return a fixed 100 s clip with audio.
class _FakeFfmpeg implements FfmpegEngine {
  final runs = <List<String>>[];

  @override
  Future<void> run(
    List<String> args, {
    void Function(int outputTimeMs)? onProgress,
    FfmpegHandle? handle,
  }) async {
    runs.add(args);
    await File(args.last).writeAsString('x');
  }

  @override
  Future<VideoProbe> probe(String path) async => const VideoProbe(
    durationMs: 100000,
    width: 1920,
    height: 1080,
    sizeBytes: 1,
    hasAudio: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFileService implements FileService {
  _FakeFileService(this.dir);
  final Directory dir;

  @override
  Future<File> reserveFile(String fileName) async =>
      File(p.join(dir.path, fileName));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeFfmpeg ffmpeg;
  late Directory tmp;
  final tools = {for (final t in buildVideoTools()) t.meta.qualifiedId: t};

  setUp(() async {
    await getIt.reset();
    tmp = await Directory.systemTemp.createTemp('video_tools_test');
    ffmpeg = _FakeFfmpeg();
    getIt
      ..registerSingleton<FfmpegEngine>(ffmpeg)
      ..registerSingleton<FileService>(_FakeFileService(tmp));
  });

  tearDown(() async {
    await getIt.reset();
    await tmp.delete(recursive: true);
  });

  Future<List<String>> argsFor(String id, Map<String, dynamic> params) async {
    final input = ToolInput(
      files: [InputFile(path: '/v/in.mp4', name: 'in.mp4')],
      params: params,
    );
    final events = await tools[id]!.run(input).toList();
    expect(events.last, isA<ToolSucceeded>());
    return ffmpeg.runs.single;
  }

  test('cutter: UI fractional seconds and mute reach ffmpeg', () async {
    final args = await argsFor('video/cutter', {
      'start': 38.2,
      'duration': 41.5,
      'mute': 'yes',
    });
    expect(args, containsAllInOrder(['-ss', '38.200', '-i', '/v/in.mp4']));
    expect(args, containsAllInOrder(['-t', '41.500', '-c', 'copy', '-an']));
  });

  test('cutter: an agent call without params keeps today\'s args', () async {
    final args = await argsFor('video/cutter', {});
    expect(args.sublist(0, 7), [
      '-y',
      '-ss',
      '0',
      '-i',
      '/v/in.mp4',
      '-t',
      '10',
    ]);
    expect(args, isNot(contains('-an')));
  });

  test('compress: targetMb probes and encodes to a bitrate', () async {
    final args = await argsFor('video/compress', {'targetMb': 25});
    // 25 MiB over 100 s at 95% minus 128 kb/s audio.
    expect(args, containsAllInOrder(['-b:v', '${1992294 - 128000}']));
    expect(args, isNot(contains('-q:v')));
  });

  test('compress: height 0 keeps the source size; default is 720p', () async {
    final keep = await argsFor('video/compress', {'height': 0});
    expect(keep, contains('scale=trunc(iw/2)*2:trunc(ih/2)*2'));
    ffmpeg.runs.clear();
    final def = await argsFor('video/compress', {});
    expect(
      def,
      containsAllInOrder(['scale=-2:720', '-c:v', 'mpeg4', '-q:v', '6']),
    );
  });

  test('every GIF/WebP tool honours start and duration', () async {
    for (final id in [
      'video/to-gif',
      'video/mp4-to-gif',
      'video/mov-to-gif',
      'video/mkv-to-gif',
      'video/avi-to-gif',
      'video/to-webp',
    ]) {
      ffmpeg.runs.clear();
      final args = await argsFor(id, {'start': 72.0, 'duration': 4.0});
      expect(args.sublist(0, 6), [
        '-y',
        '-ss',
        '72',
        '-t',
        '4',
        '-i',
      ], reason: id);
    }
  });

  test('declared params: defaults keep omitted calls unchanged', () {
    ToolParam param(String id, String key) =>
        tools[id]!.meta.params.firstWhere((p) => p.key == key);
    final mute = param('video/cutter', 'mute');
    expect(mute.type, ToolParamType.choice);
    expect(mute.choices, ['no', 'yes']);
    expect(mute.defaultText, 'no');
    expect(param('video/compress', 'targetMb').defaultValue, 0);
    expect(param('video/compress', 'height').defaultValue, 720);
    expect(param('video/to-webp', 'start').defaultValue, 0);
    expect(param('video/avi-to-gif', 'duration').defaultValue, 0);
  });

  test('the agent can pass mute and targetMb', () {
    final cut = validateCall(tools['video/cutter']!, {
      'file': '/v/a.mp4',
      'start': 5,
      'mute': 'Yes',
    }, fileExists: (_) => true);
    expect(cut.input.params['mute'], 'yes');
    final compress = validateCall(tools['video/compress']!, {
      'file': '/v/a.mp4',
      'targetMb': 25,
      'height': 0,
    }, fileExists: (_) => true);
    expect(compress.input.params, {'targetMb': 25, 'height': 0});
  });
}
