/// Device capability snapshot + the variant-compatibility gate.
///
/// MODEL_DELIVERY.md: "if no variant meets device minRamGb/accelerator → tool
/// disabled with a clear message".
library;

import 'dart:io';

import 'package:anvil/models/manifest.dart';

/// What the device offers, as far as model selection cares.
class DeviceCaps {
  /// Whole "marketing" gigabytes of RAM: `MemTotal` rounded **up**, because a
  /// phone sold as 4 GB reports ~3.7 GiB after reserved carve-outs and must
  /// still pass a `minRamGb: 4` gate.
  final int ramGb;

  /// Detected accelerator hints ('cpu', 'nnapi', …). Informational — surfaced
  /// for diagnostics/storage UI; the gate below does not consult it.
  final Set<String> accelerators;

  const DeviceCaps({required this.ramGb, required this.accelerators});

  /// Accelerator gating heuristic (documented per the Phase-2 assignment):
  /// the manifest's `accelerator` string is **advisory** — every runtime we
  /// ship falls back to CPU, so it never hard-blocks by itself. 'nnapi' and
  /// 'cpu' variants are always allowed. 'gpu' variants are only offered on
  /// devices with >= 4 GB RAM: a GPU-targeted model on a low-RAM device would
  /// end up on the CPU fallback *and* not fit in memory, so RAM is the proxy
  /// we gate on. Unknown accelerator strings are treated like 'cpu'.
  bool supportsAccelerator(String accelerator) =>
      accelerator != 'gpu' || ramGb >= 4;

  /// A variant is compatible iff the device has at least `minRamGb` RAM and
  /// [supportsAccelerator] passes.
  bool isCompatibleWith(ModelVariant variant) =>
      ramGb >= variant.minRamGb && supportsAccelerator(variant.accelerator);
}

/// Injectable source of [DeviceCaps]; fake it in tests.
abstract interface class DeviceCapsProvider {
  Future<DeviceCaps> read();
}

/// Always returns the given caps. For tests and non-mobile wiring.
class FixedDeviceCapsProvider implements DeviceCapsProvider {
  final DeviceCaps caps;
  const FixedDeviceCapsProvider(this.caps);
  @override
  Future<DeviceCaps> read() async => caps;
}

/// Real implementation: reads `MemTotal` from /proc/meminfo (present on
/// Android and Linux). Anywhere the file is missing or unreadable it returns
/// conservative defaults (2 GB, CPU only) so only the leanest variants pass.
class ProcMeminfoDeviceCapsProvider implements DeviceCapsProvider {
  final String meminfoPath;
  const ProcMeminfoDeviceCapsProvider({this.meminfoPath = '/proc/meminfo'});

  static const DeviceCaps _conservative = DeviceCaps(
    ramGb: 2,
    accelerators: {'cpu'},
  );

  @override
  Future<DeviceCaps> read() async {
    final int? ramGb = await _readRamGb();
    if (ramGb == null) return _conservative;
    return DeviceCaps(
      ramGb: ramGb,
      // NNAPI ships on every Android API level we target; advisory only.
      accelerators: Platform.isAndroid ? const {'cpu', 'nnapi'} : const {'cpu'},
    );
  }

  Future<int?> _readRamGb() async {
    final String content;
    try {
      content = await File(meminfoPath).readAsString();
    } on IOException {
      return null;
    }
    // Format: "MemTotal:        3882924 kB"
    for (final line in content.split('\n')) {
      if (!line.startsWith('MemTotal:')) continue;
      final match = RegExp(r'(\d+)').firstMatch(line);
      if (match == null) return null;
      final kb = int.parse(match.group(1)!);
      return (kb / (1024 * 1024)).ceil().clamp(1, 1 << 20);
    }
    return null;
  }
}
