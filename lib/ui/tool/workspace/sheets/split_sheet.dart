/// Split op: export the document as several files of N pages each. A
/// document-level edit — applying again replaces the previous split.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/workspace/workspace_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

class SplitSheet extends ConsumerStatefulWidget {
  const SplitSheet({super.key});

  @override
  ConsumerState<SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<SplitSheet> {
  late int _every = ref.read(pdfWorkspaceProvider).doc.split?.every ?? 1;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final alive = ref.watch(pdfWorkspaceProvider).doc.order.length;
    final max = alive - 1 < 1 ? 1 : alive - 1;
    final every = _every.clamp(1, max);
    final files = splitFileCount(alive, every);
    return WsSheetFrame(
      title: 'Split',
      sub: '→ $files files',
      children: [
        StepperField(
          label: 'Every N pages',
          value: every,
          min: 1,
          max: max,
          color: c.containerHigh,
          onChanged: (v) => setState(() => _every = v),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Split into $files files',
          icon: Icons.check,
          onPressed: alive < 2
              ? null
              : () {
                  ref
                      .read(pdfWorkspaceProvider.notifier)
                      .replaceSingleton(SplitEdit(every));
                  Navigator.pop(context);
                },
        ),
      ],
    );
  }
}
