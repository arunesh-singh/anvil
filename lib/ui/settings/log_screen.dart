import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/app_log.dart';
import 'package:anvil/core/di.dart';
import 'package:anvil/core/export_service.dart';
import 'package:anvil/core/log_repository.dart';
import 'package:anvil/core/share_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// The app log: every action the app took and every failure it surfaced, with
/// an errors-only filter and a plain-text export. Pushed via
/// [MaterialPageRoute]; owns its own [Scaffold].
class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  bool _errorsOnly = false;
  final Set<int> _expanded = {};
  bool _working = false;

  Future<void> _export({required bool save}) async {
    if (_working) return;
    setState(() => _working = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final OutputFile file = await exportLog();
      if (save) {
        final saved =
            await getIt<ExportService>().saveToDevice(file.name, file.path);
        messenger.showSnackBar(SnackBar(
          content: Text(saved != null ? 'Saved ${file.name}' : 'Cancelled.'),
        ));
      } else {
        await getIt<ShareService>().shareFiles([file.path]);
      }
    } on ToolException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export the log: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear the app log?'),
        content: const Text('This deletes every recorded action and error.'),
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
    await getIt<LogRepository>().clear();
    _expanded.clear();
    ref.invalidate(logEntriesProvider);
    ref.invalidate(logCountsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final entries = ref.watch(logEntriesProvider);

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
                  Text('App log', style: text.titleLarge),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: Icon(Icons.refresh, color: c.hint),
                    onPressed: () {
                      ref.invalidate(logEntriesProvider);
                      ref.invalidate(logCountsProvider);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Everything Anvil did on this phone, newest first. Tap a row '
                'for detail; export it if something needs reporting.',
                style: text.bodyMedium!.copyWith(color: c.muted),
              ),
              const SizedBox(height: 14),
              _FilterToggle(
                errorsOnly: _errorsOnly,
                onChanged: (v) => setState(() => _errorsOnly = v),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: entries.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text(
                      'Could not read the log:\n$e',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium!.copyWith(color: c.muted),
                    ),
                  ),
                  data: (all) {
                    final list = _errorsOnly
                        ? [
                            for (final e in all)
                              if (e.level == LogLevel.error) e,
                          ]
                        : all;
                    if (list.isEmpty) {
                      return Center(
                        child: Text(
                          _errorsOnly
                              ? 'No errors recorded. '
                              : 'Nothing logged yet.',
                          style: text.bodyLarge!.copyWith(color: c.muted),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final entry = list[i];
                        final key = entry.id ?? i;
                        return _LogRow(
                          entry: entry,
                          expanded: _expanded.contains(key),
                          onTap: () => setState(() {
                            if (!_expanded.remove(key)) _expanded.add(key);
                          }),
                        );
                      },
                    );
                  },
                ),
              ),
              PrimaryButton(
                label: _working ? 'Exporting\u2026' : 'Export log',
                icon: Icons.ios_share,
                onPressed: _working ? null : () => _export(save: false),
              ),
              const SizedBox(height: 8),
              SecondaryButton(
                label: 'Save to device',
                icon: Icons.save_alt,
                onPressed: _working ? null : () => _export(save: true),
              ),
              const SizedBox(height: 8),
              SecondaryButton(
                label: 'Clear log',
                icon: Icons.delete_outline,
                onPressed: _clear,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-cell All / Errors track, mirroring the appearance control in Settings.
class _FilterToggle extends StatelessWidget {
  const _FilterToggle({required this.errorsOnly, required this.onChanged});

  final bool errorsOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.container,
        borderRadius: BorderRadius.circular(AnvilRadii.control),
      ),
      child: Row(
        children: [
          _cell(context, 'All actions', false),
          _cell(context, 'Errors only', true),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, String label, bool value) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final active = errorsOnly == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AnvilRadii.control),
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(AnvilRadii.control),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  color: active ? c.onAccent : c.muted,
                ),
          ),
        ),
      ),
    );
  }
}

/// One log line: level dot, mono timestamp + source, message, optional detail.
class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.entry,
    required this.expanded,
    required this.onTap,
  });

  final LogEntry entry;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final colour = switch (entry.level) {
      LogLevel.info => c.hint,
      LogLevel.warn => c.accent,
      LogLevel.error => c.error,
    };
    final hasDetail = entry.detail != null && entry.detail!.trim().isNotEmpty;
    return Material(
      color: c.container,
      borderRadius: BorderRadius.circular(AnvilRadii.row),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasDetail ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 6),
                    decoration:
                        BoxDecoration(color: colour, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.message, style: text.titleSmall),
                        const SizedBox(height: 3),
                        Text(
                          '${_time(entry.at)} \u00b7 ${entry.source}',
                          style: AnvilText.mono(12, color: c.faintMono),
                        ),
                      ],
                    ),
                  ),
                  if (hasDetail)
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: c.hint,
                    ),
                ],
              ),
              if (expanded && hasDetail) ...[
                const SizedBox(height: 10),
                SelectableText(
                  entry.detail!.trimRight(),
                  style: AnvilText.mono(12, color: c.muted, height: 17 / 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)} '
        '${two(t.day)}/${two(t.month)}';
  }
}
