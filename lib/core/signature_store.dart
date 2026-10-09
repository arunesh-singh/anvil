/// Signatures drawn or imported in the PDF workspace, kept as PNG files under
/// app support (NOT the outputs dir, which retention and "clear outputs" wipe)
/// so a signature drawn once is offered again on every later document.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class SignatureStore {
  SignatureStore(this.root);

  /// `<support>/anvil/signatures`.
  final Directory root;

  /// Saved signature PNGs, newest first. File names carry an epoch-ms prefix,
  /// so name order is age order. Empty when nothing was saved yet.
  Future<List<File>> list() async {
    if (!await root.exists()) return [];
    final files = <File>[
      await for (final e in root.list())
        if (e is File && p.extension(e.path).toLowerCase() == '.png') e,
    ];
    int stamp(File f) => int.tryParse(p.basenameWithoutExtension(f.path)) ?? 0;
    files.sort((a, b) => stamp(b).compareTo(stamp(a)));
    return files;
  }

  /// Writes [png] as `<epochMs>.png`, creating [root] on first use. Two saves
  /// in the same millisecond get distinct names.
  Future<File> save(Uint8List png) async {
    await root.create(recursive: true);
    var ms = DateTime.now().millisecondsSinceEpoch;
    var f = File(p.join(root.path, '$ms.png'));
    while (await f.exists()) {
      f = File(p.join(root.path, '${++ms}.png'));
    }
    return f.writeAsBytes(png, flush: true);
  }

  /// Removes [f]; a file that is already gone is not an error.
  Future<void> delete(File f) async {
    if (await f.exists()) await f.delete();
  }
}
