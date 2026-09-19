/// Model-availability gate shared by the tool screen and the Ask tab.
///
/// One implementation, two call sites: a model-backed surface renders
/// [buildModelGate] above its action and disables that action until
/// [modelReady].
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/models/model_manager.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Gate panel for a model-backed task id: null when the model is cached (so
/// nothing needs saying). Incompatible → a disabled "needs a more capable
/// device" panel; not-cached → an in-screen download affordance with live
/// progress.
Widget? buildModelGate(BuildContext context, WidgetRef ref, String taskId) {
  final theme = Theme.of(context);
  final c = theme.extension<AnvilColors>()!;
  final status = ref.watch(modelStatusProvider(taskId)).asData?.value;
  if (status == null) {
    return const SlabPanel(
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          SizedBox(width: 14),
          Text('Checking model\u2026'),
        ],
      ),
    );
  }
  switch (status) {
    case ModelStatus.cached:
      return null;
    case ModelStatus.incompatible:
      return SlabPanel(
        child: Row(
          children: [
            IconChip(
              icon: Icons.lock_outline,
              bg: c.container,
              fg: c.iconStrong,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'This tool needs a more capable device',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Not enough memory to run its on-device model.',
                    style:
                        theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    case ModelStatus.notCached:
      final dl = ref.watch(modelDownloadsProvider)[taskId];
      final downloading = dl?.isDownloading ?? false;
      final failed = dl?.error != null;
      int? size;
      final avail = ref.watch(availableModelsProvider).asData?.value;
      if (avail != null) {
        for (final m in avail) {
          if (m.taskId == taskId) {
            size = m.variant.sizeBytes;
            break;
          }
        }
      }
      final String title;
      if (downloading) {
        final f = dl!.fraction;
        title = f != null
            ? 'Downloading ${(f * 100).round()}%'
            : 'Downloading\u2026';
      } else if (failed) {
        title = 'Download failed \u00b7 tap to retry';
      } else {
        title = size != null
            ? 'Download model (${formatBytes(size)}) to use this tool'
            : 'Download model to use this tool';
      }
      final row = ToolRow(
        icon: failed ? Icons.refresh : Icons.download_outlined,
        title: title,
        subtitle: downloading && size != null ? formatBytes(size) : null,
        onTap: downloading
            ? null
            : () =>
                ref.read(modelDownloadsProvider.notifier).download(taskId),
        trailing: downloading
            ? SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  value: dl!.fraction,
                  color: c.accent,
                ),
              )
            : Icon(
                failed ? Icons.refresh : Icons.download_outlined,
                size: 22,
                color: failed ? c.error : c.accent,
              ),
      );
      if (downloading) return row;
      // Reuse-a-local-file path: pick a .litertlm the user downloaded
      // themselves; ModelManager.importModel verifies it against the manifest.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row,
          const SizedBox(height: 10),
          SecondaryButton(
            label: 'Import a downloaded model file',
            icon: Icons.folder_open,
            onPressed: () async {
              final files = await FilePicker.pickFiles(type: FileType.any);
              final path = files
                  .where((f) => f.path != null)
                  .map((f) => f.path!)
                  .firstOrNull;
              if (path != null) {
                ref.read(modelDownloadsProvider.notifier).import(taskId, path);
              }
            },
          ),
        ],
      );
  }
}

/// True when [taskId] is null (nothing to gate) or its model is cached.
bool modelReady(WidgetRef ref, String? taskId) =>
    taskId == null ||
    ref.watch(modelStatusProvider(taskId)).asData?.value == ModelStatus.cached;

/// Display label + glyph for a model task id — the single source used by the
/// models catalog, the chat model picker and the memory panel. Falls back to
/// the raw id for a task this build has no copy for.
({String label, IconData icon}) modelTaskInfo(String taskId) => switch (taskId) {
  'image.upscale' => (label: 'Upscale image', icon: Icons.hd),
  'image.colorize' => (label: 'Colorize', icon: Icons.palette_outlined),
  'image.deblur' => (label: 'Deblur & sharpen', icon: Icons.deblur),
  'image.inpaint' => (label: 'Object removal', icon: Icons.healing),
  'asr.transcribe' => (label: 'Transcribe audio', icon: Icons.graphic_eq),
  'agent.llm' => (label: 'Gemma 4 E2B', icon: Icons.smart_toy_outlined),
  'agent.llm.qwen' => (label: 'Qwen3 (4B / 1.7B)', icon: Icons.smart_toy_outlined),
  _ => (label: taskId, icon: Icons.memory),
};

String modelTaskLabel(String taskId) => modelTaskInfo(taskId).label;
