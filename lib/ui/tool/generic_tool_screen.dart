import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/widgets/slab.dart';
import 'package:anvil/ui/widgets/model_gate.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/result/result_screen.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/progress_view.dart';

/// Image filter tools that show a live output preview in [GenericToolScreen].
/// Their result depends only on filter params, so running the real tool on the
/// selected file is the preview — no per-tool preview code.
const _previewImageTools = {
  'image/border',
  'image/resize',
  'image/pixelate',
  'image/compress',
  'image/grayscale',
  'image/flip',
};

bool _hasPreview(ToolModule t) => _previewImageTools.contains(t.meta.qualifiedId);

/// Default screen for any tool: pick a file, run, watch progress, see result.
///
/// Param-input rendering is intentionally absent — csv→json has no params. The
/// first parameterized tool (Phase 1) adds a params section here.
class GenericToolScreen extends ConsumerStatefulWidget {
  const GenericToolScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<GenericToolScreen> createState() => _GenericToolScreenState();
}

class _GenericToolScreenState extends ConsumerState<GenericToolScreen> {
  final List<InputFile> _selected = [];

  // Per-param text controllers, keyed by ToolParam.key, seeded with defaults.
  final Map<String, TextEditingController> _paramControllers = {};

  // Whether secondary params (after the first) are revealed.
  bool _expanded = false;

  // Live-preview state (only for tools in [_previewImageTools]).
  Timer? _previewDebounce;
  int _previewSeq = 0;
  Uint8List? _previewBytes;
  bool _previewLoading = false;
  bool _previewFailed = false;

  @override
  void initState() {
    super.initState();
    for (final p in widget.tool.meta.params) {
      _paramControllers[p.key] = TextEditingController(
        text: p.type == ToolParamType.text
            ? p.defaultText
            : p.defaultValue.toString(),
      );
    }
    if (_hasPreview(widget.tool)) {
      for (final c in _paramControllers.values) {
        c.addListener(_schedulePreview);
      }
    }
    // Pre-select a shared file if its extension matches this tool.
    final shared = ref.read(pendingSharedInputProvider);
    if (shared != null && _matches(shared)) {
      _selected.add(shared);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pendingSharedInputProvider.notifier).state = null;
        if (_hasPreview(widget.tool)) _runPreview();
      });
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    for (final c in _paramControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 300), _runPreview);
  }

  /// Runs the tool on the real selected file and shows the output. Cancels a
  /// stale run via [_previewSeq]. Never uses [jobProvider] (that navigates).
  Future<void> _runPreview() async {
    if (!_hasPreview(widget.tool) || _selected.isEmpty) return;
    final seq = ++_previewSeq;
    setState(() {
      _previewLoading = true;
      _previewFailed = false;
    });
    try {
      final events = await widget.tool
          .run(ToolInput(files: [_selected.first], params: _collectParams()))
          .toList();
      if (seq != _previewSeq || !mounted) return;
      final last = events.last;
      if (last is ToolSucceeded && last.result.files.isNotEmpty) {
        final bytes = await File(last.result.files.first.path).readAsBytes();
        if (seq != _previewSeq || !mounted) return;
        setState(() {
          _previewBytes = bytes;
          _previewLoading = false;
        });
      } else {
        setState(() {
          _previewFailed = true;
          _previewLoading = false;
        });
      }
    } catch (_) {
      if (seq != _previewSeq || !mounted) return;
      setState(() {
        _previewFailed = true;
        _previewLoading = false;
      });
    }
  }

  Map<String, dynamic> _collectParams() {
    return {
      for (final p in widget.tool.meta.params)
        p.key: p.type == ToolParamType.text
            ? _paramControllers[p.key]!.text
            : int.tryParse(_paramControllers[p.key]!.text.trim()) ??
                p.defaultValue,
    };
  }

  bool _matches(InputFile f) {
    final dot = f.name.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = f.name.substring(dot + 1).toLowerCase();
    return widget.tool.meta.acceptedExtensions.contains(ext);
  }

  Future<void> _pickFile() async {
    final List<PlatformFile> files;
    if (widget.tool.meta.acceptsMultiple) {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: widget.tool.meta.acceptedExtensions,
      );
    } else {
      final one = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: widget.tool.meta.acceptedExtensions,
      );
      files = one == null ? const [] : [one];
    }
    final picked = [
      for (final f in files)
        if (f.path != null) InputFile(path: f.path!, name: f.name),
    ];
    if (picked.isEmpty) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(picked);
    });
    if (_hasPreview(widget.tool)) _runPreview();
  }

  @override
  Widget build(BuildContext context) {
    final tool = widget.tool;
    final job = ref.watch(jobProvider);
    final c = Theme.of(context).extension<AnvilColors>()!;

    // On success, replace this screen with the result.
    if (job is JobSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ResultScreen(result: job.result)),
        );
      });
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: switch (job) {
            JobRunning(:final fraction, :final message) => Column(
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
            JobSuccess() => const Center(child: CircularProgressIndicator()),
            _ => _buildIdle(context, tool, job),
          },
        ),
      ),
    );
  }

  Widget _buildIdle(BuildContext context, ToolModule tool, JobState job) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    final params = tool.meta.params;
    final spec = tool.model;
    final Widget? gate =
        spec == null ? null : buildModelGate(context, ref, spec.taskId);
    final ready = modelReady(ref, spec?.taskId);
    return ListView(
      children: [
        const SizedBox(height: 8),
        Row(
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
            const Spacer(),
            IconChip(
              icon: Icons.help_outline,
              bg: c.container,
              fg: c.iconStrong,
            ),
          ],
        ),
        const SizedBox(height: 22),
        IconChip(icon: tool.meta.icon, box: 52, glyph: 26),
        const SizedBox(height: 16),
        Text(tool.meta.label, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          tool.meta.description,
          style: theme.textTheme.bodyLarge?.copyWith(color: c.muted),
        ),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 22),
          SlabPanel(
            child: Text(
              _selected.map((f) => f.name).join(', '),
              style: AnvilText.mono(14, color: c.onSurface),
            ),
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Swap',
            icon: Icons.swap_horiz,
            onPressed: _pickFile,
          ),
        ] else if (tool.meta.requiresInput) ...[
          const SizedBox(height: 22),
          InkWell(
            borderRadius: BorderRadius.circular(AnvilRadii.panel),
            onTap: _pickFile,
            child: SlabPanel(
              child: Row(
                children: [
                  IconChip(icon: Icons.attach_file),
                  const SizedBox(width: 14),
                  Text(
                    tool.meta.acceptsMultiple ? 'Pick files' : 'Pick file',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_hasPreview(tool) && _selected.isNotEmpty) ...[
          const SizedBox(height: 22),
          _previewCard(context),
        ],
        if (params.isNotEmpty) ...[
          const SizedBox(height: 22),
          _paramField(context, params.first),
          if (params.length > 1) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(AnvilRadii.row),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Text('More options', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: c.hint,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              ...[
                for (final p in params.skip(1)) ...[
                  _paramField(context, p),
                  const SizedBox(height: 8),
                ],
              ],
          ],
        ],
        if (job is JobFailed) ...[
          const SizedBox(height: 16),
          Text(job.message, style: TextStyle(color: c.error)),
        ],
        if (gate != null) ...[
          const SizedBox(height: 16),
          gate,
        ],
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Run',
          icon: Icons.arrow_forward,
          onPressed: (_selected.isEmpty && tool.meta.requiresInput) || !ready
              ? null
              : () => ref.read(jobProvider.notifier).start(
                  tool,
                  ToolInput(files: List.of(_selected), params: _collectParams()),
                ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _paramField(BuildContext context, ToolParam p) {
    if (p.type == ToolParamType.integer) {
      final value =
          int.tryParse(_paramControllers[p.key]!.text.trim()) ?? p.defaultValue;
      return StepperField(
        label: p.label,
        value: value,
        min: p.min,
        max: p.max,
        helperText: p.helperText.isEmpty ? null : p.helperText,
        onChanged: (v) =>
            setState(() => _paramControllers[p.key]!.text = v.toString()),
      );
    }
    return TextField(
      controller: _paramControllers[p.key],
      decoration: InputDecoration(labelText: p.label),
      keyboardType: p.multiline ? TextInputType.multiline : null,
      minLines: p.multiline ? 5 : 1,
      maxLines: p.multiline ? 10 : 1,
    );
  }

  Widget _previewCard(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    return SlabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Preview', style: theme.textTheme.titleSmall),
              const Spacer(),
              if (_previewLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AnvilRadii.control),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: _previewBytes != null
                  ? Image.memory(
                      _previewBytes!,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                    )
                  : const SizedBox(height: 120),
            ),
          ),
          if (_previewFailed) ...[
            const SizedBox(height: 8),
            Text('Preview unavailable',
                style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
          ],
        ],
      ),
    );
  }
}
