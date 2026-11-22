#!/bin/bash
# Host bit-exactness test for the E70Q10 sleep-overlay NEON blend.
# ARM build: prebuilt arm-linux-androideabi-4.9 + static bionic from the
# reference out tree, run under qemu-arm-static. Host build: scalar only.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../../../../.." && pwd)
OUT=${E70Q10_OUT:-/media/juwon/build/android-out/e70q10_reference_agl_stockpath/target/product/e70q10}
WORK=${WORK:-$(mktemp -d)}
CC=$TOP/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/real-arm-linux-androideabi-gcc
INC=(-I"$TOP/vendor/nxp-opensource/imx/display/gralloc_v1"
     -isystem "$TOP/bionic/libc/include" -isystem "$TOP/bionic/libc/kernel/uapi"
     -isystem "$TOP/bionic/libc/kernel/uapi/asm-arm" -isystem "$TOP/bionic/libc/kernel/android/uapi")
ARMFLAGS=(-std=gnu99 -O2 -march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=softfp -marm -nostdinc
          -isystem "$("$CC" -print-file-name=include)")
LDFLAGS=(-static -nostdlib "$OUT/obj/lib/crtbegin_static.o")
LIBS=("$OUT/obj/STATIC_LIBRARIES/libc_intermediates/libc.a" "$("$CC" -print-libgcc-file-name)"
      "$OUT/obj/STATIC_LIBRARIES/libc_intermediates/libc.a" "$OUT/obj/lib/crtend_android.o")
status=0
TESTS=${TESTS:-$(cd "$HERE" && ls *_test.c)}
for src in $TESTS; do
  name=${src%.c}
  "$CC" "${ARMFLAGS[@]}" "${INC[@]}" "${LDFLAGS[@]}" -o "$WORK/$name.arm" "$HERE/$src" "${LIBS[@]}"
  echo "== $name (armv7 neon, qemu)"; unshare -Urp --fork qemu-arm-static "$WORK/$name.arm" || status=1
  cc -std=gnu99 -O2 -I"$TOP/vendor/nxp-opensource/imx/display/gralloc_v1" \
     -o "$WORK/$name.host" "$HERE/$src"
  echo "== $name (host scalar)"; "$WORK/$name.host" || status=1
done
exit $status
