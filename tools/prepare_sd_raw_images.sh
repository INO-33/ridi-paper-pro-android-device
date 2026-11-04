#!/usr/bin/env bash
set -euo pipefail

product_out="${E70Q10_PRODUCT_OUT:?Set E70Q10_PRODUCT_OUT to target/product/e70q10}"
host_out="${ANDROID_HOST_OUT:-${product_out%/target/product/e70q10}/host/linux-x86}"
simg2img="${E70Q10_SIMG2IMG:-$host_out/bin/simg2img}"
# Default to the product directory and use the *.raw.img names that
# write_sd_images.sh and BOOT_TOMORROW.md expect. Writing to a different
# directory under a different suffix silently left the SD write using stale
# images.
output_dir="${E70Q10_SD_RAW_OUT:-$product_out}"

for input in "$product_out/system.img" "$product_out/vendor.img" "$simg2img"; do
    [[ -f "$input" && -r "$input" ]] || {
        echo "Missing input: $input" >&2
        exit 1
    }
done

mkdir -p "$output_dir"
"$simg2img" "$product_out/system.img" "$output_dir/system.raw.img"
"$simg2img" "$product_out/vendor.img" "$output_dir/vendor.raw.img"

# Android sparse images must never reach the SD partitions directly; a sparse
# image dd'd onto ext4 produces a system without /system/bin/sh. Verify the
# conversion actually produced ext4 filesystem data before anyone writes it.
for image in "$output_dir/system.raw.img" "$output_dir/vendor.raw.img"; do
    file "$image" | grep -q 'ext4 filesystem data' || {
        echo "Conversion did not produce raw ext4: $image" >&2
        exit 1
    }
done

echo "Prepared raw ext4 images for SD partitions:"
file "$output_dir/system.raw.img" "$output_dir/vendor.raw.img"
stat -c '%s bytes  %n' \
    "$output_dir/system.raw.img" \
    "$output_dir/vendor.raw.img"

