import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/export_service.dart';
import 'package:anvil/core/share_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Builds a [ToolResult] from persisted [outputPaths] and pushes [ResultScreen],
/// or shows a snackbar when the files are gone. Shared by Home resume and Files.
Future<void> openResult(BuildContext context, List<String> outputPaths) async {
  final missing = outputPaths.any((path) => !File(path).existsSync());
  if (missing) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Output file no longer available.')),
    );
    return;
  }
  final result = ToolResult(
    files: [
      for (final path in outputPaths)
        OutputFile(path: path, name: p.basename(path)),
    ],
  );
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
  );
}

/// Shows a finished tool result with open / save / share / done actions.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.result});

  final ToolResult result;

  Future<void> _open(BuildContext context, OutputFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await getIt<ExportService>().openFile(f.path);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open: $error')));
    }
  }

  Future<void> _save(BuildContext context, OutputFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await getIt<ExportService>().saveToDevice(f.name, f.path);
    if (saved != null) {
      messenger.showSnackBar(SnackBar(content: Text('Saved ${f.name}')));
    }
  }

  String _size(String path) {
    try {
      return formatBytes(File(path).lengthSync());
    } catch (_) {
      return '';
    }
  }

  bool _isImage(OutputFile f) {
    final m = f.mimeType;
    if (m != null && m.startsWith('image/')) return true;
    final n = f.name.toLowerCase();
    return n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.webp') ||
        n.endsWith('.bmp') ||
        n.endsWith('.gif');
  }

  void _viewImage(BuildContext context, OutputFile f) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Center(child: Image.file(File(f.path))),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final n = result.files.length;
    final header = n > 0 ? 'Nice — $n files.' : 'Done.';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AnvilRadii.control),
                  onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
                  child: IconChip(
                    icon: Icons.close,
                    box: 40,
                    glyph: 22,
                    bg: c.container,
                    fg: c.iconStrong,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              IconChip(
                icon: Icons.check,
                box: 52,
                glyph: 26,
                bg: c.accent,
                fg: c.onAccent,
              ),
              const SizedBox(height: 16),
              Text(header, style: text.headlineMedium),
              const SizedBox(height: 8),
              Text(
                "Saved on this phone. Share them whenever you're ready.",
                style: text.bodyLarge!.copyWith(color: c.muted),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: ListView(
                  children: [
                    for (final f in result.files) ...[
                      if (_isImage(f)) ...[
                        GestureDetector(
                          onTap: () => _viewImage(context, f),
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AnvilRadii.panel),
                            child: Container(
                              color: c.container,
                              height: 160,
                              alignment: Alignment.center,
                              child: Image.file(File(f.path),
                                  height: 140, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      ToolRow(
                        icon: Icons.insert_drive_file_outlined,
                        title: f.name,
                        subtitle: _size(f.path),
                        mono: true,
                        onTap: () => _open(context, f),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.open_in_new,
                                  size: 20, color: c.hint),
                              tooltip: 'Open',
                              onPressed: () => _open(context, f),
                            ),
                            IconButton(
                              icon: Icon(Icons.save_alt,
                                  size: 20, color: c.hint),
                              tooltip: 'Save to Files',
                              onPressed: () => _save(context, f),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (result.text != null) ...[
                      const SizedBox(height: 8),
                      SlabPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: result.text!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Copied to clipboard')),
                                  );
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copy'),
                              ),
                            ),
                            ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxHeight: 320),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  result.text!,
                                  style:
                                      AnvilText.mono(13, color: c.onSurface),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Share',
                icon: Icons.ios_share,
                onPressed: () => getIt<ShareService>().shareFiles(
                  [for (final f in result.files) f.path],
                ),
              ),
              const SizedBox(height: 10),
              SecondaryButton(
                label: 'Done',
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
