# RIDI Paper Pro E70Q10 Android 8 final porting plan

## Product goal

The target is a small, recoverable Android 8.0 e-reader environment for:

- the YES24 e-book application;
- Total Launcher as the eventual home application;
- a portrait 1404 x 1872 E Ink display;
- Wi-Fi station mode;
- external-SD-root validation before any eMMC write.

The stock RIDI application is reference material only. It is not a product
requirement. No RIDI-specific package should be retained unless it provides a
hardware function that YES24 or Android still needs.

Total Launcher and the YES24 APK are not currently present in the workspace.
They must be supplied from a legitimate source before application integration.

## Facts confirmed in the checked-out NXP Oreo source

This plan follows the source tree rather than generic Android version tables.

- The tree provides graphics allocator 2.0, mapper 2.0 and composer 2.1.
- `device/fsl/evk_6sl/manifest.xml` declares mapper 2.0.
- The NXP i.MX6SL default selects gralloc v3 and HWC v2.0, but that path
  requires the unavailable private `g2dExt.h` and corresponding `libg2d`.
- The explicit EPDC `MXCFB_SEND_UPDATE` implementation is in
  `vendor/nxp-opensource/imx/display/gralloc_v1/framebuffer.cpp`.
- The default gralloc v3/HWC v2 path does not call that EPDC update routine.
- The composer 2.1 default implementation can adapt HWC 1.1 or newer through
  `HWC2On1Adapter`, but cannot adapt NXP's HWC 1.0 module.
- NXP HWC 1.3 is adaptable but its `FbDisplay::updateScreen()` currently only
  performs normal framebuffer update/pan operations.
- The current resolved kernel configuration creates
  `binder,hwbinder,vndbinder` and includes Binder, ashmem, ION, CMA, zRAM,
  SELinux, seccomp, cgroups, ext4 and FUSE.
- The NXP public tree lacks some private FSL codec headers and binaries, so an
  unmodified full EVK product is not a reproducible baseline here.

Consequently, the practical reference baseline is an open-source
`generic_no_telephony` Android framework plus the known NXP graphics stack and
E70Q10-safe init/fstab. It is not the complete, proprietary EVK image.

## Non-destructive boot definition

“RAM boot” means:

- fastboot loads kernel, appended DTB and the small Android ramdisk into RAM;
- `/system`, `/vendor` and `/data` live on ext4 partitions on the work SD;
- internal eMMC (`mmcblk0`) is absent from the fstab and is not written;
- kernel panic and watchdog paths return the device to a recoverable state.

It does not mean loading complete system and vendor images into the device's
1 GiB RAM.

## Product profiles

### Phase 0: `e70q10_minimal`

Purpose: prove Android init, ADB and the kernel/userspace contract.

- `core_minimal`, E70Q10 kernel/DTB and safe SD fstab
- graphics HIDL skeleton, touch, buttons, watchdog and verbose logging
- no Wi-Fi and no reader applications

Exit criteria:

- repeatable non-destructive boot and responsive ADB for 30 minutes
- no kernel panic or uncontrolled reboot
- binder, hwbinder and vndbinder device nodes present
- eMMC not mounted or modified

### Phase 1: `e70q10_reference`

Purpose: establish a known Android framework/UI baseline before pruning.

- AOSP `generic_no_telephony` framework and applications
- SystemUI, Settings and a temporary AOSP launcher
- NXP allocator/mapper, gralloc v1 and HWC1 modules
- compatibility audio framework with a default/null hardware path
- E70Q10-safe init, fstab, input and graphics manifest
- all three Android animation scales forced to zero

This profile deliberately retains more framework services than the final
reader. It must not inherit unsafe EVK partition/verity files or unavailable
private codec payloads.

Exit criteria:

- stable Zygote, system_server and SurfaceFlinger
- `sys.boot_completed=1` and temporary launcher displayed
- ADB responsive for 30 minutes
- package, service, RAM and image-size baselines recorded

### Phase 2: SurfaceFlinger-to-EPDC path

Use the source-complete legacy graphics architecture for initial bring-up:

```text
SurfaceFlinger
  -> direct HWC1 path
  -> NXP HWC 1.0
  -> EGL swap
  -> NXP gralloc v1 framebuffer post
  -> MXCFB_SEND_UPDATE
  -> E70Q10 EPDC driver
```

This bypasses composer HIDL for the initial display path. Allocator/mapper HIDL
remain for Oreo buffer allocation, while SurfaceFlinger is compiled with the
tree's supported HWC1 implementation. HWC2 migration is a later optimization,
not a first-boot requirement.

Initial update policy:

- full-screen high-quality update for every accepted frame
- one outstanding update at a time
- correctness before latency
- move completion waits off the SurfaceFlinger thread after correctness

Exit criteria:

- launcher appears and touch/display coordinates match
- every accepted frame eventually reaches EPDC
- no SurfaceFlinger/composer restart loop
- update queue cannot defeat watchdog recovery

### Phase 3: measured pruning

Starting from the working reference, remove one category at a time:

- telephony remnants, Bluetooth, NFC and location
- camera, printing, live wallpapers and dreams
- unused voice/TTS packages
- tests, samples and NXP debug utilities
- A/B updates, Wi-Fi Direct, SoftAP and tethering

For each change record package/image-size delta, boot result, boot time, logcat
regressions and RAM delta. Convert to a positive allowlist only after measured
reference-to-reader reduction.

### Phase 4: YES24 reader integration

Add:

- RTL8189FTV station-mode Wi-Fi
- RTC verification, network time, TLS and keystore/keymaster
- DownloadProvider, DocumentsUI, ExternalStorageProvider and MediaProvider
- Korean/English fonts and input
- WebView until YES24 workflows prove it unnecessary
- YES24 APK and its observed DRM/native dependencies

YES24 analysis must cover SDK level, ARM ABI, WebView, Keystore, MediaDrm versus
proprietary DRM, device identifiers, certificate pinning, root/debug checks and
sensor/audio/storage requirements.

Do not remove AudioService/AudioFlinger initially. Use a null/default hardware
path so YES24 API calls remain compatible, then remove codecs and auxiliary
HALs only after measurement.

### Phase 5: Total Launcher and E Ink UX

Total Launcher replaces the temporary launcher only after its APK and HOME
intent are proven. Keep a fallback launcher until crash recovery works.

System defaults:

- no boot, window, transition or animator animation
- no haptic or UI sound effects
- portrait fixed and automatic rotation disabled
- no live wallpaper or animated screen decoration

Total Launcher must also disable its own page transitions, scrolling wallpaper
and continuously updating widgets.

EPDC policy then evolves from full GC16 updates to fast partial updates,
page-quality updates, damage coalescing and periodic full refresh. Completion
waits must be managed by a worker rather than blocking SurfaceFlinger.

### Phase 6: production and eMMC decision

- `user` build, release signing and SELinux enforcing
- secure/disabled ADB
- recovery and rollback path
- suspend/resume, shutdown and charging validation
- 500-page-turn memory and ghosting test
- final 8 GB storage budget
- only then consider recoverable eMMC installation

## Quantitative validation

Record:

- `MemAvailable` after boot and with YES24 open
- system_server, SurfaceFlinger, SystemUI, launcher and YES24 PSS
- zRAM, low-memory kills and major page faults
- PSS growth after 500 page turns
- system/vendor/data and WebView oat/vdex size
- YES24 installation and book-cache size

Initial targets, subject to measurement:

- 250–300 MiB available after reference boot
- 100–150 MiB available while YES24 is reading
- no sustained PSS growth or launcher/SystemUI restart loop

## PC build-storage policy

Current measurements show 4.7 GiB in the existing Android output directory and
only about 27 GiB free on the internal filesystem. This is enough for targeted
module/configuration checks, but not a safe margin for a full reference build.

Before building reference `systemimage` and `vendorimage`, attach the 512 GB
storage as ext4 with at least 100 GiB free, preferably 150 GiB. Give the
reference product its own external `OUT_DIR` so it cannot mix stale artifacts
with `e70q10_minimal`; put optional ccache there too. Keep source in place
unless later measurement requires moving it. Avoid exFAT/NTFS because AOSP
needs Unix permissions, symlinks and reliable case-sensitive behaviour.

## Immediate execution order

1. **Done:** add and statically validate the safe `e70q10_reference` product.
2. **Done:** install E Ink animation defaults for minimal and reference.
3. **Done at module level:** build the source-complete NXP
   gralloc-v1/HWC1/SurfaceFlinger path.
4. **Next:** instrument gralloc framebuffer post and EPDC update completion.
5. Build and statically validate reference ramdisk/boot components.
6. Attach external build storage.
7. Build reference system/vendor images in a clean external `OUT_DIR`.
8. Prepare SD ext4 partitions and perform non-destructive Android boot.
9. Integrate YES24 and Total Launcher after the baseline is stable.

Current targeted-build artifacts confirm that `gralloc.imx6.so`,
`hwcomposer.imx6.so` and the HWC1 SurfaceFlinger binary can be produced. The
gralloc binary contains the EPDC framebuffer detection path. A later
`SettingsProvider` target attempt stopped before compilation because the old,
shared output directory lacked its Soong executable; this is why subsequent
builds use a clean product-specific output directory rather than repairing or
mixing that stale tree.
