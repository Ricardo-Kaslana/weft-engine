#!/usr/bin/env bash
# Builds the Weft QuickJS glue + QuickJS engine into a single dynamic library.
#
#   packages/weft_quickjs/tool/build_native.sh
#
# Output: packages/weft_quickjs/ios/Classes/native/build/weft_quickjs.dll
# (.so on POSIX). Requires a C compiler (gcc by default; override with CC).
# The build directory is gitignored; run this once per machine before running
# weft_quickjs tests. CI builds the library from the vendored sources in the
# same way.
set -euo pipefail

cd "$(dirname "$0")/../ios/Classes/native"
mkdir -p build

CC="${CC:-gcc}"
SOURCES=(weft_glue.c quickjs/quickjs.c quickjs/libregexp.c quickjs/libunicode.c
  quickjs/cutils.c quickjs/libbf.c)
QJS_VERSION="$(cat quickjs/VERSION | tr -d '[:space:]')"
CFLAGS=(-O2 -g0 -std=gnu99 -fno-strict-aliasing -D_GNU_SOURCE -DCONFIG_BIGNUM
  -DCONFIG_VERSION="\"$QJS_VERSION\"")

case "$(uname -s)" in
  MINGW* | Windows* | CYGWIN*)
    OUT=build/weft_quickjs.dll
    "$CC" "${CFLAGS[@]}" -shared -static-libgcc -o "$OUT" "${SOURCES[@]}"
    ;;
  *)
    OUT=build/libweft_quickjs.so
    "$CC" "${CFLAGS[@]}" -fPIC -shared -o "$OUT" "${SOURCES[@]}" -lm
    ;;
esac

echo "built ios/Classes/native/$OUT"
