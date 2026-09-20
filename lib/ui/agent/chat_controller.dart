/// Riverpod state + execution for the unified Ask tab: persistent multi-session
/// chat with streamed thinking/answers and auto-executed tool steps.
///
/// Owns the session list, the current transcript, in-flight streaming state,
/// staged attachments, and the live [AgentSession]. A validated tool call runs
/// the moment the model emits it; Stop cancels the chain. Plain
/// [NotifierProvider] — not
/// autoDispose — so the chat survives tab switches inside the shell's
/// IndexedStack.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/agent/agent_session.dart';
import 'package:anvil/agent/arg_validator.dart';
import 'package:anvil/agent/attachment_ingest.dart';
import 'package:anvil/agent/chain_prompt.dart';
import 'package:anvil/agent/tool_shortlist.dart';
import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/chat_repository.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/foreground_task.dart';
import 'package:anvil/core/fn_schema.dart';
import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/llm_engine.dart';
import 'package:anvil/models/manifest.dart';
import 'package:anvil/models/model_manager.dart';

class ChatUiState {
  final List<ChatSession> sessions;
  final int? currentId;
  final List<ChatMessage> messages;
  final String streamingText;
  final String streamingThinking;
  final List<InputFile> attachments;
  final String? stepProgress;
  final bool busy;

  const ChatUiState({
    this.sessions = const [],
    this.currentId,
    this.messages = const [],
    this.streamingText = '',
    this.streamingThinking = '',
    this.attachments = const [],
    this.stepProgress,
    this.busy = false,
  });

  ChatSession? get current =>
      sessions.where((s) => s.id == currentId).firstOrNull;

  ChatUiState copyWith({
    List<ChatSession>? sessions,
    int? currentId,
    bool clearCurrentId = false,
    List<ChatMessage>? messages,
    String? streamingText,
    String? streamingThinking,
    List<InputFile>? attachments,
    String? stepProgress,
    bool clearStepProgress = false,
    bool? busy,
  }) => ChatUiState(
    sessions: sessions ?? this.sessions,
    currentId: clearCurrentId ? null : (currentId ?? this.currentId),
    messages: messages ?? this.messages,
    streamingText: streamingText ?? this.streamingText,
    streamingThinking: streamingThinking ?? this.streamingThinking,
    attachments: attachments ?? this.attachments,
    stepProgress: clearStepProgress
        ? null
        : (stepProgress ?? this.stepProgress),
    busy: busy ?? this.busy,
  );
}

class ChatController extends Notifier<ChatUiState> {
  AgentSession? _session;
  StreamSubscription<AgentEvent>? _sub;

  // --- Chain orchestration (controller-driven; one AgentSession per step) --
  static const int _maxChainSteps = 5;
  static const int _agentToolLimit = 6; // fewer schemas: better 2B selection + tokens
  // Needle renders at most five declarations per turn — above five its
  // retrieval head silently drops the rest, and a dropped tool is unreachable.
  static const int _needleToolLimit = 5;
  static const int _imageTokenCost = 300; // Gemma 4 ~280 tokens/image; round up
  static const int _promptMargin = 128; // headroom below the KV budget
  final List<ChainStep> _steps = [];
  String _request = '';
  List<Uint8List> _images = const [];
  List<String> _textBlocks = const [];
  List<ChatMessage> _priorMessages = const [];
  List<InputFile> _attachments = const [];
  bool _supportsImage = false;
  ModelFamily _modelFamily = ModelFamily.gemma4;
  // Tools shortlisted for the current step; used to make a give-up message
  // name what the assistant could actually do.
  List<ToolModule> _lastCandidates = const [];
  // Files the current step may consume (attachments, or prior-step outputs).
  // Shared with the AgentSession so a fallback proposal fills the same args.
  List<InputFile> _stepFiles = const [];

  ChatRepository get _repo => getIt<ChatRepository>();

  @override
  ChatUiState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _session?.close();
    });
    _loadSessions();
    return const ChatUiState();
  }

  Future<void> _loadSessions() async {
    final sessions = await _repo.sessions();
    final id = state.currentId;
    final messages = id == null
        ? const <ChatMessage>[]
        : await _repo.messages(id);
    state = state.copyWith(sessions: sessions, messages: messages);
  }

  // --- Session management -------------------------------------------------

  void newSession() {
    _closeSession();
    state = state.copyWith(
      clearCurrentId: true,
      messages: const [],
      attachments: const [],
      streamingText: '',
      streamingThinking: '',
      busy: false,
    );
  }

  Future<void> selectSession(int id) async {
    _closeSession();
    final messages = await _repo.messages(id);
    state = state.copyWith(
      currentId: id,
      messages: messages,
      attachments: const [],
      streamingText: '',
      streamingThinking: '',
      busy: false,
    );
  }

  Future<void> renameSession(int id, String title) async {
    final s = state.sessions.where((s) => s.id == id).firstOrNull;
    if (s == null) return;
    await _repo.updateSession(s.copyWith(title: title.trim()));
    await _loadSessions();
  }

  Future<void> deleteSession(int id) async {
    await _repo.deleteSession(id);
    if (state.currentId == id) {
      _closeSession();
      state = state.copyWith(
        clearCurrentId: true,
        messages: const [],
        busy: false,
      );
    }
    await _loadSessions();
  }

  Future<void> updateSettings({
    double? temperature,
    int? topK,
    double? topP,
    int? maxOutputTokens,
  }) async {
    final s = state.current;
    if (s == null) return;
    await _repo.updateSession(
      s.copyWith(
        temperature: temperature,
        topK: topK,
        topP: topP,
        maxOutputTokens: maxOutputTokens,
      ),
    );
    await _loadSessions();
  }

  Future<void> setModel(String taskId) async {
    final s = state.current;
    if (s == null) return;
    await _repo.updateSession(s.copyWith(modelTaskId: taskId));
    await _loadSessions();
  }

  // --- Attachments --------------------------------------------------------

  void attach(List<InputFile> files) =>
      state = state.copyWith(attachments: [...state.attachments, ...files]);

  void detach(InputFile file) => state = state.copyWith(
    attachments: [
      for (final f in state.attachments)
        if (f.path != file.path) f,
    ],
  );

  /// Pre-loads the current session's model into the engine ahead of the first
  /// send so the initial turn isn't cold — but ONLY when it's already cached
  /// (never triggers a multi-GB download). Best-effort; failures are swallowed
  /// and surface properly on the real send. Call from the composer on focus.
  Future<void> warm() async {
    if (state.busy) return;
    final taskId = state.current?.modelTaskId ?? ChatSession.defaultModelTaskId;
    try {
      if (await getIt<ModelManager>().status(taskId) != ModelStatus.cached) {
        return;
      }
      await _prepareEngine(taskId);
    } catch (_) {
      // Warming is optional; the real send re-runs prep and reports errors.
    }
  }

  /// Hands the model's RAM back. Any in-flight turn is stopped first — the
  /// native engine must not be torn down under a generating conversation —
  /// and the next send re-loads from the cached file.
  Future<void> unloadModel() async {
    await stop();
    await getIt<LlmEngine>().unload();
  }

  /// Resolves + loads the model for [taskId] and returns whether it is
  /// vision-capable. Shared by [send] and [warm].
  Future<bool> _prepareEngine(String taskId) async {
    final loaded = await getIt<ModelManager>().ensureReady(
      ModelSpec(taskId: taskId),
    );
    return _loadEngine(loaded);
  }

  /// Loads an already-resolved model into the engine. Split out of
  /// [_prepareEngine] so [send] can persist the user's turn — and flip the UI
  /// into its busy/loading state — BEFORE blocking on the tens of seconds a
  /// cold multi-GB `.litertlm` takes to map and build its GPU kernels.
  Future<bool> _loadEngine(LoadedModel loaded) async {
    final v = loaded.variant;
    await getIt<LlmEngine>().ensureLoaded(
      loaded.filePath,
      supportImage: v.supportsImage,
      family: v.family,
      maxTokens: v.maxTokens,
      taskId: loaded.taskId,
    );
    _modelFamily = v.family;
    return v.supportsImage;
  }

  /// Keeps the process alive while a turn or a tool step runs, so the user can
  /// switch apps mid-chain. Held from [send] and each step; released on every
  /// terminal state.
  Future<void> _holdProcess(String label) =>
      keepAliveHold(keepAliveChat, label);

  Future<void> _releaseProcess() => keepAliveRelease(keepAliveChat);

  // --- Turn ---------------------------------------------------------------

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.busy) return;

    // Create the session lazily on the first message.
    int id;
    if (state.currentId == null) {
      final fresh = ChatSession.fresh(DateTime.now());
      id = await _repo.createSession(fresh);
      state = state.copyWith(currentId: id);
      await _loadSessions();
    } else {
      id = state.currentId!;
    }
    final session = state.current!;

    final attachments = state.attachments;
    final priorMessages = state.messages;

    // Busy BEFORE the first await: the composer has already been cleared, and
    // a cold model blocks this turn for tens of seconds. Without the flip the
    // screen looks frozen and Send stays tappable.
    state = state.copyWith(busy: true);
    await _holdProcess('Anvil is answering');

    try {
      // Resolve the cached model file. Send is gated on a cached model, so
      // this is a manifest+disk check, not a download.
      final loaded = await getIt<ModelManager>().ensureReady(
        ModelSpec(taskId: session.modelTaskId),
      );
      final supportsImage = loaded.variant.supportsImage;

      // Persist the user turn immediately (chips classified by extension).
      final refs = [
        for (final f in attachments)
          ChatAttachmentRef(
            name: f.name,
            ingest: _classify(f.name, supportsImage),
          ),
      ];
      await _repo.addMessage(
        ChatMessage(
          sessionId: id,
          role: ChatRole.user,
          kind: ChatMessageKind.text,
          text: trimmed,
          attachments: refs,
          createdAt: DateTime.now(),
        ),
      );
      state = state.copyWith(
        messages: [...state.messages, ...await _tail(id)],
        attachments: const [],
        busy: true,
      );

      logAction(
        logSourceAgent,
        'Ask: $trimmed',
        detail: attachments.isEmpty
            ? null
            : [for (final f in attachments) f.name].join('\n'),
      );

      // The slow part, now that the turn is on screen: loading reports its
      // phase on LlmEngine.statusStream (llmStatusProvider).
      await _loadEngine(loaded);

      // Ingest attachments: images for vision, text blocks otherwise.
      final images = <Uint8List>[];
      final textBlocks = <String>[];
      for (final f in attachments) {
        final ingested = await ingestAttachment(
          f,
          modelSupportsImage: supportsImage,
        );
        switch (ingested) {
          case IngestedImage(:final bytes):
            images.add(bytes);
            // A cue in the text channel so the model ties the request to the
            // image it sees and to the path listed under "Available files".
            textBlocks.add('\n[Attached image: ${f.name}]');
          case IngestedText(:final content):
            textBlocks.add('\n[Attached file: ${f.name}]\n$content');
          case IngestRejected(:final reason):
            await _addAssistant(id, ChatMessageKind.failure, text: reason);
        }
      }

      _request = trimmed;
      _images = images;
      _textBlocks = textBlocks;
      _priorMessages = priorMessages;
      _attachments = attachments;
      _supportsImage = supportsImage;
      _steps.clear();
      await _startStep(first: true);
    } catch (e, s) {
      final message = switch (e) {
        ToolException e => e.message,
        IncompatibleDeviceException e => e.message,
        _ => 'The assistant could not start.',
      };
      logError(logSourceAgent, 'Assistant could not start', error: e, stack: s);
      await _fail(message);
    }
  }

  /// Builds a fresh chat for the next chain step: re-shortlists tools against
  /// the request (plus completed-step labels), seeds either the original prompt
  /// or a continuation prompt, and starts the single-turn [AgentSession].
  Future<void> _startStep({required bool first}) async {
    // Free the finished step's conversation (its KV cache) before the next
    // chat is created; the model itself stays loaded.
    _closeSession();
    final session = state.current!;
    final query = first ? _request : chainShortlistQuery(_request, _steps);
    final needle = _modelFamily == ModelFamily.needle3;
    final candidates = shortlistTools(
      getIt<ToolRegistry>().all,
      query,
      limit: needle ? _needleToolLimit : _agentToolLimit,
      attachmentExts: first
          ? ({for (final f in _attachments) _extOf(f.name)}
              ..removeWhere((e) => e.isEmpty))
          : const {},
    );
    _lastCandidates = candidates;
    logAction(
      logSourceAgent,
      'Shortlisted ${candidates.length} tool(s) for step ${_steps.length + 1}',
      detail: [for (final t in candidates) t.meta.qualifiedId].join('\n'),
    );
    // Needle ignores prose instructions and only accepts environment facts;
    // the rule list would be dead tokens diluting its grounding.
    final system = needle
        ? _needleSystemFacts()
        : _systemInstruction(first ? _attachments : const []);
    final chat = await getIt<LlmEngine>().startChat(
      fnSchemas: [for (final t in candidates) t.fnSchema],
      systemInstruction: system,
      temperature: session.temperature,
      topK: session.topK,
      topP: session.topP,
      maxOutputTokens: session.maxOutputTokens,
      supportImage: _supportsImage,
      family: _modelFamily,
    );
    _stepFiles = first
        ? _attachments
        : [
            for (final s in _steps)
              if (s.outputPath != null)
                InputFile(
                  path: s.outputPath!,
                  name: s.outputName ?? s.outputPath!.split('/').last,
                ),
          ];
    _session = AgentSession(
      chat: chat,
      tools: candidates,
      step: _steps.length + 1,
      availableFiles: _stepFiles,
    );
    String prompt;
    if (first) {
      final base = _basePrompt(_priorMessages, _request);
      if (needle) {
        // Needle cannot read or summarise document text, so attached blocks
        // are pure dilution.
        prompt = base;
      } else {
        final schemaTokens = candidates.fold<int>(
            0, (a, t) => a + estimateTokens(jsonEncode(t.fnSchema)));
        final reserved = estimateTokens(system) +
            schemaTokens +
            estimateTokens(base) +
            _images.length * _imageTokenCost +
            session.maxOutputTokens +
            _promptMargin;
        final blocks = fitTextBlocks(
            _textBlocks, getIt<LlmEngine>().contextTokens - reserved);
        prompt = base + blocks.join();
      }
    } else {
      prompt = continuationPrompt(_request, _steps);
    }
    if (needle && _stepFiles.isNotEmpty) {
      // Needle grounds every argument in the INPUT: a path that appears only
      // in the system turn is not used — it fabricates `{"file": "pdf"}`
      // instead. The parenthesised suffix measured best; a `files:` line
      // skewed routing toward multi-file tools.
      prompt = '$prompt (${[for (final f in _stepFiles) f.path].join(' ')})';
    }
    logAction(
      logSourceAgent,
      'Step ${_steps.length + 1} prompt: ${estimateTokens(prompt)} tok, '
      '${candidates.length} tools',
      detail: _clip(prompt, 1200),
    );
    _consume(_session!.start(prompt, images: first ? _images : const []));
  }

  /// Runs a validated step the moment the model produces it. Nothing waits on
  /// a tap: the model chooses, [validateCall] vets the args, and the result
  /// feeds the next step. Stop cancels a chain mid-flight.
  Future<void> _runStep(AgentToolCall pending) async {
    final session = _session;
    if (session == null) return;
    state = state.copyWith(busy: true);
    await _holdProcess('Anvil is running a step');
    final call = pending.call;
    logAction(
      logSourceAgent,
      'Step ${pending.step} running: ${call.tool.meta.qualifiedId}',
    );
    final ToolResult result;
    try {
      ToolResult? out;
      await for (final p in call.tool.run(call.input)) {
        switch (p) {
          case ToolRunning(:final message):
            state = state.copyWith(stepProgress: message ?? 'Working\u2026');
          case ToolSucceeded(:final result):
            out = result;
          case ToolFailed(:final message):
            throw ToolException(message);
        }
      }
      if (out == null) {
        throw const ToolException('That step produced no result.');
      }
      result = out;
    } on ToolException catch (e) {
      state = state.copyWith(clearStepProgress: true);
      logError(
        logSourceAgent,
        'Step ${pending.step} failed: ${call.tool.meta.qualifiedId}',
        detail: e.message,
      );
      _consume(session.continueAfterToolError(
        toolName: fnNameFor(call.tool.meta),
        error: e.message,
      ));
      return;
    } catch (e, s) {
      state = state.copyWith(clearStepProgress: true);
      logError(
        logSourceAgent,
        'Step ${pending.step} failed: ${call.tool.meta.qualifiedId}',
        error: e,
        stack: s,
      );
      _consume(session.continueAfterToolError(
        toolName: fnNameFor(call.tool.meta),
        error: 'That step failed: $e',
      ));
      return;
    }
    state = state.copyWith(clearStepProgress: true);
    getIt<HistoryRepository>().add(
      HistoryRecord(
        toolId: call.tool.meta.qualifiedId,
        inputNames: [for (final f in call.input.files) f.name],
        outputPaths: [for (final f in result.files) f.path],
        createdAt: DateTime.now(),
      ),
    );
    final outFile = result.files.firstOrNull;
    _steps.add(
      ChainStep(
        toolLabel: call.tool.meta.label,
        outputName: outFile?.name,
        outputPath: outFile?.path,
        resultText: result.text,
      ),
    );
    await _addAssistant(
      state.currentId!,
      ChatMessageKind.toolStep,
      toolLabel: call.tool.meta.label,
      outputName: outFile?.name,
      outputPath: outFile?.path,
    );
    if (_steps.length >= _maxChainSteps) {
      await _addAssistant(
        state.currentId!,
        ChatMessageKind.text,
        text:
            'Reached the $_maxChainSteps-step limit — stopping. '
            'Last output: ${outFile?.name ?? 'none'}.',
      );
      await _touch();
      state = state.copyWith(busy: false);
      _closeSession();
      await _releaseProcess();
      return;
    }
    await _startStep(first: false);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _flushStreamingAssistant();
    _closeSession();
    state = state.copyWith(busy: false, clearStepProgress: true);
    await _releaseProcess();
  }

  // --- Stream consumption -------------------------------------------------

  void _consume(Stream<AgentEvent> stream) {
    _sub?.cancel();
    _sub = stream.listen(
      _onEvent,
      onError: (Object e, StackTrace s) {
        logError(logSourceAgent, 'Assistant stream error', error: e, stack: s);
        _fail('The assistant lost track of that chain.');
      },
    );
  }

  void _onEvent(AgentEvent e) {
    switch (e) {
      case AgentThinking(:final text):
        state = state.copyWith(
          streamingThinking: state.streamingThinking + text,
        );
      case AgentText(:final text):
        state = state.copyWith(streamingText: state.streamingText + text);
      // Terminal events (each ends the stream) do async persistence.
      case final AgentToolCall c:
        _onToolCall(c);
      case AgentDone(:final answer):
        _onDone(answer);
      case AgentStuck(:final message):
        _onStuck(message);
    }
  }

  Future<void> _onToolCall(AgentToolCall c) async {
    logAction(
      logSourceAgent,
      'Step ${c.step}: ${c.call.tool.meta.qualifiedId}',
      detail: _callDetail(c.call),
    );
    await _flushStreamingAssistant();
    await _runStep(c);
  }

  Future<void> _onDone(String answer) async {
    logAction(logSourceAgent, 'Answered', detail: answer);
    state = state.copyWith(streamingText: answer);
    await _flushStreamingAssistant();
    await _touch();
    state = state.copyWith(busy: false);
    _closeSession();
    await _releaseProcess();
  }

  /// A model failure must not dead-end the turn: fall back to the
  /// deterministic shortlist's best match and run it.
  Future<void> _onStuck(String message) async {
    logWarning(logSourceAgent, 'Assistant gave up', detail: message);
    await _flushStreamingAssistant();
    final fb = _fallbackProposal();
    if (fb == null) {
      await _fail(_stuckMessage(message));
      return;
    }
    logWarning(
      logSourceAgent,
      'Model produced no valid call; proposing '
      '${fb.call.tool.meta.qualifiedId}',
      detail: message,
    );
    final id = state.currentId;
    if (id != null) {
      await _addAssistant(
        id,
        ChatMessageKind.text,
        text: "I'm not sure I understood that — running the closest match.",
      );
    }
    await _onToolCall(fb);
  }

  /// First shortlisted tool whose call validates with only the step's files
  /// filled in. Candidates are filtered by whether a file is attached, so we
  /// never propose a file tool with no file (or a generator over an
  /// attachment the user clearly wants acted on).
  AgentToolCall? _fallbackProposal() {
    final wantsInput = _stepFiles.isNotEmpty;
    for (final t in _lastCandidates) {
      if (t.meta.requiresInput != wantsInput) continue;
      try {
        return AgentToolCall(
          validateCall(t, fillFileArgs(t, const {}, _stepFiles)),
          _steps.length + 1,
        );
      } on InvalidCallException {
        continue;
      }
    }
    return null;
  }

  /// Turns the bare give-up sentinel into a message that names a few of the
  /// tools shortlisted for this step, so the user has a concrete next move.
  String _stuckMessage(String raw) {
    if (raw != kAgentCouldNotAnswer || _lastCandidates.isEmpty) return raw;
    final labels = _lastCandidates.take(4).map((t) => t.meta.label).join(', ');
    return "I couldn't map that to an on-device tool. For this I can: "
        '$labels. Try one of those directly, or rephrase the request.';
  }

  Future<void> _fail(String message) async {
    final id = state.currentId;
    if (id != null) {
      await _addAssistant(id, ChatMessageKind.failure, text: message);
    }
    state = state.copyWith(
      busy: false,
      clearStepProgress: true,
    );
    _closeSession();
    await _releaseProcess();
  }

  /// Persists accumulated streaming thinking/text as an assistant message when
  /// either is non-empty, then clears the accumulators.
  Future<void> _flushStreamingAssistant() async {
    final id = state.currentId;
    final text = state.streamingText;
    final thinking = state.streamingThinking;
    if (id == null || (text.isEmpty && thinking.isEmpty)) return;
    await _repo.addMessage(
      ChatMessage(
        sessionId: id,
        role: ChatRole.assistant,
        kind: ChatMessageKind.text,
        text: text,
        thinking: thinking.isEmpty ? null : thinking,
        createdAt: DateTime.now(),
      ),
    );
    state = state.copyWith(
      messages: [...state.messages, ...await _tail(id)],
      streamingText: '',
      streamingThinking: '',
    );
  }

  Future<void> _addAssistant(
    int id,
    ChatMessageKind kind, {
    String text = '',
    String? toolLabel,
    String? outputName,
    String? outputPath,
  }) async {
    await _repo.addMessage(
      ChatMessage(
        sessionId: id,
        role: ChatRole.assistant,
        kind: kind,
        text: text,
        toolLabel: toolLabel,
        outputName: outputName,
        outputPath: outputPath,
        createdAt: DateTime.now(),
      ),
    );
    state = state.copyWith(messages: [...state.messages, ...await _tail(id)]);
  }

  /// The single newest message for [id] — appended so the in-memory list stays
  /// in sync with the row's real (auto-increment) id.
  Future<List<ChatMessage>> _tail(int id) async {
    final all = await _repo.messages(id);
    return all.isEmpty ? const [] : [all.last];
  }

  Future<void> _touch() async {
    final id = state.currentId;
    if (id == null) return;
    await _repo.touchSession(id, DateTime.now());
    await _loadSessions();
  }

  void _closeSession() {
    _sub?.cancel();
    _sub = null;
    final s = _session;
    _session = null;
    s?.close();
  }

  // --- Prompt shaping -----------------------------------------------------

  String _basePrompt(List<ChatMessage> prior, String text) {
    final ctx = _conversationContext(prior);
    return ctx.isEmpty ? text : '$ctx\n\n$text';
  }

  /// Renders the last [maxTurns] finalized messages as User:/Assistant: lines
  /// to carry continuity without native KV replay (each turn builds a fresh
  /// chat so the tool shortlist can adapt per turn).
  String _conversationContext(List<ChatMessage> messages, {int maxTurns = 4}) {
    final recent = messages.length <= maxTurns
        ? messages
        : messages.sublist(messages.length - maxTurns);
    final lines = <String>[];
    for (final m in recent) {
      final who = m.role == ChatRole.user ? 'User' : 'Assistant';
      switch (m.kind) {
        case ChatMessageKind.text:
          if (m.text.trim().isNotEmpty) lines.add('$who: ${m.text}');
        case ChatMessageKind.toolStep:
          lines.add(
            'Assistant: (ran ${m.toolLabel}'
            '${m.outputName != null ? ' → ${m.outputName}' : ''})',
          );
        case ChatMessageKind.failure:
          break;
      }
    }
    return lines.join('\n');
  }

  /// Chip classification (display only); the real ingest result may differ
  /// (e.g. a scanned PDF rejected), in which case a failure message is added.
  String _classify(String name, bool supportsImage) {
    final ext = _extOf(name);
    const textLike = {
      'txt',
      'text',
      'md',
      'markdown',
      'json',
      'jsonl',
      'csv',
      'tsv',
      'xml',
      'yaml',
      'yml',
      'log',
      'ini',
      'toml',
      'html',
      'htm',
      'css',
      'dart',
      'py',
      'js',
      'ts',
      'tsx',
      'jsx',
      'java',
      'kt',
      'kts',
      'c',
      'h',
      'cpp',
      'cc',
      'hpp',
      'cs',
      'go',
      'rs',
      'rb',
      'php',
      'swift',
      'sql',
      'sh',
      'bash',
      'pdf',
      'xlsx',
    };
    const imageLike = {
      'jpg',
      'jpeg',
      'png',
      'webp',
      'heic',
      'heif',
      'bmp',
      'gif',
      'tiff',
      'tif',
      'avif',
    };
    if (textLike.contains(ext)) return 'text';
    if (imageLike.contains(ext)) return supportsImage ? 'image' : 'text';
    return 'rejected';
  }

  String _extOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

/// Bounds one log entry's detail; the log table keeps a fixed number of rows.
String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

/// A proposed call as log detail: tool, input names, params. No file contents.
String? _callDetail(ValidatedCall call) {
  final parts = <String>[
    for (final f in call.input.files) f.name,
    for (final e in call.input.params.entries) '${e.key}=${e.value}',
  ];
  return parts.isEmpty ? null : parts.join('\n');
}

String _systemInstruction(List<InputFile> files) {
  final list = files.isEmpty
      ? '- none'
      : [for (final f in files) '- ${f.path}'].join('\n');
  return "You are Anvil's assistant. You run fully offline on this phone.\n"
      'Call ONE tool per turn, or reply in plain text when no tool fits.\n'
      'Rules:\n'
      '- File arguments are absolute paths copied from "Available files" or '
      'from a previous tool result. Never invent a path.\n'
      '- The listed files are already attached — never ask the user for a file '
      'that is listed.\n'
      '- Prefer the single tool that satisfies the whole request in one step.\n'
      '- After a tool result arrives, call the next tool if work remains, '
      'otherwise reply with a one-sentence summary.\n'
      '- If no tool fits, say so in plain text and name what you can do '
      'instead. Never reply with an empty message.\n'
      'Available files:\n'
      '$list';
}

/// Needle's system turn: environment facts only. It ignores prose rules (it
/// has no instruction-following path at all), but it does ground date/device
/// references against whatever facts it is given.
String _needleSystemFacts() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return 'date: ${n.year}-${two(n.month)}-${two(n.day)} '
      '${days[n.weekday - 1]} ${two(n.hour)}:${two(n.minute)}; device: phone';
}

final chatProvider = NotifierProvider<ChatController, ChatUiState>(
  ChatController.new,
);
