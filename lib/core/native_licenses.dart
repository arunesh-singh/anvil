/// Attribution for native binaries we ship that no pub LICENSE describes.
/// FFmpeg is LGPL-3.0: §4 wants the notice, the license text, and a route to
/// relink the app against a modified FFmpeg. Needle 3 is MIT: the notice and
/// the copyright line are all §1 asks for, but neither binary arrives through
/// pub, so neither shows up in the generated license list on its own.
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

const String _needleNotice = '''
Anvil links the prebuilt Needle 3 engine archive (libneedle.a, arm64-v8a and
armeabi-v7a) vendored at third_party/needle/ from the Hugging Face repository
Cactus-Compute/needle3, revision b009f8937124b2d0458f4ed040c10c41fd2a0dfc.

Needle is licensed under the MIT License; the full text ships in
third_party/needle/LICENSE. Source: https://github.com/cactus-compute/needle

The archive is linked whole into libneedle_ffi.so (android/app/src/main/cpp);
to run Anvil against your own build, replace third_party/needle/<abi>/
libneedle.a and rebuild.
''';

void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
        <String>['FFmpeg (native binaries)'], _ffmpegNotice);
    yield const LicenseEntryWithLineBreaks(
        <String>['Needle 3 (native engine)'], _needleNotice);
  });
}
