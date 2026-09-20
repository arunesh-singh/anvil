cmake_minimum_required(VERSION 3.22.1)
project(needle_ffi LANGUAGES C CXX)

# Needle ships a STATIC archive per ABI (no .so, no Flutter plugin), so the
# only way dart:ffi can reach it is to relink it into a shared library we own.
set(NEEDLE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/needle)

add_library(needle_static STATIC IMPORTED)
set_target_properties(needle_static PROPERTIES
    IMPORTED_LOCATION ${NEEDLE_DIR}/${ANDROID_ABI}/libneedle.a)

add_library(needle_ffi SHARED needle_ffi.cpp)
target_include_directories(needle_ffi PRIVATE ${NEEDLE_DIR})

# --whole-archive is load-bearing: needle_ffi.cpp references none of the
# engine's entry points (Dart looks them up by name at runtime), so without it
# the linker drops every object in the archive and the .so exports nothing.
target_link_libraries(needle_ffi
    -Wl,--whole-archive needle_static -Wl,--no-whole-archive
    log)
