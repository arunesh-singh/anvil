import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/ui/result/result_screen.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/progress_view.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Shared scaffold for the image editors: renders [builder] while idle and
/// mirrors [GenericToolScreen]'s running/success wiring (Stop button,
/// `JobSuccess` → [ResultScreen]) so every editor reuses `jobProvider`.
class EditorScaffold extends ConsumerWidget {
  const EditorScaffold({super.key, required this.job, required this.builder});

  final JobState job;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final job = this.job;
    if (job is JobSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ResultScreen(result: job.result)),
        );
      });
    }
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: switch (job) {
          JobRunning(:final fraction, :final message) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: ProgressView(fraction: fraction, message: message),
                    ),
                  ),
                  SecondaryButton(
                    label: 'Stop',
                    onPressed: () => ref.read(jobProvider.notifier).cancel(),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          JobSuccess() => const Center(child: CircularProgressIndicator()),
          _ => builder(context),
        },
      ),
    );
  }
}

/// The back/help header row shared by editor idle bodies.
class EditorHeader extends StatelessWidget {
  const EditorHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AnvilRadii.control),
          onTap: () => Navigator.pop(context),
          child: IconChip(
            icon: Icons.arrow_back,
            bg: c.container,
            fg: c.iconStrong,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
      ],
    );
  }
}
