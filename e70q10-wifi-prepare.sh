#!/system/bin/sh

# SupplicantManager copies the system template only when the data file does not
# exist. Preserve existing network entries on upgraded SD data partitions, but
# add the E70Q10's required STA-only policy if the old file predates it.
config=/data/misc/wifi/wpa_supplicant.conf

if [ -f "$config" ] && ! grep -q '^p2p_disabled=1$' "$config"; then
    echo 'p2p_disabled=1' >> "$config"
fi

if [ -f "$config" ]; then
    chown wifi:wifi "$config"
    chmod 0660 "$config"
fi
