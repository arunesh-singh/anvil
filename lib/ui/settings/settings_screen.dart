import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/settings/log_screen.dart';
import 'package:anvil/ui/settings/models_screen.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Settings-tab content: appearance, file retention, clear-all, the
/// downloaded-models entry, diagnostics and licenses. Rendered inside
/// [AppShell]; has no [Scaffold].
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _retentionLabels = <int, String>{
    7: '7 days',
    30: '30 days',
    90: '90 days',
    0: 'Forever',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final mode = ref.watch(themeModeProvider);
    final retention = ref.watch(retentionProvider);
    final cacheBytes = ref.watch(cacheBytesProvider);
    final counts = ref.watch(logCountsProvider);
    final version = ref.watch(appVersionProvider).asData?.value;
    // "1.0.0-rc.2 (5)" once resolved; the platform read is near-instant, so the
    // brief null renders as a bare name.
    final versionLabel = version == null
        ? null
        : '${version.version} (${version.build})';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 20),
        children: [
          Text('Settings', style: text.headlineSmall),
          const SizedBox(height: 22),
          const SectionEyebrow('APPEARANCE'),
          const SizedBox(height: 12),
          _AppearanceControl(
            mode: mode,
            onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
          ),
          const SizedBox(height: 22),
          const SectionEyebrow('FILES'),
          const SizedBox(height: 12),
          ToolRow(
            icon: Icons.schedule,
            title: 'Keep results for',
            subtitle: 'Older files clear themselves out.',
            trailing: _ValueChip(_retentionLabels[retention] ?? '$retention days'),
            onTap: () => _pickRetention(context, ref, retention),
          ),
          const SizedBox(height: 8),
          ToolRow(
            icon: Icons.delete_outline,
            title: 'Clear everything now',
            subtitle: 'Deletes every saved output on this phone.',
            onTap: () => _confirmClear(context, ref),
          ),
          const SizedBox(height: 8),
          ToolRow(
            icon: Icons.memory,
            title: 'Models',
            subtitle: cacheBytes.maybeWhen(
              data: (b) => b > 0 ? '${formatBytes(b)} downloaded' : 'Browse & download',
              orElse: () => '\u2026',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ModelsScreen()),
            ),
          ),
          const SizedBox(height: 22),
          const SectionEyebrow('DIAGNOSTICS'),
          const SizedBox(height: 12),
          ToolRow(
            icon: Icons.receipt_long,
            title: 'App log',
            subtitle: counts.maybeWhen(
              data: (n) => n.total == 0
                  ? 'Nothing logged yet'
                  : '${n.total} events \u00b7 ${n.errors} error'
                      '${n.errors == 1 ? '' : 's'}',
              orElse: () => '\u2026',
            ),
            trailing: counts.asData?.value.errors != null &&
                    counts.asData!.value.errors > 0
                ? _ValueChip('${counts.asData!.value.errors}')
                : null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LogScreen()),
            ),
          ),
          const SizedBox(height: 22),
          const SectionEyebrow('ABOUT'),
          const SizedBox(height: 12),
          ToolRow(
            icon: Icons.balance,
            title: 'Open-source licenses',
            subtitle: 'FFmpeg, ML Kit, ONNX Runtime, Gemma and more.',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Anvil',
              applicationVersion: versionLabel,
            ),
          ),
          const SizedBox(height: 22),
          SlabPanel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconChip(icon: Icons.bolt),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Everything runs on this phone.',
                          style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'No uploads, no accounts, no per-use fees. '
                        'Works in aeroplane mode.',
                        style: text.bodyMedium!.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: Text(
              'Anvil${versionLabel == null ? '' : ' $versionLabel'} '
              '\u00b7 ${getIt<ToolRegistry>().all.length} tools installed',
              style: AnvilText.mono(12, color: c.faintMono),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRetention(
      BuildContext context, WidgetRef ref, int current) async {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: c.container,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AnvilRadii.panel)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in _retentionLabels.entries)
              ListTile(
                title: Text(entry.value, style: text.titleSmall),
                trailing: entry.key == current
                    ? Icon(Icons.check, color: c.accentText)
                    : null,
                onTap: () => Navigator.pop(sheetContext, entry.key),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      ref.read(retentionProvider.notifier).set(picked);
    }
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all results?'),
        content:
            const Text('This deletes every saved output on this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await getIt<HistoryRepository>().clear();
    await getIt<FileService>().clearOutputs();
    logWarning(logSourceApp, 'User cleared every saved output');
    ref.invalidate(historyProvider);
    ref.invalidate(cachedModelsProvider);
    ref.invalidate(cacheBytesProvider);
    ref.invalidate(logCountsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cleared.')));
    }
  }
}

/// Three-cell System/Light/Dark segmented control on a [AnvilColors.container]
/// track. The active cell fills with [AnvilColors.accent].
class _AppearanceControl extends StatelessWidget {
  const _AppearanceControl({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).extension<AnvilColors>()!.container,
        borderRadius: BorderRadius.circular(AnvilRadii.panel),
      ),
      child: Row(
        children: [
          _cell(context, 'System', ThemeMode.system),
          _cell(context, 'Light', ThemeMode.light),
          _cell(context, 'Dark', ThemeMode.dark),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, String label, ThemeMode value) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final active = mode == value;
    return Expanded(
      child: Material(
        color: active ? c.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(value),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            child: Text(
              label,
              style: text.titleSmall!
                  .copyWith(color: active ? c.onAccent : c.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small rounded value chip used as a [ToolRow] trailing.
class _ValueChip extends StatelessWidget {
  const _ValueChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.containerHigh,
        borderRadius: BorderRadius.circular(AnvilRadii.chip),
      ),
      child: Text(
        label,
        style: text.titleSmall!.copyWith(color: c.onSurface),
      ),
    );
  }
}
