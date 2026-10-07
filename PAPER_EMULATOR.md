# E70Q10 Paper Emulator

This target runs the RIDI-specific Android 8 framework on the x86 Goldfish /
Ranchu emulator with KVM acceleration.  It is a userspace integration and
latency-comparison target, not an i.MX6SL board emulator.

## What it validates

- layout equivalent to 1404 x 1872 at 320 dpi
- RIDI framework behaviour without ARM instruction-translation overhead
- RIDI / Onyx `android.view.View` E Ink compatibility methods
- per-frame E Ink mode transport through SurfaceFlinger and HWC1
- application, SystemUI, permission, Java, native and ANR failures
- scripted touch, swipe and key input through Android InputManager

The virtual EPDC emits `PAPER_EPDC` logcat records.  Each record includes the
packed policy, decoded waveform/full/partial/wait state and surface-damage
bounds.  It still posts the ordinary framebuffer to the emulator window.

## What it cannot validate

EPDC register timing, waveform quality, physical ghosting, TPS65185 sequencing,
CYTTSP5 I2C/IRQ/reset timing, suspend/resume, ARMv7-only native libraries and
device performance still need E70Q10 hardware or a separate ARM test target.

The runner defaults to a half-scale 702 x 936 framebuffer at 160 dpi. This
preserves the real device's 702 x 936 dp layout space while keeping the x86
comparison guest lightweight and making no claim about panel quality.

## Build and run

```sh
device/ridi/e70q10/tools/build_paper_emulator.sh build
device/ridi/e70q10/tools/run_paper_emulator.sh
```

`PAPER_EMULATOR_OUT_DIR` always names the build output root, for example
`/media/juwon/build/paper-emulator-x86`; the runner resolves its
`target/product/e70q10_emulator` subdirectory automatically.

`build` produces the complete emulator image (`droid`).  To compile only the
virtual display HAL while iterating on it, use:

```sh
device/ridi/e70q10/tools/build_paper_emulator.sh build hwcomposer.ranchu
```

The build wrapper gives Oreo's host `dex2oat` a private `ANDROID_DATA` under
the selected output directory. It never creates or modifies the host `/data`.
Only the boot class path is preoptimized on the host; applications are compiled
into the emulator's `/data` on first boot. This avoids obsolete fixed-address
mapping assumptions in Oreo's host `dex2oat` on current Linux kernels.

The runner accepts normal emulator arguments.  For a headless run:

```sh
device/ridi/e70q10/tools/run_paper_emulator.sh -no-window
```

After Android has booted, install and launch the extracted RIDI application:

```sh
device/ridi/e70q10/tools/test_ridi_app.sh
```

Useful logs:

```sh
adb logcat -s PAPER_EPDC E70Q10_VIEW AndroidRuntime ActivityManager
adb shell dumpsys SurfaceFlinger
```

## ARMv7 compatibility target

The ARMv7 target is separate from the x86 target and the physical product. It
uses software CPU translation on an x86 host, so it is useful for ABI and
ARM-only behaviour checks but not for performance comparisons.

```sh
device/ridi/e70q10/tools/build_paper_emulator_armv7.sh build
device/ridi/e70q10/tools/run_paper_emulator_armv7.sh
```

Its default output is `/media/juwon/build/paper-emulator-armv7`. The existing
x86 output can be removed independently when disk space is needed.
