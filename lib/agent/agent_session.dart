/// The Phase-3 tool-call loop (D6): the model picks ONE tool per turn, every
/// call is validated against the tool's own schema before anything runs, and
/// the user confirms each step. The controller drives the chain (one session
/// per step); guided chains only — no autonomy, no cloud planner.
///
/// Drives the plugin-free [LlmChat] seam, so it is fully host-testable.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:anvil/agent/arg_validator.dart';
import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/fn_schema.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/llm_chat.dart';

/// The one terminal "gave up" message, emitted only when the model ends its
/// turn with neither a tool call nor any text even after a nudge. The chat
/// controller recognises this sentinel to append what the shortlisted tools
/// can actually do.
const String kAgentCouldNotAnswer = 'The assistant could not answer that.';

/// Fed back after an empty turn to push the model to either call a listed
/// function or answer in plain text — never stay silent (R3: Gemma 4 E2B not
/// infrequently ends a turn empty).
const String _emptyTurnNudge =
    'You returned nothing. Either call ONE of the listed functions (exact '
    'name, with an absolute path copied from "Available files"), or, if none '
    'of them fits, reply in plain text stating what you can and cannot do '
    'here. Do not reply with an empty message.';

sealed class AgentEvent {
  const AgentEvent();
}

/// A chunk of the model's thinking scratchpad.
class AgentThinking extends AgentEvent {
  final String text;
  const AgentThinking(this.text);
}

/// A chunk of the visible answer.
class AgentText extends AgentEvent {
  final String text;
  const AgentText(this.text);
}

/// A validated call awaiting the user's confirm (D6: never auto-execute).
class AgentNeedsConfirm extends AgentEvent {
  final ValidatedCall call;

  /// 1-based position in the chain.
  final int step;
  const AgentNeedsConfirm(this.call, this.step);
}

class AgentDone extends AgentEvent {
  final String answer;
  const AgentDone(this.answer);
}

class AgentStuck extends AgentEvent {
  final String message;
  const AgentStuck(this.message);
}

class AgentSession {
  AgentSession({
    required this.chat,
    required List<ToolModule> tools,
    this.step = 1,
    int maxRepairs = 2,
    this.fileExists,
    this.availableFiles = const [],
  }) : _byId = {for (final t in tools) fnNameFor(t.meta): t},
       _byNorm = _normIndex(tools),
       _repairsLeft = maxRepairs;

  final LlmChat chat;

  /// 1-based position of this session's step in the chain (the controller
  /// drives the chain; a session runs exactly one model turn).
  final int step;

  /// Injectable for host tests; null uses the real filesystem check.
  final bool Function(String path)? fileExists;

  /// Files this step may consume: attachments (first step) or prior-step
  /// outputs. Used to fill an omitted file argument for the 2B model.
  final List<InputFile> availableFiles;

  /// Keyed by the model-facing [fnNameFor] name (grammar-safe, category-
  /// prefixed) — resolution is exact: a bare slug like `compress` would
  /// silently pick whichever category comes first.
  final Map<String, ToolModule> _byId;

  /// The same tools keyed by [_normalizeFnName], so `pdf-compress`,
  /// `pdfCompress` or `PDF_Compress` resolve instead of burning a repair. A
  /// normalization claimed by two tools is dropped: resolution never guesses.
  final Map<String, ToolModule> _byNorm;

  int _repairsLeft;

  Stream<AgentEvent> start(
    String request, {
    List<Uint8List> images = const [],
  }) => _drive(chat.send(request, images: images));

  Future<void> close() => chat.close();

  /// Forwards thinking/text deltas; on a tool call runs the validate/repair
  /// cycle (a bad name or bad args is fed back within the repair budget). A
  /// text turn is first checked for a tool call that arrived as prose instead
  /// of a structured call (flutter_gemma's documented raw-text fallback when
  /// nothing parses out of `lastRawResponse` — see [recoverLeakedToolCall]);
  /// otherwise it finishes with [AgentDone], or [AgentStuck] when empty.
  Stream<AgentEvent> _drive(Stream<LlmEvent> events) async* {
    await for (final e in events) {
      switch (e) {
        case LlmThinkingDelta(:final text):
          yield AgentThinking(text);
        case LlmTextDelta(:final text):
          yield AgentText(text);
        case LlmToolCall(:final name, :final args):
          logAction(logSourceAgent, 'Native tool call: $name',
              detail: jsonEncode(args));
          yield* _handleCall(name, args);
          return;
        case LlmTurnDone(:final text):
          final answer = text.trim();
          final leaked = recoverLeakedToolCall(answer);
          if (leaked != null) {
            logWarning(
              logSourceAgent,
              'Tool call recovered from text channel: ${leaked.name}',
              detail: _clip(answer, 400),
            );
            yield* _handleCall(leaked.name, leaked.args);
            return;
          }
          if (answer.isEmpty) {
            // An empty turn is treated like a bad call: nudge once within the
            // repair budget before giving up, so a recoverable turn still
            // yields a call or a plain-text answer.
            if (_repairsLeft <= 0) {
              yield const AgentStuck(kAgentCouldNotAnswer);
              return;
            }
            _repairsLeft--;
            logWarning(logSourceAgent, 'Empty turn — nudging',
                detail: 'repairs left: $_repairsLeft');
            yield* _drive(chat.send(_emptyTurnNudge));
            return;
          }
          logAction(logSourceAgent, 'Model answered in text',
              detail: _clip(answer, 400));
          yield AgentDone(answer);
          return;
      }
    }
  }

  Stream<AgentEvent> _handleCall(
    String name,
    Map<String, dynamic> args,
  ) async* {
    final String error;
    final tool = _resolve(name);
    if (tool == null) {
      error =
          "Unknown function '$name'. Use one of the listed function "
          'names exactly.';
    } else {
      try {
        final filled = fillFileArgs(tool, args, availableFiles);
        yield AgentNeedsConfirm(
          validateCall(tool, filled, fileExists: fileExists),
          step,
        );
        return;
      } on InvalidCallException catch (e) {
        error = e.message;
      }
    }
    logWarning(logSourceAgent, 'Call rejected', detail: error);
    if (_repairsLeft <= 0) {
      yield AgentStuck(error);
      return;
    }
    _repairsLeft--;
    yield* _drive(
      chat.sendToolResult(toolName: name, response: {'error': error}),
    );
  }

  /// Resolves a model-emitted function name: exact first, then a normalized
  /// match (case/separator drift), then a unique bare-slug match (the model
  /// dropping the category prefix). Returns null when nothing resolves
  /// unambiguously, which becomes the unknown-function repair.
  ToolModule? _resolve(String name) {
    final exact = _byId[name];
    if (exact != null) return exact;
    final norm = _normalizeFnName(name);
    if (norm.isEmpty) return null;
    final loose = _byNorm[norm];
    if (loose != null) {
      logWarning(logSourceAgent,
          'Resolved loose function name "$name" to ${fnNameFor(loose.meta)}');
      return loose;
    }
    ToolModule? bySlug;
    for (final e in _byId.entries) {
      final cut = e.key.indexOf('_');
      if (cut < 0) continue;
      if (_normalizeFnName(e.key.substring(cut + 1)) != norm) continue;
      if (bySlug != null) return null; // ambiguous slug: repair instead
      bySlug = e.value;
    }
    if (bySlug != null) {
      logWarning(logSourceAgent,
          'Resolved loose function name "$name" to ${fnNameFor(bySlug.meta)}');
    }
    return bySlug;
  }

  /// Continues the SAME chat after a confirmed tool failed at runtime: feeds
  /// the error back so the model can pick another function/args or answer in
  /// text. Bounded by the repair budget shared with argument repairs.
  Stream<AgentEvent> continueAfterToolError({
    required String toolName,
    required String error,
  }) {
    if (_repairsLeft <= 0) return Stream.value(AgentStuck(error));
    _repairsLeft--;
    return _drive(chat.sendToolResult(toolName: toolName, response: {
      'error': 'That tool failed: $error. Try a different function or '
          'arguments, or explain the problem in plain text.',
    }));
  }
}

/// Truncates log detail: the log table keeps a bounded number of entries, so
/// one verbose turn must not crowd out the trace around it.
String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

/// Case/separator-insensitive form of a function name.
String _normalizeFnName(String s) =>
    s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Index of [_normalizeFnName] → tool. Colliding normalizations are dropped
/// so a loose name never resolves to an arbitrary one of two tools.
Map<String, ToolModule> _normIndex(List<ToolModule> tools) {
  final out = <String, ToolModule>{};
  final dropped = <String>{};
  for (final t in tools) {
    final key = _normalizeFnName(fnNameFor(t.meta));
    if (dropped.contains(key)) continue;
    if (out.remove(key) != null) {
      dropped.add(key);
      continue;
    }
    out[key] = t;
  }
  return out;
}

String _extOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Fills a missing file/files argument of [tool] from [available] by accepted
/// extension, so the 2B model need not copy paths itself (its top failure).
/// Pure: also used by the controller to build a deterministic fallback call.
Map<String, dynamic> fillFileArgs(
  ToolModule tool,
  Map<String, dynamic> args,
  List<InputFile> available,
) {
  final meta = tool.meta;
  if (!meta.requiresInput || available.isEmpty) return args;
  final key = meta.acceptsMultiple ? 'files' : 'file';
  if (args[key] != null) return args;
  final matches = [
    for (final f in available)
      if (meta.acceptedExtensions.isEmpty ||
          meta.acceptedExtensions.contains(_extOf(f.name)))
        f.path,
  ];
  if (matches.isEmpty) return args;
  return {...args, key: meta.acceptsMultiple ? matches : matches.first};
}

/// Recovers a tool call the model emitted into the *text* channel because the
/// SDK failed to parse it.
///
/// The chat runs Gemma 4's native tool path, where flutter_gemma yields
/// structured calls parsed from `lastRawResponse`. When nothing parses there
/// the SDK falls back to handing the raw turn over as text, and the model
/// sometimes emits the OpenAI/HF chat shape —
/// `{"role":"assistant","tool_calls":[{"function":{"name","arguments"}}]}` —
/// as prose. This pulls the first call out of that wrapper (and the
/// flat/array variants) so it still executes. Returns null when [text] carries
/// no resolvable call, leaving genuine answers untouched.
({String name, Map<String, dynamic> args})? recoverLeakedToolCall(String text) {
  final decoded = _decodeJsonBlob(text);
  if (decoded == null) return null;
  return _callFrom(decoded);
}

/// Extracts and decodes the first JSON object/array embedded in [text],
/// tolerating markdown code fences and Gemma turn markers around it.
Object? _decodeJsonBlob(String text) {
  var s = text.trim();
  // Prefer a fenced block's contents when present (```json … ``` / ``` … ```).
  final fence = RegExp(r'```(?:json|tool_code)?\s*([\s\S]*?)```')
      .firstMatch(s);
  if (fence != null) s = fence.group(1)!.trim();
  final start = s.indexOf(RegExp(r'[{\[]'));
  if (start < 0) return null;
  final open = s[start];
  final end = s.lastIndexOf(open == '{' ? '}' : ']');
  if (end <= start) return null;
  try {
    return jsonDecode(s.substring(start, end + 1));
  } catch (_) {
    return null;
  }
}

/// Resolves a `(name, args)` call from any of the shapes the model produces:
/// an OpenAI `tool_calls` wrapper, a `{type:function, function:{…}}` entry, a
/// bare array of calls, or a flat `{name, arguments|parameters|args}` object.
({String name, Map<String, dynamic> args})? _callFrom(Object? node) {
  if (node is List) {
    return node.isEmpty ? null : _callFrom(node.first);
  }
  if (node is! Map) return null;
  final map = node.cast<String, dynamic>();
  final calls = map['tool_calls'];
  if (calls is List) return _callFrom(calls);
  final fn = map['function'];
  if (fn is Map) return _callFrom(fn);
  final name = map['name'];
  if (name is! String || name.isEmpty) return null;
  final rawArgs = map['arguments'] ?? map['parameters'] ?? map['args'];
  return (name: name, args: _asArgMap(rawArgs));
}

/// Coerces a call's argument payload to a string-keyed map. `arguments` is
/// often a JSON *string* in the OpenAI shape; a malformed one yields an empty
/// map rather than throwing into the event stream.
Map<String, dynamic> _asArgMap(Object? raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // fall through
    }
  }
  return <String, dynamic>{};
}
