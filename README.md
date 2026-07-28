# E70Q10 Android product status

This tree defines a dedicated NXP i.MX6SL product and selects the reconstructed
E70Q10 DTB. Android 8 reaches `sys.boot_completed=1` using RAM boot and the
external-SD system/vendor/data partitions. It remains a recovery-oriented
bring-up tree, not an eMMC-flashing procedure.

For the first SD/RAM boot, use `e70q10_minimal-eng`. It starts from Android's
`core_minimal` product instead of the full NXP EVK product and includes only
the framework, ADB, i.MX6 graphics, touch input files and the graphics HIDL
interfaces. Wi-Fi, Bluetooth, camera, audio, OMX, GMS and consumer apps remain
disabled until the base userspace reaches `sys.boot_completed`.

See [`FEATURE_PRUNING_PLAN.md`](FEATURE_PRUNING_PLAN.md) for the hardware-based
package policy and the planned minimal, reader and production product profiles.
The updated execution order and YES24/Total Launcher target are documented in
[`FINAL_PORTING_PLAN.md`](FINAL_PORTING_PLAN.md). The verified NXP graphics
call path is documented in [`GRAPHICS_EPDC_PATH.md`](GRAPHICS_EPDC_PATH.md).
The first complete reference image hashes and sizes are recorded in
[`BUILD_RESULTS.md`](BUILD_RESULTS.md).

The minimal fstab refers only to external SD partitions:

- `mmcblk1p2`: read-only `/system`
- `mmcblk1p3`: read-only `/vendor`
- `mmcblk1p4`: writable `/data`

Internal eMMC (`mmcblk0`) is intentionally absent. The minimal init starts the
hardware watchdog with a 30-second timeout and the kernel command line requests
an automatic reboot ten seconds after a panic.

## Reproduce the minimal build

Copy this directory to `device/ridi/e70q10` in NXP
`o8.0.0_1.0.0-ga`, then apply all files under `patches/` from the Android
source root. The patches remove an include for an unavailable private NXP
codec, make legacy compiler wrappers find the local Python 2 runtime, and
allow old kernel host tools to build with a modern GCC.

```sh
patch -p1 < device/ridi/e70q10/patches/0001-android8-modern-host-python.patch
patch -p1 < device/ridi/e70q10/patches/0002-build-without-private-fsl-codec.patch
patch -p1 < device/ridi/e70q10/patches/0003-kernel-host-fcommon.patch
patch -p1 < device/ridi/e70q10/patches/0004-surfaceflinger-fix-hwc1-framebuffer-post.patch
patch -p1 < device/ridi/e70q10/patches/0005-gralloc-log-epdc-update-latency.patch
patch -p1 < device/ridi/e70q10/patches/0006-documentsui-fix-usb-shortcut-color.patch
patch -p1 < device/ridi/e70q10/patches/0007-framework-eink-policy.patch
patch -p1 < device/ridi/e70q10/patches/0008-mesa-android-softpipe.patch
patch -p1 < device/ridi/e70q10/patches/0009-pixelflinger-clip-raster-bounds.patch
device/ridi/e70q10/tools/build_android8.sh check
device/ridi/e70q10/tools/build_android8.sh build ramdisk
device/ridi/e70q10/tools/build_android8.sh build bootimage
E70Q10_RAMBOOT_PROFILE=minimal \
device/ridi/e70q10/tools/make_stock_ramboot.sh
```

The build helper separates output by product. After attaching an ext4 build
disk, use a clean reference output directory:

```sh
E70Q10_LUNCH=e70q10_reference-eng \
E70Q10_OUT_DIR=/path/on/ext4/android-out/e70q10_reference \
device/ridi/e70q10/tools/build_android8.sh build systemimage vendorimage
```

Build the reference stock-U-Boot RAM-boot candidate from the same output:

```sh
E70Q10_OUT_DIR=/path/on/ext4/android-out/e70q10_reference \
E70Q10_RAMBOOT_PROFILE=reference \
device/ridi/e70q10/tools/make_stock_ramboot.sh
```

The first verified build produced
`out/target/product/e70q10/ramdisk.img` and `boot.img`. The NXP build places
the DTB in the Android boot image `second` field, while the E70Q10 stock U-Boot
and the verified diagnostic images use a kernel-appended DTB. Therefore,
`make_stock_ramboot.sh` creates a separate `second=0` RAM-boot candidate and
never overwrites the standard build output. Build outputs are deliberately
excluded from Git.

Graphics backend selection, the AGL/GLES1 recovery path, and the isolated
Mesa softpipe benchmark procedure are documented in
[`GRAPHICS_BRINGUP.md`](GRAPHICS_BRINGUP.md).

The reference product uses the positive package allowlist in
`e70q10_reader_base.mk`. It deliberately avoids `generic_no_telephony`, which
still pulls phone, Bluetooth, NFC, printing, PIM, music and decoration apps
into an AOSP Oreo image. Launcher2 remains only as a recovery HOME until Total
Launcher is packaged as a system application.

Current validation work:

1. Build and deploy the static E Ink framework policy: no starting windows,
   transitions, recents, lock screen, ripple or animated drawables.
2. Validate gralloc's changed-region EPDC path: unchanged frames are skipped,
   small changes use partial AUTO updates, and large or accumulated changes use
   full GC16 cleanup updates.
3. Tune partial-update thresholds, temperature handling and suspend/resume.
4. Bring up RTL8189FS Wi-Fi and finish CYTTSP5 input validation.
5. Keep all tests on `fastboot boot` plus external SD until recovery and
   power-management behavior are proven.
