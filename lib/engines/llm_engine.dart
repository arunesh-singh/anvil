/// Wraps `flutter_gemma` (Gemma 4 E2B via the LiteRT-LM FFI engine) — the
/// single place the plugin is touched. The model file (`agent.llm`, a
/// `.litertlm` bundle) is delivered/verified by [ModelManager]; this engine
/// installs it into the plugin and serves one-shot generations (write tools)
/// and function-calling chats (the agent, through the plugin-free [LlmChat]).
///
/// The slot holds ONE model. Every transition of that slot is broadcast on
/// [LlmEngine.statusStream] so the UI can show "loading Gemma 4 E2B…" instead
/// of sitting silent for the ~10–40 s a multi-GB `.litertlm` takes to map and
/// build its GPU kernels, and offer [LlmEngine.unload] to hand that RAM back.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/llm_chat.dart';
import 'package:anvil/models/manifest.dart';

/// Lifecycle of the engine's single in-memory model slot.
enum LlmPhase { unloaded, loading, loaded }

/// Snapshot of the model slot. [taskId] is the manifest task of the model
/// being loaded (or loaded); [since] is when the phase began, so the UI can
/// tick an elapsed counter over an otherwise progress-less native load.
class LlmStatus {
  final LlmPhase phase;
  final String? taskId;
  final DateTime? since;

  const LlmStatus(this.phase, {this.taskId, this.since});

  bool get isLoading => phase == LlmPhase.loading;
  bool get isLoaded => phase == LlmPhase.loaded;
}

class LlmEngine {
  /// The KV budget (prompt + output) of the currently loaded model; mirrors
  /// createModel's maxTokens. Callers read [contextTokens] to size prompts.
  int _activeMaxTokens = 4096;
  int get contextTokens => _activeMaxTokens;

  gemma.InferenceModel? _model;
  String? _loadedKey;
  String? _loadedTaskId;

  /// Live conversations/sessions handed out for the loaded model. Tracked so
  /// [unload] can stop native decoding before the model is closed — freeing
  /// the engine out from under a generating conversation is a native crash.
  final Set<_GemmaLlmChat> _chats = {};
  final Set<gemma.InferenceModelSession> _sessions = {};

  /// Serializes load/unload: the native create runs on a spawned isolate, so
  /// two concurrent `ensureLoaded`s (composer warm-up + Send) would otherwise
  /// both see an empty slot and build two multi-GB engines.
  Future<void>? _inflight;
  String? _inflightKey;

  LlmStatus _status = const LlmStatus(LlmPhase.unloaded);
  final StreamController<LlmStatus> _statusCtl =
      StreamController<LlmStatus>.broadcast();

  /// Current slot state; pair with [statusStream] for updates.
  LlmStatus get status => _status;

  /// Slot transitions (loading → loaded → unloaded). Broadcast, never closed.
  Stream<LlmStatus> get statusStream => _statusCtl.stream;

  void _emit(LlmStatus s) {
    _status = s;
    if (!_statusCtl.isClosed) _statusCtl.add(s);
  }

  /// Maps a manifest [ModelFamily] onto the plugin's `ModelType`.
  gemma.ModelType _gemmaType(ModelFamily f) => switch (f) {
    ModelFamily.gemma4 => gemma.ModelType.gemma4,
    ModelFamily.qwen3 => gemma.ModelType.qwen3,
  };

  String _keyOf(String path, bool supportImage, ModelFamily family, int max) =>
      '$path|$supportImage|${family.name}|$max';

  /// Loads the model at [modelPath] once; subsequent calls are no-ops until
  /// the path (or a load parameter) changes. Concurrent calls coalesce: the
  /// same configuration joins the in-flight load, a different one queues
  /// behind it. [taskId] is carried into [status] for the UI label only.
  Future<void> ensureLoaded(String modelPath,
      {bool supportImage = false,
      ModelFamily family = ModelFamily.gemma4,
      int maxTokens = 4096,
      String? taskId}) {
    final key = _keyOf(modelPath, supportImage, family, maxTokens);
    if (_model != null && _loadedKey == key) return Future<void>.value();
    final inflight = _inflight;
    if (inflight != null && _inflightKey == key) return inflight;
    final future =
        (inflight == null ? Future<void>.value() : inflight.catchError((_) {}))
            .then((_) => _load(modelPath, key, supportImage, family, maxTokens,
                taskId));
    _inflight = future;
    _inflightKey = key;
    return future.whenComplete(() {
      if (identical(_inflight, future)) {
        _inflight = null;
        _inflightKey = null;
      }
    });
  }

  Future<void> _load(String modelPath, String key, bool supportImage,
      ModelFamily family, int maxTokens, String? taskId) async {
    // Re-check: a queued load may have been satisfied by the one ahead of it.
    if (_model != null && _loadedKey == key) return;
    _emit(LlmStatus(LlmPhase.loading, taskId: taskId, since: DateTime.now()));
    await _releaseModel();
    final modelType = _gemmaType(family);
    try {
      await gemma.FlutterGemma.installModel(
        modelType: modelType,
        fileType: gemma.ModelFileType.litertlm,
      ).fromFile(modelPath).install();
      // maxTokens is the whole KV budget (prompt + output), curated per model
      // in the manifest. Gemma 4 E2B uses 4096 — Google AI Edge Gallery's
      // config documents ~5.9 GB peak on the 6 GB target, so 8192 risks OOM
      // there; it holds the replayed 4-turn history + one file block + up to 4
      // images (~280 tokens each). Qwen3 text tiers use a larger (RAM-gated)
      // budget so attached PDF text survives. litertlm min is 1024.
      _model = await gemma.FlutterGemmaPlugin.instance.createModel(
        modelType: modelType,
        fileType: gemma.ModelFileType.litertlm,
        maxTokens: maxTokens,
        preferredBackend: gemma.PreferredBackend.gpu,
        supportImage: supportImage,
        maxNumImages: supportImage ? 4 : null,
        // Gemma 4 E2B Multi-Token Prediction (LiteRT-LM >=0.11): faster decode
        // at no accuracy cost. MTP is Gemma-4-specific; pass null (model
        // default) for Qwen3.
        enableSpeculativeDecoding: family == ModelFamily.gemma4 ? true : null,
      );
      _activeMaxTokens = maxTokens;
      _loadedKey = key;
      _loadedTaskId = taskId;
      _emit(LlmStatus(LlmPhase.loaded, taskId: taskId, since: DateTime.now()));
    } catch (e) {
      _emit(const LlmStatus(LlmPhase.unloaded));
      throw ToolException('Could not load the language model: $e');
    }
  }

  /// One-shot generation for the write tools.
  Future<String> generate(String prompt) async {
    final model = _model;
    if (model == null) {
      throw const ToolException(
          'The language model is not loaded — run the tool again.');
    }
    try {
      final session =
          await model.createSession(temperature: 0.7, maxOutputTokens: 2048);
      _sessions.add(session);
      try {
        await session.addQueryChunk(gemma.Message.text(text: prompt, isUser: true));
        final out = (await session.getResponse()).trim();
        if (out.isEmpty) {
          throw const ToolException('The model produced no output.');
        }
        return out;
      } finally {
        _sessions.remove(session);
        await session.close();
      }
    } on ToolException {
      rethrow;
    } catch (e) {
      throw ToolException('Text generation failed: $e');
    }
  }

  /// Function-calling chat for the Phase-3 agent. Takes plain JSON schemas and
  /// returns the plugin-free [LlmChat] seam so `lib/agent/` never imports
  /// flutter_gemma.
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
    final model = _model;
    if (model == null) {
      throw const ToolException(
          'The language model is not loaded — open the assistant again.');
    }
    final tools = [
      for (final s in fnSchemas)
        gemma.Tool(
          name: s['name'] as String,
          description: s['description'] as String,
          parameters: (s['parameters'] as Map).cast<String, dynamic>(),
        ),
    ];
    // Function calling is wired end to end for both families in the pinned
    // SDKs; the plugin picks the wire format from `modelType`:
    //
    // Gemma 4 (`ModelType.gemma4`) → NATIVE SDK-passthrough tool tokens.
    // InferenceModel.createChat (the FFI override in flutter_gemma_litertlm)
    // forwards `tools:` into createSession, which serializes them via
    // SdkResponseParser.serializeToolsForSdk into the native conversation
    // config, so the minja template renders `<|tool>declaration:…<tool|>`;
    // responses take the chatRaw branch, populate `lastRawResponse`, and the
    // plugin yields structured FunctionCallResponse(s) at end of turn.
    //
    // Qwen3 (`ModelType.qwen3`) → the plugin's `QwenFunctionCallFormat`: it
    // weaves its own tool-declaration prompt, appends `/no_think`, and parses
    // `<tool_call>{…}</tool_call>` out of the text stream back into
    // FunctionCallResponse. Either way `_GemmaLlmChat._drive()` maps the
    // response onto [LlmToolCall] unchanged.
    //
    // NOTE: `generate()` and this chat share the single `_model` slot; the
    // family loaded by `ensureLoaded` is the one both use.
    final chat = await model.createChat(
      temperature: temperature,
      topK: topK,
      topP: topP,
      tools: tools,
      supportsFunctionCalls: true,
      modelType: _gemmaType(family),
      toolChoice: gemma.ToolChoice.auto,
      maxOutputTokens: maxOutputTokens,
      systemInstruction: systemInstruction,
      supportImage: supportImage,
      // Thinking off: with a bounded KV budget and maxOutputTokens <= 1024, a
      // thinking preamble can eat the output budget before the tool call is
      // emitted, and the gemma4 passthrough classifier assumes a turn is
      // either all tool-call JSON or all text. Qwen3's plugin format appends
      // `/no_think` for the same reason.
      isThinking: false,
    );
    final wrapped = _GemmaLlmChat(chat, this);
    _chats.add(wrapped);
    return wrapped;
  }

  /// Frees the model slot: stops any live generation, closes the sessions and
  /// the native engine, and reports [LlmPhase.unloaded]. Queued behind an
  /// in-flight load — tearing the engine down mid-create is a native crash.
  /// Idempotent; the next request re-loads from the cached file.
  Future<void> unload() {
    final inflight = _inflight;
    final future =
        (inflight == null ? Future<void>.value() : inflight.catchError((_) {}))
            .then((_) async {
      await _releaseModel();
      _emit(const LlmStatus(LlmPhase.unloaded));
    });
    _inflight = future;
    _inflightKey = null;
    return future.whenComplete(() {
      if (identical(_inflight, future)) _inflight = null;
    });
  }

  /// Stops + closes every conversation and the model itself. Does NOT emit —
  /// callers own the resulting phase ([_load] emits loading/loaded).
  Future<void> _releaseModel() async {
    for (final chat in _chats.toList()) {
      await chat.stopAndClose();
    }
    _chats.clear();
    for (final session in _sessions.toList()) {
      try {
        await session.stopGeneration();
      } catch (_) {
        // Nothing in flight, or the session is already gone.
      }
      try {
        await session.close();
      } catch (_) {
        // Already closed by its owner's `finally`.
      }
    }
    _sessions.clear();
    await _model?.close();
    _model = null;
    _loadedKey = null;
    _loadedTaskId = null;
    _activeMaxTokens = 4096;
  }

  /// Task id of the model currently in memory, or null when the slot is empty.
  String? get loadedTaskId => _model == null ? null : _loadedTaskId;

  void _forget(_GemmaLlmChat chat) => _chats.remove(chat);
}

/// The only place plugin response types are mapped onto [LlmEvent].
class _GemmaLlmChat implements LlmChat {
  _GemmaLlmChat(this._chat, this._engine);
  final gemma.InferenceChat _chat;
  final LlmEngine _engine;
  bool _closed = false;

  @override
  Stream<LlmEvent> send(String text, {List<Uint8List> images = const []}) async* {
    await _chat.addQueryChunk(images.isEmpty
        ? gemma.Message.text(text: text, isUser: true)
        : gemma.Message.withImages(
            text: text, imageBytes: images, isUser: true));
    yield* _drive();
  }

  @override
  Stream<LlmEvent> sendToolResult({
    required String toolName,
    required Map<String, dynamic> response,
  }) async* {
    await _chat.addQueryChunk(
        gemma.Message.toolResponse(toolName: toolName, response: response));
    yield* _drive();
  }

  /// Drains one turn's stream into [LlmEvent]s. A tool call ends the turn at
  /// the first call (D6); otherwise the accumulated text closes it.
  Stream<LlmEvent> _drive() async* {
    final buf = StringBuffer();
    await for (final r in _chat.generateChatResponseAsync()) {
      switch (r) {
        case gemma.ThinkingResponse(:final content):
          yield LlmThinkingDelta(content);
        case gemma.TextResponse(:final token):
          buf.write(token);
          yield LlmTextDelta(token);
        case gemma.FunctionCallResponse(:final name, :final args):
          yield LlmToolCall(name: name, args: args);
          return;
        case gemma.ParallelFunctionCallResponse(:final calls):
          yield LlmToolCall(name: calls.first.name, args: calls.first.args);
          return;
      }
    }
    yield LlmTurnDone(buf.toString());
  }

  /// Ends this conversation: native decoding is told to stop (cancelling the
  /// Dart subscription alone only detaches the litertlm stream's consumer),
  /// then the session's KV cache is released. The model stays loaded.
  @override
  Future<void> close() async {
    _engine._forget(this);
    await stopAndClose();
  }

  Future<void> stopAndClose() async {
    if (_closed) return;
    _closed = true;
    try {
      await _chat.stopGeneration();
    } catch (_) {
      // Nothing generating, or the session is already torn down.
    }
    try {
      await _chat.close();
    } catch (_) {
      // Superseded sessions can already be closed; close is idempotent.
    }
  }
}
