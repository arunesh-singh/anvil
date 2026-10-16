/// The write-category screen (design `explorations/tools-workspace.html`,
/// frame "Rewrite"): your text, the tool's controls, Run saying what it will
/// do, and the result landing INLINE — copy, try again (pages through
/// attempts), compare with the original — instead of navigating to the
/// generic result screen. Runs still go through [jobProvider], so history,
/// keep-alive and the model gate behave like every other tool.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/input/input_picker.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/model_gate.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Tone chips for `write/tone-of-voice`: label → the `tone` value sent. The
/// last three are edits the prompt builder recognises (`toneOfVoicePrompt`).
const toneChips = <(String, String)>[
  ('Formal', 'formal'),
  ('Friendly', 'friendly'),
  ('Shorter', 'shorter'),
  ('Clearer', 'clearer'),
  ('Fix grammar', 'fix grammar'),
];

/// What Run says for [meta]: the tool's verb.
String writeRunLabel(ToolMeta meta) => switch (meta.id) {
  'translate' => 'Translate',
  'word-counter' => 'Count',
  'ai-detector' => 'Check',
  'content-summarizer' || 'summarize-youtube' => 'Summarize',
  'grammar-fixer' => 'Fix grammar',
  'explain-like-five' => 'Explain',
  'paragraph-completer' => 'Continue',
  'shorten-content' => 'Shorten',
  'content-improver' => 'Improve',
  'paraphrasing' => 'Paraphrase',
  'ai-rephraser' => 'Rephrase',
  'humanizer-ai' => 'Humanize',
  // Generators take a topic; rewriters take existing text.
  _ when _textParam(meta)?.label == 'Topic / brief' => 'Generate',
  _ => 'Rewrite',
};

ToolParam? _textParam(ToolMeta meta) =>
    meta.params.where((p) => p.key == 'text').firstOrNull;

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class WriteToolScreen extends ConsumerStatefulWidget {
  const WriteToolScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<WriteToolScreen> createState() => _WriteToolScreenState();
}

class _WriteToolScreenState extends ConsumerState<WriteToolScreen> {
  final _text = TextEditingController();
  final Map<String, TextEditingController> _fields = {};
  final Map<String, String> _choices = {};
  final Map<String, int> _ints = {};

  // tone-of-voice: a chip value, or the custom field when [_customTone].
  String _tone = toneChips.first.$2;
  bool _customTone = false;
  final _customToneCtl = TextEditingController();

  String? _fileName;

  // Inline result state.
  final List<String> _attempts = [];
  int _page = 0;
  bool _compare = false;
  String _source = '';
  ToolInput? _lastInput;
  bool _appendNext = false;

  ToolMeta get _meta => widget.tool.meta;
  bool get _isTone => _meta.id == 'tone-of-voice';

  @override
  void initState() {
    super.initState();
    for (final p in _meta.params) {
      if (p.key == 'text' || (_isTone && p.key == 'tone')) continue;
      switch (p.type) {
        case ToolParamType.integer:
          _ints[p.key] = p.defaultValue;
        case ToolParamType.choice:
          _choices[p.key] = p.defaultText;
        case ToolParamType.text:
          _fields[p.key] = TextEditingController(text: p.defaultText);
      }
    }
    _text.addListener(_refresh);
    _customToneCtl.addListener(_refresh);
    final shared = takeSharedInput(ref, _meta);
    if (shared != null) _loadFile(shared);
  }

  @override
  void dispose() {
    _text.dispose();
    _customToneCtl.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _loadFile(InputFile f) async {
    final content = await getIt<FileService>().readString(f.path);
    if (!mounted) return;
    setState(() {
      _fileName = f.name;
      _text.text = content;
    });
  }

  Future<void> _pickFile() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _meta.acceptedExtensions,
    );
    final path = f?.path;
    if (f == null || path == null) return;
    await _loadFile(InputFile(path: path, name: f.name));
  }

  String get _toneValue => _customTone ? _customToneCtl.text.trim() : _tone;

  Map<String, dynamic> _params() => {
    'text': _text.text,
    if (_isTone) 'tone': _toneValue,
    for (final e in _fields.entries) e.key: e.value.text,
    ..._choices,
    ..._ints,
  };

  bool get _canRun =>
      _text.text.trim().isNotEmpty && (!_isTone || _toneValue.isNotEmpty);

  void _start(ToolInput input, {required bool append}) {
    _appendNext = append;
    ref.read(jobProvider.notifier).start(widget.tool, input);
  }

  void _run() {
    final input = ToolInput(files: const [], params: _params());
    _lastInput = input;
    _source = _text.text.trim();
    _start(input, append: false);
  }

  void _onJob(JobState? _, JobState next) {
    if (next is! JobSuccess) return;
    final text = next.result.text ?? '';
    setState(() {
      if (!_appendNext) {
        _attempts.clear();
        _compare = false;
      }
      _attempts.add(text);
      _page = _attempts.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<JobState>(jobProvider, _onJob);
    final job = ref.watch(jobProvider);
    final c = Theme.of(context).extension<AnvilColors>()!;
    final spec = widget.tool.model;
    final gate = spec == null
        ? null
        : buildModelGate(context, ref, spec.taskId);
    final ready = modelReady(ref, spec?.taskId);
    final running = job is JobRunning;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
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
                      _meta.label,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 14, bottom: 12),
                  children: [
                    ..._inputSection(context),
                    for (final p in _meta.params)
                      if (p.key != 'text') ...[
                        const SizedBox(height: 12),
                        _param(context, p),
                      ],
                    ..._resultSection(context, job),
                  ],
                ),
              ),
              if (gate != null) ...[gate, const SizedBox(height: 12)],
              PrimaryButton(
                label: writeRunLabel(_meta),
                icon: spec == null ? Icons.arrow_forward : Icons.auto_awesome,
                onPressed: ready && !running && _canRun ? _run : null,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _inputSection(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final p = _textParam(_meta);
    return [
      TextField(
        controller: _text,
        decoration: InputDecoration(labelText: p?.label ?? 'Your text'),
        keyboardType: TextInputType.multiline,
        minLines: 6,
        maxLines: 12,
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          WsPill(
            icon: Icons.attach_file,
            label: 'Use a file',
            small: true,
            onTap: _pickFile,
          ),
          if (_fileName != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _fileName!,
                style: AnvilText.mono(12, color: c.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    ];
  }

  Widget _param(BuildContext context, ToolParam p) {
    if (_isTone && p.key == 'tone') return _toneControls(context);
    switch (p.type) {
      case ToolParamType.choice:
        final labels = [for (final v in p.choices) _capitalize(v)];
        final selected = p.choices.indexOf(_choices[p.key]!);
        void pick(int i) => setState(() => _choices[p.key] = p.choices[i]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionEyebrow(p.label),
            const SizedBox(height: 8),
            if (p.choices.length <= 4)
              WsSegmented(labels: labels, selected: selected, onChanged: pick)
            else
              WsPillRail(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    WsPill(
                      label: labels[i],
                      on: i == selected,
                      onTap: () => pick(i),
                    ),
                ],
              ),
          ],
        );
      case ToolParamType.integer:
        return StepperField(
          label: p.label,
          value: _ints[p.key]!,
          min: p.min,
          max: p.max,
          helperText: p.helperText.isEmpty ? null : p.helperText,
          onChanged: (v) => setState(() => _ints[p.key] = v),
        );
      case ToolParamType.text:
        return TextField(
          controller: _fields[p.key],
          decoration: InputDecoration(
            labelText: p.label,
            helperText: p.helperText.isEmpty ? null : p.helperText,
          ),
          minLines: p.multiline ? 3 : 1,
          maxLines: p.multiline ? 8 : 1,
        );
    }
  }

  Widget _toneControls(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WsPillRail(
        children: [
          for (final (label, value) in toneChips)
            WsPill(
              label: label,
              on: !_customTone && _tone == value,
              onTap: () => setState(() {
                _tone = value;
                _customTone = false;
              }),
            ),
          WsPill(
            icon: Icons.edit,
            label: 'Custom',
            on: _customTone,
            onTap: () => setState(() => _customTone = true),
          ),
        ],
      ),
      if (_customTone) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _customToneCtl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Custom tone',
            hintText: 'e.g. playful, apologetic, like a pirate',
          ),
        ),
      ],
    ],
  );

  List<Widget> _resultSection(BuildContext context, JobState job) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    final Widget? panel = switch (job) {
      JobRunning(:final message) => SlabPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message ?? 'Working\u2026',
                style: theme.textTheme.bodyLarge?.copyWith(color: c.muted),
              ),
            ),
            WsPill(
              icon: Icons.stop,
              label: 'Stop',
              small: true,
              onTap: () => ref.read(jobProvider.notifier).cancel(),
            ),
          ],
        ),
      ),
      _ when _attempts.isNotEmpty => _resultPanel(context),
      _ => null,
    };
    return [
      if (job is JobFailed) ...[
        const SizedBox(height: 12),
        Text(job.message, style: TextStyle(color: c.error)),
      ],
      if (panel != null) ...[const SizedBox(height: 14), panel],
    ];
  }

  Widget _resultPanel(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    final n = _attempts.length;
    final llm = widget.tool.model != null;
    void go(int delta) =>
        setState(() => _page = (_page + delta).clamp(0, n - 1));
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) go(1);
        if (v > 200) go(-1);
      },
      child: SlabPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: SectionEyebrow('Result')),
                if (n > 1) ...[
                  _arrow(Icons.chevron_left, _page > 0 ? () => go(-1) : null),
                  Text(
                    '${_page + 1} of $n',
                    style: AnvilText.mono(12, color: c.muted),
                  ),
                  _arrow(
                    Icons.chevron_right,
                    _page < n - 1 ? () => go(1) : null,
                  ),
                ],
              ],
            ),
            if (_compare) ...[
              const SizedBox(height: 8),
              Text('Original', style: AnvilText.mono(11, color: c.hint)),
              const SizedBox(height: 4),
              Text(
                _source,
                style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: c.containerHigh),
            ],
            const SizedBox(height: 8),
            SelectableText(_attempts[_page], style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                WsPill(
                  icon: Icons.content_copy,
                  label: 'Copy',
                  small: true,
                  on: true,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _attempts[_page]));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Copied')));
                  },
                ),
                if (llm && _lastInput != null)
                  WsPill(
                    icon: Icons.refresh,
                    label: 'Try again',
                    small: true,
                    onTap: () => _start(_lastInput!, append: true),
                  ),
                if (llm)
                  WsPill(
                    icon: Icons.compare_arrows,
                    label: 'Compare',
                    small: true,
                    on: _compare,
                    onTap: () => setState(() => _compare = !_compare),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _arrow(IconData icon, VoidCallback? onTap) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(AnvilRadii.chip),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? c.faint : c.iconStrong,
        ),
      ),
    );
  }
}
