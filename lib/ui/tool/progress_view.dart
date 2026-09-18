import 'package:flutter/material.dart';

import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Shows job progress: a circular percent ring plus a status message.
class ProgressView extends StatelessWidget {
  const ProgressView({super.key, this.fraction, this.message});

  final double? fraction;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularPercent(
          fraction: fraction,
          centerLabel: fraction == null ? '…' : '${(fraction! * 100).round()}%',
          subLabel: message,
        ),
        const SizedBox(height: 24),
        Text('Working…', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'A couple of seconds. No signal needed.',
          style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
