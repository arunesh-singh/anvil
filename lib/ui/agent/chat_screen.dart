/// Ask-tab content: a persistent multi-session chat driven by the on-device
/// assistant. Scaffold-less — the [AppShell] owns the Scaffold and bottom nav.
///
/// Assistant text and its `<think>` scratchpad stream in live; each tool step
/// the model picks runs automatically and reports its result inline — Stop
/// cancels a chain mid-flight.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/chat_repository.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/export_service.dart';
import 'package:anvil/core/share_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/ui/agent/chat_controller.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/widgets/llm_memory_panel.dart';
import 'package:anvil/ui/widgets/model_gate.dart';
import 'package:anvil/ui/widgets/slab.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    final picked = [
      for (final f in files)
        if (f.path != null) InputFile(path: f.path!, name: f.name),
    ];
    if (picked.isEmpty) return;
    ref.read(chatProvider.notifier).attach(picked);
  }

  void _send() {
    final text = _composer.text;
    if (text.trim().isEmpty) return;
    _composer.clear();
    ref.read(chatProvider.notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    final state = ref.watch(chatProvider);
    final taskId = state.current?.modelTaskId ?? ChatSession.defaultModelTaskId;
    final gate = buildModelGate(context, ref, taskId);
    final ready = modelReady(ref, taskId);

    final children = <Widget>[
      _header(context, state),
      const SizedBox(height: 16),
    ];

    if (state.messages.isEmpty &&
        state.streamingText.isEmpty &&
        state.streamingThinking.isEmpty &&
        !state.busy) {
      children.add(
        const InfoCard(
          'Ask anything, or describe a task. Attach files and Anvil reads them; '
          'it asks before running each tool step — all on this device.',
        ),
      );
    }

    for (final m in state.messages) {
      children
        ..add(const SizedBox(height: 14))
        ..add(_message(context, c, m));
    }

    // In-flight streaming bubble.
    if (state.busy ||
        state.streamingText.isNotEmpty ||
        state.streamingThinking.isNotEmpty) {
      children
        ..add(const SizedBox(height: 14))
        ..add(_streamingBubble(context, c, state));
    }

    if (state.attachments.isNotEmpty) {
      children
        ..add(const SizedBox(height: 18))
        ..add(_attachmentsPanel(context, c, state));
    }

    if (gate != null) {
      children
        ..add(const SizedBox(height: 18))
        ..add(gate);
    }

    // A composer-focus warm-up loads the model with no turn in flight: say so,
    // otherwise Send just looks dead for half a minute.
    final llm = ref.watch(llmStatusProvider).asData?.value;
    if (!state.busy && llm != null && llm.isLoading) {
      children
        ..add(const SizedBox(height: 18))
        ..add(const LlmMemoryPanel());
    }

    children
      ..add(const SizedBox(height: 18))
      ..add(
        SecondaryButton(
          label: 'Attach file',
          icon: Icons.attach_file,
          onPressed: _attach,
        ),
      )
      ..add(const SizedBox(height: 12))
      ..add(
        TextField(
          controller: _composer,
          minLines: 1,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          onTap: () => ref.read(chatProvider.notifier).warm(),
          decoration: const InputDecoration(hintText: 'Message the assistant'),
        ),
      )
      ..add(const SizedBox(height: 12))
      ..add(
        PrimaryButton(
          label: 'Send',
          icon: Icons.arrow_forward,
          onPressed: ready && !state.busy ? _send : null,
        ),
      );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      children: children,
    );
  }

  // --- Header -------------------------------------------------------------

  Widget _header(BuildContext context, ChatUiState state) {
    final theme = Theme.of(context);
    final title = state.current?.title ?? ChatSession.defaultTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionEyebrow('ASSISTANT', icon: Icons.auto_awesome),
            ),
            IconButton(
              tooltip: 'Chats',
              icon: const Icon(Icons.forum_outlined),
              onPressed: () => _openSessions(context),
            ),
            IconButton(
              tooltip: 'New chat',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: () => ref.read(chatProvider.notifier).newSession(),
            ),
            IconButton(
              tooltip: 'Model & settings',
              icon: const Icon(Icons.tune),
              onPressed: () => _openSettings(context),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(title, style: theme.textTheme.headlineSmall),
      ],
    );
  }

  // --- Sessions sheet -----------------------------------------------------

  void _openSessions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final state = ref.watch(chatProvider);
            final c = Theme.of(ctx).extension<AnvilColors>()!;
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  ToolRow(
                    icon: Icons.add_comment_outlined,
                    title: 'New chat',
                    trailing: const SizedBox.shrink(),
                    onTap: () {
                      ref.read(chatProvider.notifier).newSession();
                      Navigator.pop(ctx);
                    },
                  ),
                  for (final s in state.sessions) ...[
                    const SizedBox(height: 8),
                    ToolRow(
                      icon: s.id == state.currentId
                          ? Icons.chat
                          : Icons.chat_bubble_outline,
                      title: s.title,
                      subtitle: _relativeTime(s.updatedAt),
                      onTap: () {
                        ref.read(chatProvider.notifier).selectSession(s.id!);
                        Navigator.pop(ctx);
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: c.hint,
                            ),
                            onPressed: () => _renameDialog(ctx, ref, s),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: c.error,
                            ),
                            onPressed: () => ref
                                .read(chatProvider.notifier)
                                .deleteSession(s.id!),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _renameDialog(
    BuildContext context,
    WidgetRef ref,
    ChatSession s,
  ) async {
    final controller = TextEditingController(text: s.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(chatProvider.notifier).renameSession(s.id!, name);
    }
  }

  // --- Settings sheet -----------------------------------------------------

  void _openSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final theme = Theme.of(ctx);
            final state = ref.watch(chatProvider);
            final s = state.current;
            final chatModels =
                ref.watch(chatModelsProvider).asData?.value ?? const [];
            final temperature =
                s?.temperature ?? ChatSession.defaultTemperature;
            final topK = s?.topK ?? ChatSession.defaultTopK;
            final topP = s?.topP ?? ChatSession.defaultTopP;
            final maxOut =
                s?.maxOutputTokens ?? ChatSession.defaultMaxOutputTokens;
            final taskId = s?.modelTaskId ?? ChatSession.defaultModelTaskId;
            final notifier = ref.read(chatProvider.notifier);
            final disabled =
                s == null; // no session yet → settings apply on first send
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionEyebrow('MODEL', icon: Icons.memory),
                    const SizedBox(height: 12),
                    _modelPicker(
                      ctx,
                      chatModels,
                      taskId,
                      onChanged: disabled ? null : notifier.setModel,
                    ),
                    const SizedBox(height: 12),
                    const LlmMemoryPanel(),
                    const SizedBox(height: 20),
                    const SectionEyebrow('INFERENCE', icon: Icons.tune),
                    const SizedBox(height: 12),
                    _slider(
                      theme,
                      'Temperature',
                      temperature,
                      0.0,
                      1.0,
                      20,
                      enabled: !disabled,
                      onChangeEnd: (v) =>
                          notifier.updateSettings(temperature: v),
                    ),
                    const SizedBox(height: 8),
                    StepperField(
                      label: 'Top-K: $topK',
                      value: topK,
                      min: 1,
                      max: 64,
                      onChanged: disabled
                          ? (_) {}
                          : (v) => notifier.updateSettings(topK: v),
                    ),
                    const SizedBox(height: 8),
                    _slider(
                      theme,
                      'Top-P',
                      topP,
                      0.0,
                      1.0,
                      20,
                      enabled: !disabled,
                      onChangeEnd: (v) => notifier.updateSettings(topP: v),
                    ),
                    const SizedBox(height: 8),
                    _slider(
                      theme,
                      'Max output tokens',
                      maxOut.toDouble(),
                      128,
                      4096,
                      31,
                      enabled: !disabled,
                      onChangeEnd: (v) =>
                          notifier.updateSettings(maxOutputTokens: v.round()),
                    ),
                    if (disabled) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Send a message to start a chat, then adjust its model '
                        'and settings here.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.extension<AnvilColors>()!.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _modelPicker(
    BuildContext context,
    List<AvailableModel> models,
    String taskId, {
    required ValueChanged<String>? onChanged,
  }) {
    final theme = Theme.of(context);
    final ids = {taskId, for (final m in models) m.taskId}.toList();
    return DropdownButtonFormField<String>(
      initialValue: ids.contains(taskId) ? taskId : ids.first,
      decoration: const InputDecoration(labelText: 'Chat model'),
      items: [
        for (final id in ids)
          DropdownMenuItem(value: id, child: Text(modelTaskLabel(id))),
      ],
      onChanged: onChanged == null
          ? null
          : (v) {
              if (v != null) onChanged(v);
            },
      style: theme.textTheme.bodyLarge,
    );
  }

  Widget _slider(
    ThemeData theme,
    String label,
    double value,
    double min,
    double max,
    int divisions, {
    required bool enabled,
    required ValueChanged<double> onChangeEnd,
  }) {
    final c = theme.extension<AnvilColors>()!;
    return StatefulBuilder(
      builder: (ctx, setSheet) {
        var v = value.clamp(min, max);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
                Text(
                  v.toStringAsFixed(v >= 100 ? 0 : 2),
                  style: AnvilText.mono(13, color: c.muted),
                ),
              ],
            ),
            Slider(
              value: v,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: enabled ? (nv) => setSheet(() => v = nv) : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ],
        );
      },
    );
  }

  // --- Messages -----------------------------------------------------------

  Widget _message(BuildContext context, AnvilColors c, ChatMessage m) {
    final theme = Theme.of(context);
    switch (m.kind) {
      case ChatMessageKind.text:
        if (m.role == ChatRole.user) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: SlabPanel(
                  padding: const EdgeInsets.all(16),
                  color: c.accentContainer,
                  child: Text(
                    m.text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: c.accentText,
                    ),
                  ),
                ),
              ),
              for (final a in m.attachments) ...[
                const SizedBox(height: 6),
                _attachmentChip(context, c, a),
              ],
            ],
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: _assistantText(context, c, m.text, m.thinking),
        );
      case ChatMessageKind.toolStep:
        final path = m.outputPath;
        return ToolRow(
          icon: Icons.check,
          title: m.toolLabel ?? 'Ran a tool',
          subtitle: m.outputName,
          mono: true,
          onTap: path == null
              ? null
              : () => getIt<ExportService>().openFile(path),
          trailing: path == null
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.ios_share, size: 20),
                  onPressed: () => getIt<ShareService>().shareFiles([path]),
                ),
        );
      case ChatMessageKind.failure:
        return Text(m.text, style: TextStyle(color: c.error));
    }
  }

  Widget _assistantText(
    BuildContext context,
    AnvilColors c,
    String text,
    String? thinking,
  ) {
    final theme = Theme.of(context);
    return SlabPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thinking != null && thinking.trim().isNotEmpty)
            _thinking(context, c, thinking),
          if (text.trim().isNotEmpty)
            Text(text, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }

  Widget _thinking(BuildContext context, AnvilColors c, String thinking) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        dense: true,
        title: Text('Thinking', style: AnvilText.mono(12, color: c.hint)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(thinking, style: AnvilText.mono(12, color: c.muted)),
          ),
        ],
      ),
    );
  }

  Widget _streamingBubble(
    BuildContext context,
    AnvilColors c,
    ChatUiState state,
  ) {
    // A running tool step (stepProgress) takes priority; otherwise, before the
    // first token, a spinner over the phase we are actually in — loading a
    // multi-GB model is not "thinking", and it is the slow one.
    final progress = state.stepProgress;
    if (progress != null ||
        (state.streamingText.isEmpty && state.streamingThinking.isEmpty)) {
      final llm = ref.watch(llmStatusProvider).asData?.value;
      final String message;
      if (progress != null) {
        message = progress;
      } else if (llm != null && llm.isLoading) {
        final since = llm.since;
        final secs =
            since == null ? 0 : DateTime.now().difference(since).inSeconds;
        final label =
            llm.taskId == null ? 'the model' : modelTaskLabel(llm.taskId!);
        message = 'Loading $label\u2026 ${secs}s';
      } else if (llm != null && !llm.isLoaded) {
        message = 'Preparing the model\u2026';
      } else {
        message = 'Thinking\u2026';
      }
      return SlabPanel(
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(message)),
            _stopButton(),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _assistantText(
            context,
            c,
            state.streamingText,
            state.streamingThinking.isEmpty ? null : state.streamingThinking,
          ),
          const SizedBox(height: 8),
          _stopButton(),
        ],
      ),
    );
  }

  Widget _stopButton() => SecondaryButton(
    label: 'Stop',
    icon: Icons.stop,
    onPressed: () => ref.read(chatProvider.notifier).stop(),
  );

  // --- Attachments --------------------------------------------------------

  Widget _attachmentChip(
    BuildContext context,
    AnvilColors c,
    ChatAttachmentRef a,
  ) {
    final icon = switch (a.ingest) {
      'image' => Icons.image_outlined,
      'rejected' => Icons.block,
      _ => Icons.description_outlined,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c.hint),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            a.name,
            style: AnvilText.mono(12, color: c.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _attachmentsPanel(
    BuildContext context,
    AnvilColors c,
    ChatUiState state,
  ) {
    final theme = Theme.of(context);
    return SlabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Attached', style: theme.textTheme.titleSmall),
          for (final f in state.attachments) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(AnvilRadii.control),
              onTap: () => ref.read(chatProvider.notifier).detach(f),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      f.name,
                      style: AnvilText.mono(13, color: c.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.close, size: 18, color: c.hint),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}
