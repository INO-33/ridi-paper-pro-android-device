#!/usr/bin/env bash
set -euo pipefail

sd_device="${1:-}"
expected_confirmation="${CONFIRM_E70Q10_SD:-}"
product_out="${E70Q10_PRODUCT_OUT:-/media/juwon/build/android-out/e70q10_reference_agl_stockpath/target/product/e70q10}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
prepare_script="$script_dir/prepare_sd_raw_images.sh"
system_sparse="$product_out/system.img"
vendor_sparse="$product_out/vendor.img"
system_image="$product_out/system.raw.img"
vendor_image="$product_out/vendor.raw.img"

if [[ ! "$sd_device" =~ ^/dev/sd[a-z]$ ]] ||
   [[ ! -b "$sd_device" ]] ||
   [[ "$expected_confirmation" != "$sd_device" ]]; then
    echo "Refusing write." >&2
    echo "Usage: CONFIRM_E70Q10_SD=/dev/sdX $0 /dev/sdX" >&2
    exit 2
fi

# Never trust an existing *.raw.img here. Android's image build updates the
# sparse system.img/vendor.img but does not update the separately converted raw
# files, which previously allowed an old filesystem to be written after a new
# build. Recreate both raw ext4 images immediately before every SD write.
[[ -x "$prepare_script" ]] || {
    echo "Missing raw-image preparation script: $prepare_script" >&2
    exit 1
}
E70Q10_PRODUCT_OUT="$product_out" "$prepare_script"

for image in "$system_image" "$vendor_image"; do
    [[ -f "$image" ]] || {
        echo "Missing raw image: $image" >&2
        exit 1
    }
    file "$image" | grep -q 'ext4 filesystem data' || {
        echo "Refusing non-raw image: $image" >&2
        exit 1
    }
done

# Keep a second, explicit freshness assertion in the destructive script. This
# also catches a failed converter that happened to leave an older output file.
[[ ! "$system_sparse" -nt "$system_image" ]] || {
    echo "Refusing stale raw image: $system_image" >&2
    exit 1
}
[[ ! "$vendor_sparse" -nt "$vendor_image" ]] || {
    echo "Refusing stale raw image: $vendor_image" >&2
    exit 1
}

system_partition="${sd_device}2"
vendor_partition="${sd_device}3"
[[ -b "$system_partition" && -b "$vendor_partition" ]] || {
    echo "Missing expected p2/p3 partitions on $sd_device" >&2
    exit 1
}

system_bytes="$(stat -c %s "$system_image")"
vendor_bytes="$(stat -c %s "$vendor_image")"
(( $(sudo blockdev --getsize64 "$system_partition") >= system_bytes )) || {
    echo "$system_partition is too small" >&2
    exit 1
}
(( $(sudo blockdev --getsize64 "$vendor_partition") >= vendor_bytes )) || {
    echo "$vendor_partition is too small" >&2
    exit 1
}

echo "Target confirmed:"
# Keep the confirmation compact. Wide MOUNTPOINTS columns and carriage-return
# progress updates render as streams of blank padding in some IDE terminals.
lsblk -dn -o NAME,PATH,SIZE,MODEL,TRAN "$sd_device"
lsblk -ln -o NAME,SIZE,FSTYPE,LABEL "$sd_device"
for partition in "${sd_device}1" "${sd_device}2" "${sd_device}3" "${sd_device}4"; do
    if findmnt -rn -S "$partition" >/dev/null; then
        udisksctl unmount -b "$partition"
    fi
done

echo "Writing system image to $system_partition ..."
sudo dd if="$system_image" of="$system_partition" bs=64M conv=fsync status=none
echo "Writing vendor image to $vendor_partition ..."
sudo dd if="$vendor_image" of="$vendor_partition" bs=64M conv=fsync status=none
sync
echo "E70Q10 SD system/vendor write complete."
