import 'package:anvil/core/native_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the FFmpeg LGPL notice is registered with source and relink info',
      () async {
    registerNativeLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final ffmpeg = entries.firstWhere(
        (e) => e.packages.contains('FFmpeg (native binaries)'));
    final text = ffmpeg.paragraphs.map((p) => p.text).join(' ');
    expect(text, contains('Lesser General Public License'));
    expect(text, contains('github.com/sk3llo/ffmpeg_kit_flutter'));
    expect(text, contains('Relinking'));
  });
}
