import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tool/editors/preview_runner.dart';

/// Each run waits for its own completer, then writes `[quality]` as the
/// output so tests can tell which run's bytes landed.
class _GatedTool extends BaseToolModule {
  final runs = <Map<String, dynamic>>[];
  final gates = <Completer<void>>[];
  final Directory dir = Directory.systemTemp.createTempSync('preview_test');

  @override
  ToolMeta get meta => const ToolMeta(
    id: 'fake',
    category: ToolCategory.image,
    label: 'Fake',
    icon: Icons.abc,
    description: 'fake',
    tinywowSlug: 'fake',
    acceptedExtensions: ['png'],
  );

  @override
  EngineKind get engine => EngineKind.image;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    runs.add(input.params);
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    final q = input.params['quality'] as int;
    if (q < 0) throw const ToolException('boom');
    final f = File('${dir.path}/out_${runs.length}.jpg')
      ..writeAsBytesSync(List.filled(q, 7));
    yield ToolSucceeded(
      ToolResult(
        files: [OutputFile(path: f.path, name: 'in.jpg')],
      ),
    );
  }
}

const _file = InputFile(path: '/tmp/in.png', name: 'in.png');
const _delay = Duration(milliseconds: 20);

Future<void> _until(bool Function() cond) async {
  for (var i = 0; i < 200 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(cond(), isTrue);
}

void main() {
  test('debounces a burst into one run with the last params', () async {
    final tool = _GatedTool();
    final runner = PreviewRunner(tool, delay: _delay);
    addTearDown(runner.dispose);

    runner.request(_file, {'quality': 10});
    runner.request(_file, {'quality': 20});
    runner.request(_file, {'quality': 30});
    expect(runner.loading, isTrue);
    await _until(() => tool.runs.isNotEmpty);
    await Future<void>.delayed(_delay * 3);
    expect(tool.runs, [
      {'quality': 30},
    ]);

    tool.gates.single.complete();
    await _until(() => !runner.loading);
    expect(runner.byteLength, 30);
    expect(runner.outputName, 'in.jpg');
    expect(runner.failed, isFalse);
  });

  test(
    'a stale run finishing last never overwrites the newer result',
    () async {
      final tool = _GatedTool();
      final runner = PreviewRunner(tool, delay: _delay);
      addTearDown(runner.dispose);

      runner.request(_file, {'quality': 11});
      await _until(() => tool.runs.length == 1);
      runner.request(_file, {'quality': 22});
      await _until(() => tool.runs.length == 2);

      tool.gates[1].complete();
      await _until(() => runner.byteLength == 22);
      tool.gates[0].complete();
      await Future<void>.delayed(_delay * 3);
      expect(runner.byteLength, 22);
      expect(runner.loading, isFalse);
    },
  );

  test('a failed run sets failed but keeps the previous bytes', () async {
    final tool = _GatedTool();
    final runner = PreviewRunner(tool, delay: _delay);
    addTearDown(runner.dispose);

    runner.request(_file, {'quality': 5});
    await _until(() => tool.gates.length == 1);
    tool.gates[0].complete();
    await _until(() => runner.byteLength == 5);

    runner.request(_file, {'quality': -1});
    await _until(() => tool.gates.length == 2);
    tool.gates[1].complete();
    await _until(() => runner.failed);
    expect(runner.byteLength, 5);
    expect(runner.loading, isFalse);
  });

  test('cancel and dispose drop in-flight results', () async {
    final tool = _GatedTool();
    final runner = PreviewRunner(tool, delay: _delay);

    runner.request(_file, {'quality': 9});
    await _until(() => tool.gates.length == 1);
    runner.cancel();
    expect(runner.loading, isFalse);
    tool.gates[0].complete();
    await Future<void>.delayed(_delay * 3);
    expect(runner.bytes, isNull);

    runner.request(_file, {'quality': 8});
    runner.dispose();
    await Future<void>.delayed(_delay * 3);
    // The debounced run never started after dispose.
    expect(tool.runs, hasLength(1));
  });
}
