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

The Android build emits sparse `system.img` and `vendor.img` files. Never write
those sparse containers directly to the SD partitions with `dd`; the kernel
cannot mount them as ext4. Convert them first:

```sh
E70Q10_PRODUCT_OUT=/path/to/out/target/product/e70q10 \
E70Q10_SD_RAW_OUT=/path/on/build-disk/sd-ready \
device/ridi/e70q10/tools/prepare_sd_raw_images.sh
```

Only `system.raw.ext4` and `vendor.raw.ext4` are suitable for direct partition
writes. Their expected expanded sizes are the configured partition sizes:
768 MiB and 256 MiB, respectively.

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
patch -p1 < device/ridi/e70q10/patches/0010-native-eink-policy-transport.patch
patch -p1 < device/ridi/e70q10/patches/0011-imx-display-eink-policy.patch
patch -p1 < device/ridi/e70q10/patches/0012-settings-reader-ui.patch
device/ridi/e70q10/tools/build_android8.sh check
device/ridi/e70q10/tools/build_android8.sh build ramdisk
device/ridi/e70q10/tools/build_android8.sh build bootimage
E70Q10_RAMBOOT_PROFILE=minimal \
device/ridi/e70q10/tools/make_stock_ramboot.sh
```

The build helper separates output by product. Reuse the existing reference
output on the ext4 build disk for incremental builds; do not clean it:

```sh
E70Q10_LUNCH=e70q10_reference-eng \
E70Q10_OUT_DIR=/path/on/ext4/android-out/e70q10_reference \
device/ridi/e70q10/tools/build_android8.sh build systemimage vendorimage
```

HWC/gralloc are loaded from `/vendor/lib/hw` on the separate vendor partition.
For framework sleep/wake interface changes, apply `system.img` and `vendor.img`
from the same build together. The helper adds `vendorimage` when `systemimage`
is requested; it does not install either image. Kernel battery fixes also need
`bootimage` and its corresponding `boot.img`.

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

This repository is private, so the device-unique blobs the port cannot be
rebuilt without are committed here:

- `stock-blobs/imx/epdc/epdc_ED078KH1.fw` is the extracted EPDC waveform. The
  reference product copies it to `/vendor/firmware/imx/epdc/`. Without this
  file the EPDC driver stays uninitialized and `MXCFB_SEND_UPDATE` returns
  `EPERM`.
- `prebuilt/8189fs.ko` is the RTL8189FS Wi-Fi kernel module.

Both are extracted from the device and are not redistributable. Keep this
repository private, and do not mirror it to a public remote.

The device boot command line includes `firmware_class.path=/vendor/firmware`.
This lets the kernel cache the existing waveform directly during suspend
preparation, without a firmware uevent waking userspace and aborting freeze.
The normal firmware fallback remains available if vendor is not mounted yet
during early boot. Rebuild/apply `bootimage` for this command-line change;
the existing vendor waveform does not need replacing. On a running device,
`/sys/module/firmware_class/parameters/path` must read `/vendor/firmware`.

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

## Depleted battery shutdown (stock route)

The E70Q10 opt-in PMIC IRQ domain separates charger, VBAT-low and RTC
alarm consumers. Charger debounce masks only its group. Stock VBAT
warning ADC conversion continues in suspend at the recovered 3550mV
threshold; this does not change the PMIC's hard power-cut voltage. A low
event is published only after valid gauge readings and obeys stock's
external-power / greater-than-10-percent false-critical guard.

For `SHUTDOWN_LOW_BATTERY` only, the framework acquires the stock
screen wake lock before launching SystemUI's `ReaderLowBatteryActivity`.
The activity draws the unchanged stock LOW BATTERY asset and replies
after draw plus 500ms. The framework waits up to 5s for an authenticated
reply, then leaves stock's 1500ms panel margin before shutdown broadcasts.
This is a stock-style draw acknowledgement, not a hardware EPDC WAIT.
Normal user shutdown confirmation, its image, reboot and thermal shutdown
retain their existing route. The former LOW BATTERY image branch in
GlobalActionsImpl is removed.

Build/apply matching `bootimage systemimage vendorimage` incrementally.
No data wipe is needed. On the new image, verify `rc5t619-pmic`,
`rc5t619-vbat-low`, and `rc5t619-rtc-alarm` in `/proc/interrupts`,
`rtc0/wakealarm`, and `low_irq` in
`/sys/bus/platform/devices/rn5t618-power/stock_soc`. Normal shutdown UI
can be checked independently. Controlled low-voltage wake and actual
final-panel display still require hardware validation; do not infer them
from source/harness tests.

## Build number shown in Settings

Physical E70Q10 products show `YYYY.MM.DD-juwon` (for example,
`2026.10.15-juwon`). The date follows `BUILD_DATETIME` in `Asia/Seoul`.
`TARGET_BUILD_DISPLAY_ID` in `BoardConfig.mk` changes only
`ro.build.display.id`; internal incremental number, fingerprint, build tags
and emulator products retain their existing values. Build `systemimage`
(the helper also includes matching `vendorimage`); no clean is needed.

## Stock bootloader command-line bound

Stock `ntx_prebooti` builds `setenv bootargs` in a 500-byte stack buffer
without a length check. E70Q10 therefore limits the image command line to
240 bytes, including buildvariant. The failed 281-byte image plus the
observed 234-byte NTX suffix exceeded that buffer; a 232-byte header with
identical kernel/DTB/ramdisk reached the Android boot logo with PMIC enabled.
The console alias, duplicated NTX memory size and default loglevel were
removed; the suspend firmware path remains. Core make rejects longer
commands before producing boot.img. GUI/eMMC conversion also removes only
those known redundant tokens from old long headers, then rejects anything
still over 240 bytes. No kernel/PMIC driver rollback is required for this fix.
Rebuild `bootimage`, or relaunch the updated Python GUI and prepare the SD
again from the existing raw images. Merely reusing the previous SD payload
does not apply the header fix.

The shared PMIC IRQ thread also sleeps for 20ms on an interrupt with no
enabled child source, after releasing its mutex. IRQF_ONESHOT keeps the
physical line masked during that pause. This lets the normal-priority
charger debounce worker acknowledge a masked latched factor; real ADC/RTC
factors remain latched for the next dispatch. No RTC polling timer is added.
The source needs a new `bootimage`; the successful header-only RAM replay
did not include this later IRQ backoff.

## Retaining the final power-off frame

Normal/null-reason and user-requested shutdowns now use the same trusted
draw acknowledgement and stock 1500ms margin as the low-battery route.
The normal confirmation and normal power-off image remain unchanged; only
low battery launches ReaderLowBatteryActivity. After an authentic draw
reply and margin, sys.ridi.shutdown.freeze stops EPDC framebuffer posts
before window/service teardown can replace the image. Missing UI times
out after 5s and does not freeze an unconfirmed frame. Reboot and thermal
reasons keep the previous framework behavior. Ordinary frames do not wait.
The EPDC shutdown callback uses the existing suspend drain/hardware-idle/
powerdown sequence before cutting panel rails, with a logged bounded
force-off fallback if the drain fails. This changes no sleep transition
submission/alpha blending/normal dirty scanning logic.
Build matching `bootimage systemimage vendorimage`. Repeated normal and
low-battery shutdown retention still needs device validation; source/API
checks do not establish physical panel retention on a failing device.

### Charger detach reporting and nested IRQ masking (2026-10-15)

The RC5T619 nested IRQ chip implements `irq_disable` with its group mask
callback. Linux 4.9 otherwise uses lazy disable; `handle_nested_irq` skips a
disabled child without masking its hardware group. A latched charger event
can consequently keep the FIFO parent busy, starving its debounce worker,
healthd and other regmap readers. Only the disabled group is masked; ADC
low-voltage and RTC wake sources remain enabled. The existing empty-source
20 ms backoff is retained.

Cable status notification and charger IRQ recovery run even when a raw SOC
read or validated gauge sample fails. The last valid capacity is retained;
a CHGSTATE read failure does not invent a detach. No new suspend poll timer
is added. Build target: `bootimage`. Actual-source tests reproduce the old
lazy-mask failure and verify immediate masking, recovery and independent
cable updates. These source changes still require a new boot image and
physical cable attach/detach verification.
