#!/usr/bin/env bash
set -euo pipefail

workspace="${RIDI_WORKSPACE:-/home/juwon/ridi}"
source_tree="${ANDROID_BUILD_TOP:-$workspace/android-sources/nxp-o8.0.0_1.0.0-ga}"
out_dir="${PAPER_EMULATOR_OUT_DIR:-$workspace/android-out/paper-emulator-x86}"
if [[ -d "$out_dir/target/product/e70q10_emulator" ]]; then
    product_out="$out_dir/target/product/e70q10_emulator"
else
    # Also accept an explicit product directory for convenience.
    product_out="$out_dir"
fi
emulator="$source_tree/prebuilts/android-emulator/linux-x86_64/emulator"
kernel="$source_tree/prebuilts/qemu-kernel/x86/3.18/kernel-qemu2"
skin="${PAPER_EMULATOR_SKIN:-702x936}"
density="${PAPER_EMULATOR_DENSITY:-160}"
gpu="${PAPER_EMULATOR_GPU:-swiftshader}"
# i.MX6SL is single-core, so keep one guest vCPU for comparable scheduler
# behaviour even though this x86 guest runs with KVM acceleration.
cores="${PAPER_EMULATOR_CORES:-1}"
logcat_output="${PAPER_EMULATOR_LOGCAT:-$out_dir/paper-emulator-logcat.log}"

[[ -x "$emulator" ]] || { echo "Missing emulator: $emulator" >&2; exit 1; }
[[ -f "$kernel" ]] || { echo "Missing x86 emulator kernel: $kernel" >&2; exit 1; }

for image in system.img ramdisk.img userdata.img; do
    [[ -f "$product_out/$image" ]] || {
        echo "Missing $product_out/$image; build the paper emulator first." >&2
        exit 1
    }
done

build_prop="$product_out/system/build.prop"
[[ -f "$build_prop" ]] || {
    echo "Missing $build_prop; build the x86 paper emulator first." >&2
    exit 1
}
if ! grep -Eq '^ro\.product\.cpu\.abi=x86$' "$build_prop"; then
    echo "Refusing to boot a stale non-x86 image from $product_out." >&2
    echo "Use a fresh PAPER_EMULATOR_OUT_DIR and rebuild e70q10_emulator." >&2
    exit 1
fi

# This old emulator frontend always requires a vendor.img argument, even for
# non-Treble products.  E70Q10 Emulator is intentionally non-Treble and its
# root/vendor symlink points at /system/vendor, so the image is only a valid
# compatibility placeholder and is not mounted by fstab.ranchu.
vendor_image="$product_out/vendor.img"
if [[ ! -f "$vendor_image" ]]; then
    make_ext4fs="$out_dir/host/linux-x86/bin/make_ext4fs"
    [[ -x "$make_ext4fs" ]] || {
        echo "Missing host make_ext4fs; build the paper emulator first." >&2
        exit 1
    }
    empty_vendor="$product_out/.empty-vendor"
    mkdir -p "$empty_vendor"
    "$make_ext4fs" -l 16777216 -L vendor -a vendor \
        "$vendor_image" "$empty_vendor"
fi

userdata_image="$product_out/userdata-qemu.img"
if [[ ! -f "$userdata_image" ]]; then
    cp --reflink=auto "$product_out/userdata.img" "$userdata_image"
fi
mkdir -p "$product_out/data/misc/pstore"

sdcard_image="$product_out/sdcard.img"
if [[ ! -f "$sdcard_image" ]]; then
    mksdcard="$source_tree/prebuilts/android-emulator/linux-x86_64/mksdcard"
    [[ -x "$mksdcard" ]] || { echo "Missing mksdcard: $mksdcard" >&2; exit 1; }
    "$mksdcard" 64M "$sdcard_image"
fi

export ANDROID_PRODUCT_OUT="$product_out"
exec "$emulator" \
    -sysdir "$product_out" \
    -kernel "$kernel" \
    -vendor "$vendor_image" \
    -data "$userdata_image" \
    -skin "$skin" \
    -prop "qemu.sf.lcd_density=$density" \
    -prop "qemu.hw.mainkeys=0" \
    -logcat-output "$logcat_output" \
    -memory 1024 \
    -cores "$cores" \
    -gpu "$gpu" \
    -sdcard "$sdcard_image" \
    -no-snapshot \
    "$@"
