import 'package:anvil/core/di.dart';
import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHistoryRepo implements HistoryRepository {
  final List<HistoryRecord> added = [];
  @override
  Future<int> add(HistoryRecord r) async {
    added.add(r);
    return added.length;
  }

  @override
  Future<List<HistoryRecord>> all() async => added;

  @override
  Future<void> clear() async => added.clear();

  @override
  Future<List<HistoryRecord>> pruneOlderThan(DateTime cutoff) async {
    final removed = added
        .where((r) => r.createdAt.isBefore(cutoff))
        .toList();
    added.removeWhere((r) => r.createdAt.isBefore(cutoff));
    return removed;
  }
}

class _FakeTool extends BaseToolModule {
  _FakeTool({required this.stream});
  final Stream<ToolProgress> Function() stream;

  @override
  ToolMeta get meta => const ToolMeta(
    id: 'fake',
    category: ToolCategory.converter,
    label: 'Fake',
    icon: Icons.abc,
    description: 'fake',
    tinywowSlug: 'fake',
    acceptedExtensions: ['x'],
  );

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) => stream();
}

const _input = ToolInput(files: [InputFile(path: '/tmp/a.x', name: 'a.x')]);

Future<void> _settle(ProviderContainer c) async {
  for (var i = 0; i < 50; i++) {
    if (c.read(jobProvider) is! JobRunning) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  late _FakeHistoryRepo history;

  setUp(() async {
    history = _FakeHistoryRepo();
    await getIt.reset();
    getIt.registerSingleton<HistoryRepository>(history);
  });

  tearDown(() async => getIt.reset());

  test('success path: Running -> Success and records one history entry', () async {
    final tool = _FakeTool(
      stream: () async* {
        yield const ToolRunning(message: 'go');
        yield ToolSucceeded(
          ToolResult(files: [OutputFile(path: '/tmp/out.json', name: 'out.json')]),
        );
      },
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final seen = <JobState>[];
    container.listen(jobProvider, (_, n) => seen.add(n), fireImmediately: true);

    await container.read(jobProvider.notifier).start(tool, _input);
    await _settle(container);

    expect(container.read(jobProvider), isA<JobSuccess>());
    expect(seen.whereType<JobRunning>(), isNotEmpty);
    expect(history.added, hasLength(1));
    expect(history.added.single.toolId, 'converter/fake');
    expect(history.added.single.outputPaths, ['/tmp/out.json']);
  });

  test('failure path: thrown ToolException -> JobFailed with message', () async {
    final tool = _FakeTool(
      stream: () async* {
        yield const ToolRunning();
        throw const ToolException('bad');
      },
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.listen(jobProvider, (_, _) {}, fireImmediately: true);
    await container.read(jobProvider.notifier).start(tool, _input);
    await _settle(container);

    final state = container.read(jobProvider);
    expect(state, isA<JobFailed>());
    expect((state as JobFailed).message, 'bad');
    expect(history.added, isEmpty);
  });
}
