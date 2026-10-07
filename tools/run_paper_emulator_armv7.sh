#!/usr/bin/env bash
set -euo pipefail

workspace="${RIDI_WORKSPACE:-/home/juwon/ridi}"
source_tree="${ANDROID_BUILD_TOP:-$workspace/android-sources/nxp-o8.0.0_1.0.0-ga}"
out_dir="${PAPER_EMULATOR_OUT_DIR:-/media/juwon/build/paper-emulator-armv7}"
if [[ -d "$out_dir/target/product/e70q10_arm" ]]; then
    product_out="$out_dir/target/product/e70q10_arm"
else
    product_out="$out_dir"
fi

emulator="$source_tree/prebuilts/android-emulator/linux-x86_64/emulator"
kernel="${PAPER_EMULATOR_KERNEL:-$source_tree/prebuilts/qemu-kernel/arm/3.18/kernel-qemu2}"
skin="${PAPER_EMULATOR_SKIN:-702x936}"
density="${PAPER_EMULATOR_DENSITY:-160}"
profile="${PAPER_EMULATOR_PROFILE:-legacy}"
cores="${PAPER_EMULATOR_CORES:-1}"
cpu_model="${PAPER_EMULATOR_CPU:-}"
# Optional only: the shipped ARM kernel currently lacks CONFIG_HW_RANDOM, so
# enabling this by default would add a device that the guest cannot consume.
rng_mode="${PAPER_EMULATOR_RNG:-none}"
logcat_output="${PAPER_EMULATOR_LOGCAT:-$out_dir/paper-emulator-logcat.log}"

case "$profile" in
    strict_ab)
        gpu="off"
        software_fb=0
        force_sw_hwui=0
        ridi_eink=0
        # The generic ARM emulator's libGLES_android exposes a working ES1
        # PixelFlinger config, but not the physical E70Q10 RGB565 EGL config.
        # Leave RenderEngine's force_gles1 assert off; qemu.gles=0 still keeps
        # the profile free of host/emulated GLES2.
        force_gles1=0
        opengles_version=""
        strict_gles_prop=1
        ;;
    strict_display)
        gpu="off"
        software_fb=1
        # Keep the normal ViewRoot decision untouched.  This profile only
        # selects the existing PAPER/HWC1 RGB565 framebuffer-target contract
        # through ro.ridi.eink_mode; it does not force WebView software Canvas.
        force_sw_hwui=0
        ridi_eink=1
        force_gles1=0
        opengles_version=""
        strict_gles_prop=1
        ;;
    physical_like)
        gpu="off"
        software_fb=1
        force_sw_hwui=1
        ridi_eink=1
        # Physical-like framework policy is retained, but the display backend
        # stays on the bootable Ranchu software ES1 path. The physical-only
        # RGB565 RenderEngine assertion is not compatible with libGLES_android.
        force_gles1=0
        opengles_version=""
        strict_gles_prop=1
        ;;
    legacy)
        gpu="${PAPER_EMULATOR_GPU:-swiftshader}"
        software_fb=0
        force_sw_hwui=0
        ridi_eink=0
        force_gles1=0
        opengles_version=""
        strict_gles_prop=0
        ;;
    *)
        echo "Unsupported PAPER_EMULATOR_PROFILE=$profile; use strict_ab, strict_display, physical_like, or legacy." >&2
        exit 2
        ;;
esac

qemu_props=(
    -prop "qemu.sf.lcd_density=$density"
    -prop "qemu.hw.mainkeys=0"
    -prop "qemu.paper.profile=$profile"
    -prop "qemu.paper.force_sw_hwui=$force_sw_hwui"
    -prop "qemu.paper.ridi_eink=$ridi_eink"
    -prop "qemu.paper.force_gles1=$force_gles1"
    -prop "qemu.paper.software_fb=$software_fb"
)
if [[ "$force_gles1" == 1 ]]; then
    # ro.* values supplied directly to this legacy emulator frontend are
    # overwritten by its boot-property setup. Pass a qemu.* selector and let
    # the emulator init fragment apply the physical AGL policy early.
    : "${opengles_version:?internal profile value required}"
    qemu_props+=( -prop "qemu.opengles.version=$opengles_version" )
fi
if [[ "$strict_gles_prop" == 1 ]]; then
    qemu_props+=( -prop "qemu.gles=0" )
fi

qemu_args=()
if [[ -n "$cpu_model" || "$rng_mode" == "virtio" ]]; then
    qemu_args+=( -qemu )
    if [[ -n "$cpu_model" ]]; then
        qemu_args+=( -cpu "$cpu_model" )
    fi
    if [[ "$rng_mode" == "virtio" ]]; then
        # The ARM guest can otherwise block zygote in getrandom() forever when
        # its kernel entropy pool starts at zero.  This is test-harness entropy
        # only; it does not alter the graphics or WebView configuration.
        qemu_args+=(
            -object "rng-random,filename=/dev/urandom,id=paper_host_rng"
            -device "virtio-rng-device,rng=paper_host_rng"
        )
    elif [[ "$rng_mode" != "none" ]]; then
        echo "Unsupported PAPER_EMULATOR_RNG=$rng_mode; use virtio or none." >&2
        exit 2
    fi
fi

[[ -x "$emulator" ]] || { echo "Missing emulator: $emulator" >&2; exit 1; }
[[ -f "$kernel" ]] || { echo "Missing ARM emulator kernel: $kernel" >&2; exit 1; }

for image in system.img ramdisk.img userdata.img; do
    [[ -f "$product_out/$image" ]] || {
        echo "Missing $product_out/$image; build the ARMv7 paper emulator first." >&2
        exit 1
    }
done

build_prop="$product_out/system/build.prop"
[[ -f "$build_prop" ]] || {
    echo "Missing $build_prop; build the ARMv7 paper emulator first." >&2
    exit 1
}
if ! grep -Eq '^ro\.product\.cpu\.abi=armeabi-v7a$' "$build_prop"; then
    echo "Refusing to boot a stale non-ARMv7 image from $product_out." >&2
    exit 1
fi

vendor_image="$product_out/vendor.img"
if [[ ! -f "$vendor_image" ]]; then
    make_ext4fs="$out_dir/host/linux-x86/bin/make_ext4fs"
    [[ -x "$make_ext4fs" ]] || {
        echo "Missing host make_ext4fs; build the ARMv7 paper emulator first." >&2
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
elif [[ "$(stat -c '%s' "$userdata_image")" != "$(stat -c '%s' "$product_out/userdata.img")" ]]; then
    # Do not delete or rewrite a prior disposable image.  A stale copy can be
    # smaller than the freshly built filesystem and then fails fs_mgr geometry
    # checks before SurfaceFlinger is meaningfully tested.
    userdata_image="${TMPDIR:-/tmp}/paper-emulator-armv7-${profile}-userdata-$$.img"
    cp --reflink=auto "$product_out/userdata.img" "$userdata_image"
fi
mkdir -p "$product_out/data/misc/pstore"
pstore_file="$product_out/data/misc/pstore/pstore.bin"
if [[ ! -f "$pstore_file" ]]; then
    : > "$pstore_file"
fi

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
    "${qemu_props[@]}" \
    -logcat-output "$logcat_output" \
    -memory 1024 \
    -cores "$cores" \
    -gpu "$gpu" \
    -accel off \
    -sdcard "$sdcard_image" \
    -no-snapshot \
    "${qemu_args[@]}" \
    "$@"
