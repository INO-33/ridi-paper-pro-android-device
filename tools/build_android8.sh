#!/usr/bin/env bash
set -euo pipefail

workspace="${RIDI_WORKSPACE:-/home/juwon/ridi}"
source_tree="${ANDROID_BUILD_TOP:-$workspace/android-sources/nxp-o8.0.0_1.0.0-ga}"
java_home="${JAVA_HOME:-$workspace/host-tools/jdk8-local/usr/lib/jvm/java-8-openjdk-amd64}"
tool_bin="${RIDI_ANDROID8_TOOL_BIN:-$workspace/host-tools/android8-bin}"

[[ -x "$java_home/bin/javac" ]] || {
    echo "Missing Java 8 compiler: $java_home/bin/javac" >&2
    exit 1
}
[[ -x "$tool_bin/python" ]] || {
    echo "Missing Python 2 wrapper: $tool_bin/python" >&2
    exit 1
}

export JAVA_HOME="$java_home"
export PATH="$tool_bin:$JAVA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$JAVA_HOME/lib/amd64/jli${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export HOSTCFLAGS=-fcommon
export LC_ALL=C
export OUT_DIR="${E70Q10_OUT_DIR:-$workspace/android-out/e70q10}"
export USE_CCACHE=0

cd "$source_tree"
set +u
# shellcheck disable=SC1091
source build/envsetup.sh >/dev/null
lunch "${E70Q10_LUNCH:-e70q10_minimal-eng}" >/dev/null
set -u

case "${1:-check}" in
    check)
        echo "Android build environment ready"
        echo "  target:  ${TARGET_PRODUCT}-${TARGET_BUILD_VARIANT}"
        echo "  output:  $OUT_DIR"
        echo "  java:    $("$JAVA_HOME/bin/javac" -version 2>&1)"
        echo "  python:  $(python --version 2>&1)"
        echo "  free:    $(df -h "$workspace" | awk 'NR == 2 {print $4}')"
        ;;
    build)
        shift
        jobs="${E70Q10_BUILD_JOBS:-6}"
        min_free_gb="${E70Q10_MIN_FREE_GB:-25}"
        free_kb="$(df -Pk "$workspace" | awk 'NR == 2 {print $4}')"
        min_free_kb="$((min_free_gb * 1024 * 1024))"
        if (( free_kb < min_free_kb )); then
            echo "Refusing build: ${free_kb} KiB free; ${min_free_kb} KiB required" >&2
            exit 1
        fi
        (($#)) || set -- ramdisk
        echo "Building $* with -j$jobs into $OUT_DIR"
        make -j"$jobs" "$@"
        ;;
    *)
        echo "Usage: $0 [check | build [make-target ...]]" >&2
        exit 2
        ;;
esac
