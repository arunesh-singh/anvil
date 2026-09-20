// Shared-library shell around the vendored Needle 3 static archive.
//
// The five `needle_*` entry points come from libneedle.a itself (pulled in
// whole by the linker, see CMakeLists.txt) and carry default visibility, so
// dart:ffi looks them up directly. This translation unit exists to give CMake
// a source file, to expose a marker the Dart side can probe, and to close the
// one libc++ gap described below.

#include <cstddef>
#include <cstdint>
#include <cstring>

#include "needle.h"

extern "C" __attribute__((visibility("default"))) int needle_ffi_abi_version(void) {
  return 3;
}

#if defined(__arm__)
// The 32-bit archive was built against NDK r30's libc++, which outlines the
// byte hasher as std::__ndk1::__hash_memory(const void*, size_t). No stable
// NDK defines that symbol (verified across r26/r27/r27.1/r28 — only the r30
// beta has it), and the 64-bit archive never references it because libc++
// keeps the cityhash path header-inline there. Rather than put the whole app
// on a beta toolchain for one ABI, define the symbol here.
//
// This is libc++'s own murmur2, byte for byte. Correctness only needs
// determinism within a process — nothing persists or shares these hashes —
// and NDK r28's libc++ neither defines nor calls it, so there is no ODR
// conflict. If a future NDK bump starts providing it, this fails loudly at
// link time with a duplicate symbol: delete the block then.
extern "C" std::size_t _needle_hash_memory(const void* key,
                                           std::size_t len) __asm__(
    "_ZNSt6__ndk113__hash_memoryEPKvj");

extern "C" std::size_t _needle_hash_memory(const void* key, std::size_t len) {
  const std::uint32_t m = 0x5bd1e995;
  const std::uint32_t r = 24;
  std::uint32_t h = static_cast<std::uint32_t>(len);
  const unsigned char* data = static_cast<const unsigned char*>(key);
  for (; len >= 4; data += 4, len -= 4) {
    std::uint32_t k;
    std::memcpy(&k, data, sizeof(k));
    k *= m;
    k ^= k >> r;
    k *= m;
    h *= m;
    h ^= k;
  }
  switch (len) {
    case 3:
      h ^= static_cast<std::uint32_t>(data[2]) << 16;
      [[fallthrough]];
    case 2:
      h ^= static_cast<std::uint32_t>(data[1]) << 8;
      [[fallthrough]];
    case 1:
      h ^= data[0];
      h *= m;
      break;
    default:
      break;
  }
  h ^= h >> 13;
  h *= m;
  h ^= h >> 15;
  return h;
}
#endif  // __arm__
