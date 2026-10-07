#!/usr/bin/env bash
set -euo pipefail

workspace="${RIDI_WORKSPACE:-/home/juwon/ridi}"
export E70Q10_LUNCH="${PAPER_EMULATOR_LUNCH:-e70q10_emulator_armv7-eng}"
export E70Q10_OUT_DIR="${PAPER_EMULATOR_OUT_DIR:-/media/juwon/build/paper-emulator-armv7}"
export E70Q10_MIN_FREE_GB="${PAPER_EMULATOR_MIN_FREE_GB:-10}"
export E70Q10_BUILD_JOBS="${PAPER_EMULATOR_BUILD_JOBS:-6}"
export ANDROID_DATA="${PAPER_EMULATOR_ANDROID_DATA:-$E70Q10_OUT_DIR/.android-data}"
mkdir -p "$ANDROID_DATA"

if [[ "${1:-check}" == build && $# -eq 1 ]]; then
    set -- build droid
fi

exec "$workspace/android-sources/nxp-o8.0.0_1.0.0-ga/device/ridi/e70q10/tools/build_android8.sh" "$@"
