#!/usr/bin/env bash
set -euo pipefail

workspace="${RIDI_WORKSPACE:-/home/juwon/ridi}"
adb="${ADB:-$workspace/host-tools/android-platform-tools/platform-tools/adb}"
apk="${RIDI_PAPER_APK:-$workspace/ridi-paper-pro-stock-4.4.2-20260721/files/system/priv-app/com.ridi.paper.apk}"
component="com.ridi.paper/com.ridi.books.viewer.common.activity.SetupWizardActivity"
log_file="${RIDI_APP_LOG:-$workspace/log/paper-emulator-ridi.log}"

[[ -x "$adb" ]] || { echo "Missing adb: $adb" >&2; exit 1; }
[[ -f "$apk" ]] || { echo "Missing RIDI APK: $apk" >&2; exit 1; }

"$adb" wait-for-device
until [[ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; do
    sleep 1
done

"$adb" install -r -g "$apk" || {
    echo "Normal install failed. The app may require platform/privileged permissions; see logcat." >&2
    exit 1
}

"$adb" logcat -c
"$adb" shell am force-stop com.ridi.paper
"$adb" shell am start -W -n "$component"

echo "Capturing RIDI, crash and virtual EPDC logs in $log_file"
exec "$adb" logcat -v threadtime \
    PAPER_EPDC:I E70Q10_VIEW:I AndroidRuntime:E ActivityManager:I libc:F '*:S' \
    >"$log_file"
