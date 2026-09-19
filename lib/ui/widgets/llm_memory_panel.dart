/// What the language model is doing to this device's memory right now:
/// coming up, resident (with an Unload action), or absent.
///
/// A `.litertlm` model is 1–4 GB of RAM and takes tens of seconds to map and
/// build its GPU kernels. That load used to happen behind a silent screen —
/// this panel is the visible half of [LlmEngine]'s status stream, and the
/// only way to hand the memory back without killing the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/engines/llm_engine.dart';
import 'package:anvil/ui/agent/chat_controller.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/widgets/model_gate.dart';
import 'package:anvil/ui/widgets/slab.dart';

class LlmMemoryPanel extends ConsumerStatefulWidget {
  const LlmMemoryPanel({super.key});

  @override
  ConsumerState<LlmMemoryPanel> createState() => _LlmMemoryPanelState();
}

class _LlmMemoryPanelState extends ConsumerState<LlmMemoryPanel> {
  bool _unloading = false;

  Future<void> _unload() async {
    setState(() => _unloading = true);
    try {
      await ref.read(chatProvider.notifier).unloadModel();
    } finally {
      if (mounted) setState(() => _unloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    // llmStatusProvider re-emits every second while loading, so the elapsed
    // counter below advances without a widget-local ticker.
    final status = ref.watch(llmStatusProvider).asData?.value ??
        const LlmStatus(LlmPhase.unloaded);

    final taskId = status.taskId;
    final label = taskId == null ? 'The model' : modelTaskLabel(taskId);

    if (status.isLoading) {
      final since = status.since;
      final secs = since == null ? 0 : DateTime.now().difference(since).inSeconds;
      return SlabPanel(
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Loading $label\u2026 ${secs}s',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    'First load maps the weights and builds GPU kernels. '
                    'Later messages reuse it.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (!status.isLoaded) {
      return SlabPanel(
        child: Row(
          children: [
            IconChip(
              icon: Icons.memory,
              bg: c.container,
              fg: c.iconStrong,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'No model in memory. The next message loads one.',
                style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
              ),
            ),
          ],
        ),
      );
    }

    final size = _sizeOf(taskId);
    return SlabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconChip(
                icon: Icons.memory,
                bg: c.accentContainer,
                fg: c.accentText,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$label is in memory',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      size == null
                          ? 'Kept loaded so the next message answers instantly.'
                          : 'About ${formatBytes(size)} of RAM, kept loaded so '
                              'the next message answers instantly.',
                      style:
                          theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            label: _unloading ? 'Unloading\u2026' : 'Unload model',
            icon: Icons.eject_outlined,
            onPressed: _unloading ? null : _unload,
          ),
        ],
      ),
    );
  }

  /// On-disk size of the loaded variant ≈ its resident footprint.
  int? _sizeOf(String? taskId) {
    if (taskId == null) return null;
    final catalog = ref.watch(availableModelsProvider).asData?.value;
    if (catalog == null) return null;
    for (final m in catalog) {
      if (m.taskId == taskId) return m.variant.sizeBytes;
    }
    return null;
  }
}
