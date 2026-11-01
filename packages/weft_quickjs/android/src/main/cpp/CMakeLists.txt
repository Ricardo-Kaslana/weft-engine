# Builds the Weft QuickJS shim plus the vendored QuickJS engine into
# libweft_quickjs.so for Android.
#
# The sources are consumed in place from packages/weft_quickjs/ios/Classes/native,
# the same files tool/build_native.sh compiles for desktop and the iOS pod
# compiles for the app image. The location under ios/ is required because
# CocoaPods file patterns cannot traverse to a sibling directory. Nothing is
# copied, so there is one definition of the build.

cmake_minimum_required(VERSION 3.13)
project(weft_quickjs LANGUAGES C)

set(WEFT_NATIVE "${CMAKE_CURRENT_SOURCE_DIR}/../../../../ios/Classes/native")

if(NOT EXISTS "${WEFT_NATIVE}/weft_glue.c")
    message(FATAL_ERROR "weft_quickjs: native sources not found at ${WEFT_NATIVE}")
endif()

add_library(weft_quickjs SHARED
    "${WEFT_NATIVE}/weft_glue.c"
    "${WEFT_NATIVE}/quickjs/quickjs.c"
    "${WEFT_NATIVE}/quickjs/libregexp.c"
    "${WEFT_NATIVE}/quickjs/libunicode.c"
    "${WEFT_NATIVE}/quickjs/cutils.c"
    "${WEFT_NATIVE}/quickjs/libbf.c"
)

target_include_directories(weft_quickjs PRIVATE "${WEFT_NATIVE}")

target_compile_features(weft_quickjs PRIVATE c_std_99)
target_compile_options(weft_quickjs PRIVATE
    -fno-strict-aliasing
    # Only the WEFT_EXPORT entry points are part of the FFI surface; keep the
    # QuickJS internals out of the dynamic symbol table.
    -fvisibility=hidden
)
target_compile_definitions(weft_quickjs PRIVATE
    _GNU_SOURCE
    CONFIG_BIGNUM
    CONFIG_VERSION="2024-01-13"
)

# bionic ships pthread in libc; libm is a separate library on Android.
target_link_libraries(weft_quickjs PRIVATE m)

# Google Play requires 16 KB page alignment for apps targeting Android 15+.
# NDK r27 still lays shared libraries out at 4 KB, so ask the linker for 16 KB;
# the wider alignment stays compatible with 4 KB devices.
target_link_options(weft_quickjs PRIVATE -Wl,-z,max-page-size=16384)
