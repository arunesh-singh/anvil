/// Split CSV / Split Excel (design `explorations/tools-workspace.html`, frame
/// "Split CSV"): the file with its row/column count and first rows so the
/// header is confirmed, repeat-header switch, rows-per-file or number-of-files,
/// and the output (file count, last file's rows) stated before Run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/isolate_runner.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/tools/converters/converter_tools.dart';
import 'package:anvil/tools/converters/table_data.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/tool_frame.dart';
import 'package:anvil/ui/tool/input/input_picker.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// What the screen needs from a parsed table: its size and first rows.
/// Plain fields only, so it crosses the isolate boundary.
class TablePreview {
  const TablePreview(this.headers, this.firstRows, this.rowCount);

  final List<String> headers;
  final List<List<String>> firstRows;
  final int rowCount;

  factory TablePreview.of(TableData t, {int rows = 3}) =>
      TablePreview(t.headers, [
        for (var r = 0; r < t.rows.length && r < rows; r++)
          [for (var c = 0; c < t.headers.length; c++) t.cell(r, c)],
      ], t.rows.length);
}

TablePreview previewCsv(String s) => TablePreview.of(TableData.parseCsv(s));

TablePreview previewExcel(List<int> b) =>
    TablePreview.of(TableData.parseExcel(b));

// Top-level so the isolate closure captures only the file data — a closure
// built inside the State's async method would drag its unsendable context.
Future<TablePreview> _previewCsvOffThread(String s) =>
    runOffThread(() => previewCsv(s));

Future<TablePreview> _previewExcelOffThread(List<int> b) =>
    runOffThread(() => previewExcel(b));

/// `1234567` → `1,234,567`.
String groupDigits(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

String _rows(int n) => '${groupDigits(n)} ${n == 1 ? 'row' : 'rows'}';

/// The output line for a [splitPlan]: `5 files · last has 140 rows`.
String splitSummary(List<int> plan) {
  final n = plan.length;
  if (n == 1) return '1 file · ${_rows(plan.first)}';
  if (plan.last == plan.first) return '$n files · ${_rows(plan.first)} each';
  return '$n files · last has ${_rows(plan.last)}';
}

/// Run copy for a [splitPlan]: `Split into 5`.
String splitRunLabel(List<int> plan) =>
    plan.length == 1 ? 'Keep as 1 file' : 'Split into ${plan.length}';

class SplitTableScreen extends ConsumerStatefulWidget {
  const SplitTableScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<SplitTableScreen> createState() => _SplitTableScreenState();
}

class _SplitTableScreenState extends ConsumerState<SplitTableScreen> {
  InputFile? _file;
  TablePreview? _preview;
  String? _error;
  int _loadSeq = 0;

  bool _repeatHeader = true;
  bool _byFiles = false;
  late int _rowsPerFile = _defaultRows;
  int _files = 2;

  int get _defaultRows =>
      widget.tool.meta.params
          .where((p) => p.key == 'rowsPerFile')
          .firstOrNull
          ?.defaultValue ??
      100;

  bool get _isExcel => widget.tool.meta.acceptedExtensions.contains('xlsx');

  SplitSpec get _spec => SplitSpec(
    rowsPerFile: _rowsPerFile,
    files: _byFiles ? _files : 0,
    repeatHeader: _repeatHeader,
  );

  @override
  void initState() {
    super.initState();
    final shared = takeSharedInput(ref, widget.tool.meta);
    if (shared != null) _load(shared);
  }

  Future<void> _load(InputFile f) async {
    final seq = ++_loadSeq;
    setState(() {
      _file = f;
      _preview = null;
      _error = null;
    });
    try {
      final fs = getIt<FileService>();
      final preview = _isExcel
          ? await _previewExcelOffThread(await fs.readBytes(f.path))
          : await _previewCsvOffThread(await fs.readString(f.path));
      if (!mounted || seq != _loadSeq) return;
      setState(() => _preview = preview);
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(
        () => _error = e is ToolException
            ? e.message
            : 'Could not read this file as a table.',
      );
    }
  }

  void _run() {
    ref
        .read(jobProvider.notifier)
        .start(
          widget.tool,
          ToolInput(
            files: [_file!],
            params: {
              'rowsPerFile': _rowsPerFile,
              'files': _byFiles ? _files : 0,
              'header': _repeatHeader ? 'yes' : 'no',
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final plan = preview == null ? null : splitPlan(preview.rowCount, _spec);
    return ToolFrame(
      tool: widget.tool,
      hasInput: _file != null,
      onPicked: (files) => _load(files.first),
      actions: [
        WsChip(
          icon: Icons.swap_horiz,
          tooltip: 'Pick another file',
          onTap: () => setState(() {
            _loadSeq++;
            _file = null;
            _preview = null;
          }),
        ),
      ],
      runLabel: plan == null ? 'Split' : splitRunLabel(plan),
      onRun: plan == null ? null : _run,
      body: _body(context, preview, plan),
    );
  }

  Widget _body(BuildContext context, TablePreview? preview, List<int>? plan) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    final rowCount = preview?.rowCount ?? 0;
    final maxCount = rowCount < 1 ? 1 : rowCount;
    int rowStep(int v) => v > 100 ? 100 : (v > 10 ? 10 : 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filePanel(context, preview),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: c.error)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Repeat header in every file',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Switch(
              value: _repeatHeader,
              activeTrackColor: c.accent,
              onChanged: (v) => setState(() => _repeatHeader = v),
            ),
          ],
        ),
        if (!_repeatHeader)
          Text(
            'Only the first file keeps the header row.',
            style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
          ),
        const SizedBox(height: 12),
        WsSegmented(
          labels: const ['Rows per file', 'Number of files'],
          selected: _byFiles ? 1 : 0,
          onChanged: (i) => setState(() {
            final byFiles = i == 1;
            // Carry the current file count over so the output stays put.
            if (byFiles && !_byFiles && plan != null) {
              _files = plan.length < 2 ? 2.clamp(1, maxCount) : plan.length;
            }
            _byFiles = byFiles;
          }),
        ),
        const SizedBox(height: 10),
        if (_byFiles)
          StepperField(
            label: 'Number of files',
            value: _files,
            min: 1,
            max: maxCount,
            onChanged: (v) => setState(() => _files = v),
          )
        else
          StepperField(
            label: 'Rows per file',
            value: _rowsPerFile,
            min: 1,
            step: rowStep(_rowsPerFile),
            onChanged: (v) => setState(() => _rowsPerFile = v),
          ),
        if (plan != null) ...[
          const SizedBox(height: 12),
          WsEstimate(label: 'Output', value: splitSummary(plan)),
        ],
      ],
    );
  }

  Widget _filePanel(BuildContext context, TablePreview? preview) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    const maxCols = 4;
    final cols = preview == null
        ? 0
        : (preview.headers.length < maxCols ? preview.headers.length : maxCols);
    Widget cell(String s, {bool head = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Text(
        s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AnvilText.mono(
          12,
          weight: head ? FontWeight.w500 : FontWeight.w400,
          color: head ? c.accentText : c.muted,
        ),
      ),
    );
    return SlabPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AnvilRadii.panel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const IconChip(icon: Icons.table_rows),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _file?.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AnvilText.mono(14, color: c.onSurface),
                        ),
                        Text(
                          preview == null
                              ? (_error == null ? 'Reading\u2026' : '')
                              : '${_rows(preview.rowCount)} · '
                                    '${preview.headers.length} '
                                    '${preview.headers.length == 1 ? 'column' : 'columns'}',
                          style: AnvilText.mono(12, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (preview != null && cols > 0)
              Table(
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: c.accentContainer),
                    children: [
                      for (var i = 0; i < cols; i++)
                        cell(preview.headers[i], head: true),
                    ],
                  ),
                  for (final r in preview.firstRows)
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.containerHigh)),
                      ),
                      children: [for (var i = 0; i < cols; i++) cell(r[i])],
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
