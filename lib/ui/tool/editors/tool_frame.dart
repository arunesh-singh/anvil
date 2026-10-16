/// The frame every redesigned single-tool screen shares (design
/// `explorations/tools-workspace.html`, right column): header, the first-open
/// picker until a file is chosen, then "the file is the screen" — the body —
/// with Run right under the controls saying what it will do.
///
/// Wraps [EditorScaffold], so running/Stop, success → result screen, and the
/// agent hand-off completion are the same for every screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/editor_scaffold.dart';
import 'package:anvil/ui/tool/input/input_picker.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/model_gate.dart';
import 'package:anvil/ui/widgets/slab.dart';

class ToolFrame extends ConsumerWidget {
  const ToolFrame({
    super.key,
    required this.tool,
    required this.hasInput,
    required this.onPicked,
    required this.body,
    this.title,
    this.actions = const [],
    this.runLabel,
    this.runDetail,
    this.runIcon = Icons.arrow_forward,
    this.onRun,
    this.pickerPrompt,
    this.scroll = true,
  });

  final ToolModule tool;

  /// False shows the first-open picker (for tools that need an input file).
  final bool hasInput;
  final ValueChanged<List<InputFile>> onPicked;
  final Widget body;

  /// Defaults to the tool's label.
  final String? title;

  /// Trailing header chips (undo, help…).
  final List<Widget> actions;

  /// Run button copy: what it will do ("Crop", "Split into 9") plus a mono
  /// [runDetail] ("· 1814 × 1814 px").
  final String? runLabel;
  final String? runDetail;
  final IconData? runIcon;

  /// Null disables Run (nothing to do yet). Also disabled until the tool's
  /// model is ready.
  final VoidCallback? onRun;

  /// Replaces the picker's default "Pick the image." sentence.
  final String? pickerPrompt;

  /// Wrap [body] in a scroll view; screens with a flexing stage pass false.
  final bool scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobProvider);
    return EditorScaffold(
      job: job,
      builder: (context) => _idle(context, ref, job),
    );
  }

  Widget _idle(BuildContext context, WidgetRef ref, JobState job) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final spec = tool.model;
    final gate = spec == null
        ? null
        : buildModelGate(context, ref, spec.taskId);
    final ready = modelReady(ref, spec?.taskId);
    final picking = !hasInput && tool.meta.requiresInput;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              WsChip(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title ?? tool.meta.label,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!picking)
                for (final a in actions) ...[const SizedBox(width: 8), a],
            ],
          ),
          Expanded(
            child: picking
                ? ToolInputPicker(
                    tool: tool,
                    prompt: pickerPrompt,
                    onPicked: onPicked,
                    footer: gate,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: scroll
                            ? SingleChildScrollView(
                                padding: const EdgeInsets.only(top: 12),
                                child: body,
                              )
                            : Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: body,
                              ),
                      ),
                      if (job is JobFailed) ...[
                        const SizedBox(height: 12),
                        Text(job.message, style: TextStyle(color: c.error)),
                      ],
                      if (gate != null) ...[const SizedBox(height: 12), gate],
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: runLabel ?? 'Run',
                        detail: runDetail,
                        icon: runIcon,
                        onPressed: ready ? onRun : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
