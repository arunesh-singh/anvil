import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/ui/agent/chat_screen.dart';
import 'package:anvil/ui/history/history_screen.dart';
import 'package:anvil/ui/home/home_screen.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/settings/settings_screen.dart';
import 'package:anvil/ui/tokens.dart';

/// The four-tab shell (Tools / Ask / Files / Settings). Owns the single
/// [Scaffold] and the custom bottom nav; the tab bodies are Scaffold-less
/// content widgets.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final index = ref.watch(homeTabProvider);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: index,
          children: const [
            HomeScreen(),
            ChatScreen(),
            HistoryScreen(),
            SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: const _SlabBottomNav(),
    );
  }
}

class _SlabBottomNav extends ConsumerWidget {
  const _SlabBottomNav();

  static const _items = [
    (icon: Icons.handyman, label: 'Tools'),
    (icon: Icons.auto_awesome, label: 'Ask'),
    (icon: Icons.folder, label: 'Files'),
    (icon: Icons.tune, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(homeTabProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: _NavItem(
                  icon: _items[i].icon,
                  label: _items[i].label,
                  active: current == i,
                  onTap: () => ref.read(homeTabProvider.notifier).state = i,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final fg = active ? c.onSurface : c.hint;
    return Material(
      color: active ? c.container : Colors.transparent,
      borderRadius: BorderRadius.circular(AnvilRadii.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 21, color: fg),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall!
                    .copyWith(color: fg, letterSpacing: 0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
