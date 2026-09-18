import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/history_repository.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/result/result_screen.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// "Your files": past tool runs grouped by recency, newest first. Rendered as
/// Files-tab content inside [AppShell] — no Scaffold of its own.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final history = ref.watch(historyProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Could not load history: $e',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
        ),
        data: (records) => records.isEmpty
            ? _EmptyState(
                onFind: () => ref.read(homeTabProvider.notifier).state = 0,
              )
            : _RecordList(records: records),
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({required this.records});

  final List<HistoryRecord> records;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final week = <HistoryRecord>[];
    final earlier = <HistoryRecord>[];
    for (final r in records) {
      if (now.difference(r.createdAt).inDays < 7) {
        week.add(r);
      } else {
        earlier.add(r);
      }
    }

    final children = <Widget>[
      Text('Your files', style: text.headlineSmall),
      const SizedBox(height: 4),
      Text(
        'Everything you\u2019ve made, newest first.',
        style: text.bodyMedium?.copyWith(color: c.muted),
      ),
      const SizedBox(height: 22),
    ];

    void addGroup(String label, List<HistoryRecord> group) {
      if (group.isEmpty) return;
      if (children.length > 4) children.add(const SizedBox(height: 22));
      children.add(SectionEyebrow(label));
      for (final r in group) {
        children.add(const SizedBox(height: 8));
        children.add(_recordRow(context, r));
      }
    }

    addGroup('THIS WEEK', week);
    addGroup('EARLIER', earlier);

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: children,
    );
  }

  Widget _recordRow(BuildContext context, HistoryRecord r) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final tool = getIt<ToolRegistry>().byId(r.toolId);
    return ToolRow(
      icon: tool?.meta.icon ?? Icons.history,
      title: tool?.meta.label ?? r.toolId,
      subtitle: r.inputNames.join(', '),
      mono: true,
      trailing: Text(
        _shortDate(r.createdAt),
        style: text.bodyMedium?.copyWith(color: c.muted),
      ),
      onTap: () => openResult(context, r.outputPaths),
    );
  }

  static const _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _shortDate(DateTime d) {
    final now = DateTime.now();
    if (now.difference(d).inDays < 7) {
      return _weekdays[d.weekday - 1];
    }
    return '${_months[d.month - 1]} ${d.day}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onFind});

  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your files', style: text.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Everything you\u2019ve made, newest first.',
                style: text.bodyMedium?.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_open, size: 64, color: c.faint),
                const SizedBox(height: 22),
                Text('Nothing on the shelf yet', style: text.titleLarge),
                const SizedBox(height: 10),
                Text(
                  'Whatever you make lands here, and stays on this phone.',
                  style: text.bodyLarge?.copyWith(color: c.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                PrimaryButton(
                  label: 'Find something to do',
                  onPressed: onFind,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
