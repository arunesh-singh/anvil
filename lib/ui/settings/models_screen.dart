import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/models/model_manager.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Browsable model catalog: lists every curated model with its size and
/// on-device state, and lets the user download or remove each one. Pushed via
/// [MaterialPageRoute]; owns its own [Scaffold].
class ModelsScreen extends ConsumerWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final totalBytes = ref.watch(cacheBytesProvider);
    final catalog = ref.watch(availableModelsProvider);
    final downloads = ref.watch(modelDownloadsProvider);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(AnvilRadii.control),
                    child: IconChip(
                      icon: Icons.arrow_back,
                      bg: c.container,
                      fg: c.iconStrong,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text('Models', style: text.titleLarge),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Downloaded once, then used offline. Tap to fetch a model; '
                'remove any to free space.',
                style: text.bodyMedium!.copyWith(color: c.muted),
              ),
              const SizedBox(height: 18),
              totalBytes.maybeWhen(
                data: (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Storage used: ${b > 0 ? formatBytes(b) : 'None yet'}',
                    style: text.bodyMedium!.copyWith(color: c.muted),
                  ),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              Expanded(
                child: catalog.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text(
                      'Could not load the model catalog:\n$e',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium!.copyWith(color: c.muted),
                    ),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return Center(
                        child: Text(
                          'No models available.',
                          style: text.bodyLarge!.copyWith(color: c.muted),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 20),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _ModelCatalogRow(
                        model: list[i],
                        download: downloads[list[i].taskId],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One catalog entry with a state-dependent trailing action.
class _ModelCatalogRow extends ConsumerWidget {
  const _ModelCatalogRow({required this.model, required this.download});

  final AvailableModel model;
  final ModelDownloadState? download;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final info = _taskInfo(model.taskId);
    final v = model.variant;
    final downloading = download?.isDownloading ?? false;
    final failed = download?.error != null;

    final String subtitle;
    if (downloading) {
      final f = download!.fraction;
      subtitle = f != null
          ? 'Downloading ${(f * 100).round()}% of ${formatBytes(v.sizeBytes)}'
          : 'Downloading ${formatBytes(v.sizeBytes)}\u2026';
    } else if (failed) {
      subtitle = 'Download failed \u00b7 tap to retry';
    } else if (model.cached) {
      subtitle = '${v.id} \u00b7 ${formatBytes(v.sizeBytes)} \u00b7 Downloaded';
    } else if (!model.compatible) {
      subtitle =
          'Needs more memory (${v.minRamGb} GB) \u00b7 ${formatBytes(v.sizeBytes)}';
    } else {
      subtitle = '${v.id} \u00b7 ${formatBytes(v.sizeBytes)}';
    }

    final enabled = !downloading && (model.compatible || model.cached);

    return ToolRow(
      icon: info.icon,
      title: info.label,
      subtitle: subtitle,
      mono: model.cached && !downloading && !failed,
      onTap: enabled
          ? () {
              if (model.cached) return;
              ref.read(modelDownloadsProvider.notifier).download(model.taskId);
            }
          : null,
      trailing: _trailing(context, ref, c, downloading, failed),
    );
  }

  Widget _trailing(
    BuildContext context,
    WidgetRef ref,
    AnvilColors c,
    bool downloading,
    bool failed,
  ) {
    if (downloading) {
      return SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          value: download!.fraction,
          color: c.accent,
        ),
      );
    }
    if (failed) {
      return IconButton(
        icon: Icon(Icons.refresh, color: c.error),
        tooltip: download!.error,
        onPressed: () =>
            ref.read(modelDownloadsProvider.notifier).download(model.taskId),
      );
    }
    if (model.cached) {
      return IconButton(
        icon: Icon(Icons.delete_outline, color: c.hint),
        tooltip: 'Remove',
        onPressed: () async {
          await getIt<ModelManager>().evict(model.taskId);
          ref.invalidate(availableModelsProvider);
          ref.invalidate(cachedModelsProvider);
          ref.invalidate(cacheBytesProvider);
        },
      );
    }
    if (!model.compatible) {
      return Icon(Icons.lock_outline, size: 20, color: c.hint);
    }
    return Icon(Icons.download_outlined, size: 22, color: c.accent);
  }
}

/// Display label + glyph for a model task id. Falls back to the raw id.
({String label, IconData icon}) _taskInfo(String taskId) => switch (taskId) {
      'image.upscale' => (label: 'Upscale image', icon: Icons.hd),
      'image.colorize' => (label: 'Colorize', icon: Icons.palette_outlined),
      'image.deblur' => (label: 'Deblur & sharpen', icon: Icons.deblur),
      'image.inpaint' => (label: 'Object removal', icon: Icons.healing),
      'asr.transcribe' => (label: 'Transcribe audio', icon: Icons.graphic_eq),
      'agent.llm' => (label: 'Assistant (Gemma 4)', icon: Icons.smart_toy_outlined),
      'agent.llm.qwen' => (label: 'Assistant (Qwen3)', icon: Icons.smart_toy_outlined),
      _ => (label: taskId, icon: Icons.memory),
    };
