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
export USE_CCACHE=0
jack_security="$source_tree/device/ridi/e70q10/tools/jack-java.security"
export ANDROID_JACK_VM_ARGS="${ANDROID_JACK_VM_ARGS:--Dfile.encoding=UTF-8 -XX:+TieredCompilation -Djava.security.properties=$jack_security}"

lunch_target="${E70Q10_LUNCH:-e70q10_minimal-eng}"
product_name="${lunch_target%-*}"
export OUT_DIR="${E70Q10_OUT_DIR:-$workspace/android-out/$product_name}"
# Host ART tools must not fall back to the build computer's /data.
export ANDROID_DATA="${ANDROID_DATA:-$OUT_DIR/.android-data}"

cd "$source_tree"
set +u
# shellcheck disable=SC1091
source build/envsetup.sh >/dev/null
lunch "$lunch_target" >/dev/null
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
        out_parent="$(dirname "$OUT_DIR")"
        if [[ ! -d "$out_parent" ]]; then
            echo "Missing OUT_DIR parent: $out_parent" >&2
            exit 1
        fi
        free_kb="$(df -Pk "$out_parent" | awk 'NR == 2 {print $4}')"
        min_free_kb="$((min_free_gb * 1024 * 1024))"
        if (( free_kb < min_free_kb )); then
            echo "Refusing build: ${free_kb} KiB free; ${min_free_kb} KiB required" >&2
            exit 1
        fi
        (($#)) || set -- ramdisk
        # HWC/gralloc are on the separate vendor partition; keep the sleep
        # extension producer and the framework consumer in the same build.
        want_system=0
        want_vendor=0
        for build_target in "$@"; do
            [[ "$build_target" != systemimage ]] || want_system=1
            [[ "$build_target" != vendorimage ]] || want_vendor=1
        done
        if (( want_system && !want_vendor )); then
            set -- "$@" vendorimage
            echo "Adding vendorimage: apply system.img and vendor.img together"
        fi
        mkdir -p "$ANDROID_DATA"
        product_out="$OUT_DIR/target/product/e70q10"
        # Non-eng Android 8 shows "internal problem" when the system and vendor
        # fingerprints differ (Build.isBuildConsistent). The fingerprint embeds
        # the make start time and build.prop only regenerates when its deps
        # change, so force both (and the ramdisk copy) in this one invocation.
        if (( want_system )) && [[ "$TARGET_BUILD_VARIANT" != eng ]]; then
            # system/build.prop is only a copy of this intermediate.
            rm -f "$product_out/obj/ETC/system_build_prop_intermediates/build.prop" \
                "$product_out/system/build.prop" "$product_out/vendor/build.prop"
            for build_target in "$@"; do
                [[ "$build_target" != bootimage ]] || rm -f "$product_out/root/default.prop"
            done
        fi
        echo "Building $* with -j$jobs into $OUT_DIR"
        make -j"$jobs" "$@"
        if (( want_system )) && [[ "$TARGET_BUILD_VARIANT" != eng ]]; then
            system_fp="$(sed -n 's/^ro\.build\.fingerprint=//p' "$product_out/system/build.prop")"
            vendor_fp="$(sed -n 's/^ro\.vendor\.build\.fingerprint=//p' "$product_out/vendor/build.prop")"
            if [[ -z "$system_fp" || "$system_fp" != "$vendor_fp" ]]; then
                echo "Fingerprint mismatch: system '$system_fp' vendor '$vendor_fp'" >&2
                exit 1
            fi
            echo "Fingerprint: $system_fp"
        fi
        if (( want_system )) && [[ "$lunch_target" == e70q10_reference-user || "$lunch_target" == e70q10_minimal-user ]]; then
            product_out="$OUT_DIR/target/product/e70q10"
            python3 "$workspace/porting/e70q10/emmc-tool/signing_policy.py" \
                --product "$product_out" --source "$source_tree" \
                --certificate-dir "${RIDI_RELEASE_KEY_DIR:-$HOME/.local/share/ridi8-signing/keys}" \
                --image "$product_out/system.img" --out "$product_out/signing-policy.tsv"
            # Key migration RAM image for this exact build (policy + boot security
            # policy embedded). The updater runtime is pinned; see its README.
            signing_runtime="${RIDI_SIGNING_RUNTIME:-$workspace/porting/e70q10/signing-runtime/runtime.zip}"
            if [[ -f "$signing_runtime.sha256" ]]; then
                (cd "$(dirname "$signing_runtime")" && sha256sum -c --quiet "$(basename "$signing_runtime").sha256")
            fi
            rm -f "$product_out/signing-migration.img" "$product_out/signing-migration.img.sha256"
            python3 "$workspace/porting/e70q10/emmc-tool/signing_rescue.py" \
                --folder "$product_out" --runtime "$signing_runtime" \
                --output "$product_out/signing-migration.img"
        fi
        ;;
    *)
        echo "Usage: $0 [check | build [make-target ...]]" >&2
        exit 2
        ;;
esac
