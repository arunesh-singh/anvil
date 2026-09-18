import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/tool_screen.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Category listing pushed from Home's "Browse the bench" rows. Owns its own
/// [Scaffold]; a local filter field replaces the mock's sub-category chips
/// (no sub-category taxonomy exists in [ToolMeta]).
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key, required this.category});

  final ToolCategory category;

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final tools = getIt<ToolRegistry>().byCategory(widget.category);
    final label = categoryLabel(widget.category);

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? tools
        : tools
            .where((t) =>
                t.meta.label.toLowerCase().contains(q) ||
                t.meta.description.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(AnvilRadii.control),
                    onTap: () => Navigator.pop(context),
                    child: IconChip(
                      icon: Icons.arrow_back,
                      box: 40,
                      glyph: 21,
                      bg: c.container,
                      fg: c.iconStrong,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: text.titleLarge),
                        Text(
                          '${tools.length} tools, all on-device',
                          style: text.bodyMedium?.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Filter $label tools',
                  prefixIcon: Icon(Icons.search, color: c.hint),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No tools match.'))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final t = filtered[i];
                          return ToolRow(
                            icon: t.meta.icon,
                            title: t.meta.label,
                            subtitle: t.meta.description,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => toolScreenFor(t),
                              ),
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
