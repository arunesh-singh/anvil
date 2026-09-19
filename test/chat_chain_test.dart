/// The core proof for controller-driven multi-tool chains: each validated step
/// runs its tool immediately (with live progress), persists a `toolStep` with a
/// reopenable output path, and re-shortlists + rebuilds a fresh chat for the
/// next step — so a chain can call *different* tools. Also proves the
/// [_maxChainSteps] cap.
///
/// getIt is wired with fakes; the LlmEngine hands back scripted chats so the
/// whole loop runs on the host without a model or plugin.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:anvil/core/chat_repository.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/fn_schema.dart';
import 'package:anvil/core/foreground_task.dart';
import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/llm_chat.dart';
import 'package:anvil/engines/llm_engine.dart';
import 'package:anvil/models/manifest.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/ui/agent/chat_controller.dart';

const _variant = ModelVariant(
  id: 'v1',
  tier: ModelTier.fast,
  url: 'https://example.test/model',
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  sizeBytes: 1,
  runtime: ModelRuntime.task,
  minRamGb: 0,
  accelerator: 'cpu',
  version: '1',
);

/// A tool that yields one [ToolRunning] then writes an output file and yields
/// [ToolSucceeded]; stands in for `pdf/from-jpg`-like and `pdf/add-text`-like.
class _ChainTool extends BaseToolModule {
  _ChainTool({
    required this.meta,
    required this.outPath,
    required this.outName,
  });
  @override
  final ToolMeta meta;
  final String outPath;
  final String outName;

  @override
  EngineKind get engine => EngineKind.pdf;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'working');
    File(outPath).writeAsStringSync('output');
    yield ToolSucceeded(
      ToolResult(
        files: [OutputFile(path: outPath, name: outName)],
      ),
    );
  }
}

ToolMeta _meta(String id, List<String> accepts) => ToolMeta(
  id: id,
  category: ToolCategory.pdf,
  label: id == 'from-jpg' ? 'Image to PDF' : 'Add Text to PDF',
  icon: Icons.picture_as_pdf,
  description: 'A PDF tool.',
  tinywowSlug: id,
  acceptedExtensions: accepts,
);

/// One scripted turn: streams its events on send; a step never re-sends.
class _ScriptedChat implements LlmChat {
  _ScriptedChat(this._turn);
  final List<LlmEvent> _turn;

  @override
  Stream<LlmEvent> send(
    String text, {
    List<Uint8List> images = const [],
  }) async* {
    for (final e in _turn) {
      yield e;
    }
  }

  @override
  Stream<LlmEvent> sendToolResult({
    required String toolName,
    required Map<String, dynamic> response,
  }) async* {}

  @override
  Future<void> close() async {}
}

/// Pops the next scripted chat per [startChat]; counts invocations so a test
/// can assert re-shortlisting happened once per step.
class _FakeLlmEngine extends LlmEngine {
  _FakeLlmEngine(this._chats, {this.loadGate});
  final List<List<LlmEvent>> _chats;

  /// When set, `ensureLoaded` blocks on it — a stand-in for the tens of
  /// seconds a cold multi-GB `.litertlm` takes to map and build its kernels.
  final Completer<void>? loadGate;
  int startChatCount = 0;

  @override
  Future<void> ensureLoaded(
    String modelPath, {
    bool supportImage = false,
    ModelFamily family = ModelFamily.gemma4,
    int maxTokens = 4096,
    String? taskId,
  }) async {
    if (loadGate != null) await loadGate!.future;
  }

  @override
  Future<LlmChat> startChat({
    required List<Map<String, dynamic>> fnSchemas,
    required String systemInstruction,
    required double temperature,
    required int topK,
    required double topP,
    required int maxOutputTokens,
    bool supportImage = false,
    ModelFamily family = ModelFamily.gemma4,
  }) async {
    startChatCount++;
    return _ScriptedChat(_chats.removeAt(0));
  }
}

class _FakeModelManager implements ModelManager {
  @override
  Future<LoadedModel> ensureReady(
    ModelSpec spec, {
    void Function(int, int)? onProgress,
  }) async => LoadedModel(
    taskId: spec.taskId,
    variant: _variant,
    filePath: '/tmp/model',
  );

  @override
  Future<List<AvailableModel>> availableModels() async => const [
    AvailableModel(
      taskId: 'agent.llm',
      variant: _variant,
      compatible: true,
      cached: true,
      chat: true,
      supportsImage: false,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHistoryRepository implements HistoryRepository {
  @override
  Future<int> add(HistoryRecord r) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Database> _openChatDb() => databaseFactory.openDatabase(
  inMemoryDatabasePath,
  options: OpenDatabaseOptions(
    version: 4,
    onCreate: (db, _) async {
      await db.execute('''
            CREATE TABLE chat_sessions(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              model_task_id TEXT NOT NULL,
              temperature REAL NOT NULL,
              top_k INTEGER NOT NULL,
              top_p REAL NOT NULL,
              max_output_tokens INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
      await db.execute('''
            CREATE TABLE chat_messages(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id INTEGER NOT NULL,
              role TEXT NOT NULL,
              kind TEXT NOT NULL,
              text TEXT NOT NULL,
              thinking TEXT,
              tool_label TEXT,
              output_name TEXT,
              output_path TEXT,
              attachments TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
    },
  ),
);

void main() {
  sqfliteFfiInit();

  late Directory tmp;
  late Database db;
  late _ChainTool toolA;
  late _ChainTool toolB;
  late String inputPath;
  late String outAPath;

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('chain_test');
    inputPath = p.join(tmp.path, 'in.jpg');
    outAPath = p.join(tmp.path, 'a.pdf');
    File(inputPath).writeAsStringSync('jpg');

    toolA = _ChainTool(
      meta: _meta('from-jpg', const ['jpg']),
      outPath: outAPath,
      outName: 'a.pdf',
    );
    toolB = _ChainTool(
      meta: _meta('add-text', const ['pdf']),
      outPath: p.join(tmp.path, 'b.pdf'),
      outName: 'b.pdf',
    );

    db = await _openChatDb();
    getIt.registerSingleton<ChatRepository>(ChatRepository(db));
    getIt.registerSingleton<HistoryRepository>(_FakeHistoryRepository());
    getIt.registerSingleton<ToolRegistry>(ToolRegistry([toolA, toolB]));
    getIt.registerSingleton<ModelManager>(_FakeModelManager());
    // The controller holds the process up for the duration of a turn; on the
    // host there is no Android service behind the channel.
    getIt.registerSingleton<ForegroundKeepAlive>(
        ForegroundKeepAlive(supported: false));
  });

  tearDown(() async {
    await getIt.reset();
    await db.close();
    await tmp.delete(recursive: true);
  });

  _FakeLlmEngine wireEngine(
    List<List<LlmEvent>> chats, {
    Completer<void>? loadGate,
  }) {
    final engine = _FakeLlmEngine(chats, loadGate: loadGate);
    getIt.registerSingleton<LlmEngine>(engine);
    return engine;
  }

  Future<void> settle(
    ProviderContainer container,
    bool Function(ChatUiState) cond,
  ) async {
    for (var i = 0; i < 500; i++) {
      if (cond(container.read(chatProvider))) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('condition never met: ${container.read(chatProvider)}');
  }

  test(
    'a two-step chain runs different tools and re-shortlists per step',
    () async {
      final nameA = fnNameFor(toolA.meta);
      final nameB = fnNameFor(toolB.meta);
      final engine = wireEngine([
        [
          LlmToolCall(name: nameA, args: {'file': inputPath}),
        ],
        [
          LlmToolCall(name: nameB, args: {'file': outAPath}),
        ],
        const [LlmTurnDone('Done.')],
      ]);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);

      // No taps anywhere: send drives both steps and the closing answer.
      await notifier.send('make a pdf then add text');
      await settle(container, (s) => !s.busy && s.messages.isNotEmpty);

      expect(engine.startChatCount, 3);
      final msgs = container.read(chatProvider).messages;
      final steps =
          msgs.where((m) => m.kind == ChatMessageKind.toolStep).toList();
      expect(steps, hasLength(2));
      // Step 1's output is reopenable and became step 2's input.
      expect(steps.first.outputPath, outAPath);
      expect(msgs.last.text, 'Done.');
    },
  );

  test('the chain stops at the step cap without another turn', () async {
    final nameA = fnNameFor(toolA.meta);
    final call = [
      LlmToolCall(name: nameA, args: {'file': inputPath}),
    ];
    final engine = wireEngine([call, call, call, call, call, call]);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(chatProvider.notifier);

    await notifier.send('make a pdf again and again');
    await settle(container, (s) => !s.busy && s.messages.isNotEmpty);

    // Five steps ran back to back; the cap stopped a sixth turn.
    expect(engine.startChatCount, 5);
    final msgs = container.read(chatProvider).messages;
    expect(msgs.where((m) => m.kind == ChatMessageKind.toolStep), hasLength(5));
    expect(msgs.last.text, contains('5-step limit'));
  });

  test(
    'a cold model does not swallow the turn: the question is on screen and '
    'the chat is busy while the model is still loading',
    () async {
      final gate = Completer<void>();
      wireEngine([
        [
          LlmToolCall(name: fnNameFor(toolA.meta), args: {'file': inputPath}),
        ],
        const [LlmTurnDone('Done.')],
      ], loadGate: gate);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      final keepAlive = getIt<ForegroundKeepAlive>();

      final sending = notifier.send('make a pdf');
      await settle(container, (s) => s.messages.isNotEmpty);

      // Still inside ensureLoaded: the composer was cleared, so the user turn
      // and the busy state are what stop the screen looking frozen.
      expect(gate.isCompleted, isFalse);
      final mid = container.read(chatProvider);
      expect(mid.busy, isTrue);
      expect(mid.messages.single.role, ChatRole.user);
      expect(mid.messages.single.text, 'make a pdf');
      // …and the process is held so the load survives an app switch.
      expect(keepAlive.active, isTrue);

      gate.complete();
      await sending;
      await settle(container, (s) => !s.busy);

      // The step ran unattended and the hold was handed back at the end.
      expect(keepAlive.active, isFalse);
    },
  );
}
