/// Attribution for native binaries we ship that no pub LICENSE describes.
/// FFmpeg is LGPL-3.0: §4 wants the notice, the license text, and a route to
/// relink the app against a modified FFmpeg.
library;

import 'package:flutter/foundation.dart';

const String _ffmpegNotice = '''
Anvil bundles prebuilt FFmpeg shared libraries via ffmpeg_kit_flutter_new_full
2.2.2 (https://github.com/sk3llo/ffmpeg_kit_flutter), a fork of
arthenica/ffmpeg-kit (https://github.com/arthenica/ffmpeg-kit). This is the
LGPL flavour: no GPL-only components (no x264, no libxvid) are linked.

FFmpeg is licensed under the GNU Lesser General Public License v3.0 or later.
The full LGPL text ships with the ffmpeg_kit_flutter_new_full entry in this
list. FFmpeg source: https://ffmpeg.org/download.html

Relinking: Anvil loads FFmpeg dynamically from libffmpegkit.so inside the APK.
To run Anvil against your own build of FFmpeg, build the ffmpeg-kit LGPL
libraries, replace the .so files of the matching ABI inside the APK, re-sign
it, and install the result.
''';

void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
        <String>['FFmpeg (native binaries)'], _ffmpegNotice);
  });
}
