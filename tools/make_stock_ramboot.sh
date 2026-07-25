#!/usr/bin/env bash
set -euo pipefail

workspace="${RIDI_WORKSPACE:-/home/juwon/ridi}"
product_out="${E70Q10_PRODUCT_OUT:-$workspace/android-out/e70q10/target/product/e70q10}"
host_out="${ANDROID_HOST_OUT:-$workspace/android-out/e70q10/host/linux-x86}"
tool_bin="${RIDI_ANDROID8_TOOL_BIN:-$workspace/host-tools/android8-bin}"
kernel="$product_out/obj/KERNEL_OBJ/kernel_img"
dtb="$product_out/obj/KERNEL_OBJ/imx6sl-e70q10.dtb"
ramdisk="$product_out/ramdisk.img"
mkbootimg="$host_out/bin/mkbootimg"
output="${1:-$product_out/e70q10-minimal-stock-ramboot.img}"

[[ -x "$tool_bin/python" ]] || {
    echo "Missing Python 2 wrapper: $tool_bin/python" >&2
    exit 1
}
export PATH="$tool_bin:$PATH"

for input in "$kernel" "$dtb" "$ramdisk" "$mkbootimg"; do
    [[ -f "$input" && -r "$input" ]] || {
        echo "Missing build input: $input" >&2
        exit 1
    }
done

temp_dir="$(mktemp -d)"
trap 'rm -r -- "$temp_dir"' EXIT
combined_kernel="$temp_dir/zImage+imx6sl-e70q10.dtb"
cp -- "$kernel" "$combined_kernel"
cat -- "$dtb" >>"$combined_kernel"

cmdline='console=ttymxc0,115200 init=/init androidboot.console=ttymxc0 consoleblank=0 no_console_suspend androidboot.hardware=E70Q10 video=mxcepdcfb:ED078KH1,bpp=16 mem=1018M panic=10 oops=panic loglevel=7 androidboot.selinux=permissive'

"$mkbootimg" \
    --kernel "$combined_kernel" \
    --ramdisk "$ramdisk" \
    --base 0x82800000 \
    --pagesize 2048 \
    --cmdline "$cmdline" \
    --output "$output"

read -r kernel_size _ ramdisk_size _ second_size _ _ page_size \
    < <(od -An -v -w32 -j8 -N32 -tu4 "$output")

if ((second_size != 0)); then
    echo "Refusing unexpected image with second_size=$second_size" >&2
    exit 1
fi
if ((kernel_size != $(stat -c %s "$combined_kernel"))); then
    echo "Kernel size mismatch in boot header" >&2
    exit 1
fi
if ((ramdisk_size != $(stat -c %s "$ramdisk") || page_size != 2048)); then
    echo "Ramdisk size or page-size mismatch in boot header" >&2
    exit 1
fi

echo "Created stock-compatible RAM-boot candidate (not flashed): $output"
sha256sum "$output"
