import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/browse/browse_screen.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/result/result_screen.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/tool_screen.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Tools-tab content ("Your bench"): search, resume card, contextual
/// suggestions, and category browse rows. Scaffold-less — the [AppShell] owns
/// the Scaffold and bottom nav.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final query = ref.watch(searchQueryProvider).trim();
    final shared = ref.watch(pendingSharedInputProvider);

    final children = <Widget>[
      Row(
        children: [
          Text('Your bench', style: text.headlineSmall),
          const Spacer(),
          _OfflineChip(),
        ],
      ),
    ];

    if (shared != null) {
      children.add(const SizedBox(height: 16));
      children.add(_SharedBanner(shared: shared));
    }

    children.add(const SizedBox(height: 16));
    children.add(
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search 218 tools',
        ),
        onChanged: (v) => ref.read(searchQueryProvider.notifier).state = v,
      ),
    );
    children.add(const SizedBox(height: 22));

    if (query.isNotEmpty) {
      children.add(_buildResults(context, ref));
    } else {
      children.addAll(_buildBench(context, ref, c, text));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      children: children,
    );
  }

  Widget _buildResults(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(filteredToolsProvider);
    if (tools.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: Text('No tools match.')),
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < tools.length; i++) {
      if (i > 0) rows.add(const SizedBox(height: 8));
      final t = tools[i];
      rows.add(
        ToolRow(
          icon: t.meta.icon,
          title: t.meta.label,
          subtitle: t.meta.description,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => toolScreenFor(t)),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  List<Widget> _buildBench(
    BuildContext context,
    WidgetRef ref,
    AnvilColors c,
    TextTheme text,
  ) {
    final registry = ref.watch(registryProvider);
    final record = ref.watch(resumeProvider);
    final suggestions = ref.watch(suggestionsProvider);
    final sections = <Widget>[];

    ToolModule? resumeTool;
    if (record != null) {
      resumeTool = getIt<ToolRegistry>().byId(record.toolId);
    }

    if (record != null && resumeTool != null) {
      final rt = resumeTool;
      sections.add(
        SlabPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionEyebrow(
                'PICK UP WHERE YOU LEFT OFF',
                icon: Icons.history,
                color: c.accentText,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconChip(icon: rt.meta.icon, box: 44, glyph: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rt.meta.label, style: text.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          '${record.inputNames.join(', ')} → '
                          '${record.outputPaths.length} files',
                          style: AnvilText.mono(12, color: c.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: 'Run it again',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => toolScreenFor(rt),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SecondaryButton(
                    label: 'Results',
                    onPressed: () => openResult(context, record.outputPaths),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (suggestions.isNotEmpty && resumeTool != null) {
      if (sections.isNotEmpty) sections.add(const SizedBox(height: 22));
      final subs = <Widget>[
        Text(
          'Because you opened ${categoryLabel(resumeTool.meta.category)}',
          style: text.titleSmall,
        ),
        const SizedBox(height: 12),
      ];
      for (var i = 0; i < suggestions.length; i++) {
        if (i > 0) subs.add(const SizedBox(height: 8));
        final s = suggestions[i];
        subs.add(
          ToolRow(
            icon: s.meta.icon,
            title: s.meta.label,
            subtitle: s.meta.description,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => toolScreenFor(s)),
            ),
          ),
        );
      }
      sections.add(
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: subs),
      );
    }

    if (sections.isNotEmpty) sections.add(const SizedBox(height: 22));
    final browse = <Widget>[
      Text('Browse the bench', style: text.titleSmall),
      const SizedBox(height: 12),
    ];
    for (var i = 0; i < kCategoryOrder.length; i++) {
      if (i > 0) browse.add(const SizedBox(height: 8));
      final cat = kCategoryOrder[i];
      final count = registry.where((t) => t.meta.category == cat).length;
      browse.add(
        ToolRow(
          icon: categoryIcon(cat),
          title: categoryLabel(cat),
          trailing: Text('$count', style: AnvilText.mono(13, color: c.hint)),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BrowseScreen(category: cat)),
          ),
        ),
      );
    }
    sections.add(
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: browse),
    );

    return sections;
  }
}

/// Bolt + "OFFLINE" pill shown in the bench header.
class _OfflineChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.container,
        borderRadius: BorderRadius.circular(AnvilRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 14, color: c.accent),
          const SizedBox(width: 6),
          Text(
            'OFFLINE',
            style: text.labelSmall?.copyWith(
              color: c.muted,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Restyled banner announcing a file received via share intent.
class _SharedBanner extends ConsumerWidget {
  const _SharedBanner({required this.shared});

  final InputFile shared;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return SlabPanel(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Icon(Icons.attach_file, color: c.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Shared file ready: ${shared.name} — pick a tool'),
          ),
          TextButton(
            onPressed: () =>
                ref.read(pendingSharedInputProvider.notifier).state = null,
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}
