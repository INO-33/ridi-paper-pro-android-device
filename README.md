# E70Q10 Android product status

This tree defines a dedicated NXP i.MX6SL product and selects the reconstructed
E70Q10 DTB. It is a bring-up skeleton, not a flashable product.

For the first SD/RAM boot, use `e70q10_minimal-eng`. It starts from Android's
`core_minimal` product instead of the full NXP EVK product and includes only
the framework, ADB, i.MX6 graphics, touch input files and the graphics HIDL
interfaces. Wi-Fi, Bluetooth, camera, audio, OMX, GMS and consumer apps remain
disabled until the base userspace reaches `sys.boot_completed`.

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
device/ridi/e70q10/tools/build_android8.sh check
device/ridi/e70q10/tools/build_android8.sh build ramdisk
device/ridi/e70q10/tools/build_android8.sh build bootimage
device/ridi/e70q10/tools/make_stock_ramboot.sh
```

The first verified build produced
`out/target/product/e70q10/ramdisk.img` and `boot.img`. The NXP build places
the DTB in the Android boot image `second` field, while the E70Q10 stock U-Boot
and the verified diagnostic images use a kernel-appended DTB. Therefore,
`make_stock_ramboot.sh` creates a separate `second=0` RAM-boot candidate and
never overwrites the standard build output. Build outputs are deliberately
excluded from Git.

Blocking work before an image can be installed:

1. Forward-port Netronix CYTTSP5, LM3630A and RTL8189FS support from
   `reference-sources/tolino-epos/kernel_imx` to Linux 4.9, and production-harden
   the already working RC5T619/TPS65185 ports.
2. The stock waveform, shared ED078KH1/ED078KH3 timing profile, 16-bit EPDC bus
   and PMIC sequence are hardware-verified with white and 16-step GC16 RAM-boot
   refreshes. Finish repeated-update, temperature and suspend/resume validation.
3. Adapt the NXP Oreo composer/gralloc path for EPDC update ioctls and ghosting
   policy.  KitKat HAL binaries are not ABI-compatible.
4. Measure built images and define a recoverable replacement partition map.
5. Prove RAM boot, ADB/serial recovery, suspend/resume and power-off before any
   eMMC write.
