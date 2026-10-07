# E70Q10 post-build verification checklist

Companion to `PERF_TUNING_ROLLBACK.md`. That file says how to undo things; this
one says what to check and, for the parts that were derived by reading source
rather than by measurement, what to do when the check disagrees.

Nothing in the current change set has been built or booted. Every item below is
unverified until someone runs it.

Expect the **first** boot after writing a new image to be slow: applications are
not dexpreopted at build time, so the device runs `dex2oat` once and caches the
result in `/data/dalvik-cache`. Do not judge any of the tuning until that has
finished (see D4).

```bash
ADB="/home/juwon/ridi/host-tools/android-platform-tools/platform-tools/adb -s PP1A1ID154423"
OUT=/media/juwon/build/android-out/e70q10_reference_agl_stockpath/target/product/e70q10
KO=$OUT/obj/KERNEL_OBJ
```

---

## A. Host-side checks, before flashing

### A1. Kernel config actually carries the changes

`$(KERNEL_OUT)/.config` is the config the kernel was really built from, so read
that rather than the defconfig.

```bash
grep -E "^CONFIG_CPU_FREQ_DEFAULT_GOV_INTERACTIVE|^CONFIG_CPU_FREQ_GOV_ONDEMAND|^CONFIG_CPU_FREQ_STAT|^CONFIG_NR_CPUS|^CONFIG_CRYPTO_LZ4|^CONFIG_SWAP|^CONFIG_ZRAM" $KO/.config
```

Expect all seven. `CONFIG_CPU_FREQ_GOV_ONDEMAND=y` matters as much as the rest:
it is no longer selected by the default-governor choice, so if it is missing the
runtime A/B comparison and the rollback in `PERF_TUNING_ROLLBACK.md` are both
impossible.

### A2. system.img size should be roughly unchanged

Nothing in this change set grows the system image. Application dexpreopt is
deliberately off (see `BoardConfig.mk`: the host `dex2oat` cannot load the target
boot image under current kernel ASLR), so no application odex is produced.

```bash
ls -l $OUT/system.img          # expect ~439 MB, partition limit is 768 MB
```

A noticeably larger image means something re-enabled build-time dexpreopt. Check
that neither `WITH_DEXPREOPT_BOOT_IMG_ONLY` nor `PRODUCT_DEXPREOPT_SPEED_APPS` has
crept back in:

```bash
grep -rn "WITH_DEXPREOPT_BOOT_IMG_ONLY\|PRODUCT_DEXPREOPT_SPEED_APPS" \
    device/ridi/e70q10/*.mk | grep -v "^.*:#"
```

### A3. Only the boot image is preopted, and no application is

This is the expected state, not a defect.

```bash
ls $OUT/system/framework/arm/ | grep -c "boot.*\.oat"     # non-zero
find $OUT/system/app $OUT/system/priv-app -name "*.odex" | wc -l   # expect 0
```

Applications are compiled by the device itself on the first boot after the image
is written, into `/data/dalvik-cache`, and that cache is reused on later boots.
The consequence to plan for is a slow **first** boot, not a permanently slow
device.

### A4. New properties landed in build.prop

```bash
grep -E "ro.config.low_ram|dalvik.vm.heap" $OUT/system/build.prop
```

Expect `ro.config.low_ram=true` plus the six `dalvik.vm.heap*` values from
`phone-xhdpi-1024-dalvik-heap.mk`. Neither existed before.

### A5. Ramdisk carries the init and fstab edits

`systemimage` alone does not pick these up; they are `PRODUCT_COPY_FILES` into
`root/`.

```bash
mkdir -p /tmp/rdcheck && cd /tmp/rdcheck
gzip -dc $OUT/ramdisk.img | cpio -idmv 2>/dev/null
grep -n "scaling_governor\|swapon_all" init.E70Q10.rc
grep -n "zram0" fstab.E70Q10
```

---

## B. First boot smoke test

Two changes here can plausibly stop the device booting or leave it without a UI,
so check these before anything else.

### B1. It boots and SystemUI survives

```bash
$ADB wait-for-device
$ADB logcat -d -b crash | tail -40
$ADB shell 'getprop sys.boot_completed'
```

`ro.config.low_ram=true` is new. It makes `ActivityManager.isHighEndGfx()` return
false, which in stock code skips `mView.setBackground(mBarBackground)` in
`BarTransitions`. That was patched to also install the background when
`config_fixedColorSystemBars` is set, but the patch has never run.

### B2. Status bar and nav bar are still white with black icons

```bash
$ADB shell 'dumpsys SurfaceFlinger | grep -iE "StatusBar|NavigationBar" | head'
```

If the bars come up transparent or dark, the `isFixedColor()` gate in
`frameworks/base/packages/SystemUI/src/com/android/systemui/statusbar/phone/BarTransitions.java`
did not take effect. Quickest confirmation is to set `ro.config.low_ram=false`
in `e70q10_eink_defaults.mk` and rebuild `systemimage`: if the bars return, the
gate is the problem and not something else.

### B3. Swap came up rather than being skipped

```bash
$ADB shell 'cat /proc/swaps'
```

`fs_mgr_swapon_all` bails out of a swap entry entirely (`ret = -1; continue`) if
it cannot open `/sys/block/zram0/max_comp_streams`. An empty `/proc/swaps` means
the entry was skipped, not that zram is merely idle.

---

## C. Items derived from source that need empirical confirmation

These are the ones to distrust. Each row says how the conclusion was reached, so
that a disagreement points at a specific piece of reasoning.

### C1. interactive tunable path (highest risk)

**Assumed:** tunables live at `/sys/devices/system/cpu/cpufreq/interactive/`, the
global cpufreq kobject.

**Derivation:** `cpufreq_interactive.c` passes
`get_governor_parent_kobj(policy)` to `kobject_init_and_add`, and
`cpufreq.c:129-135` returns `cpufreq_global_kobject` when
`have_governor_per_policy()` is false. `imx6q-cpufreq.c:257` sets only
`.flags = CPUFREQ_NEED_INITIAL_FREQ_CHECK`, so the per-policy flag is absent.

**Check:**

```bash
$ADB shell 'ls -d /sys/devices/system/cpu/cpufreq/interactive 2>/dev/null || echo global-absent'
$ADB shell 'ls -d /sys/devices/system/cpu/cpu0/cpufreq/interactive 2>/dev/null || echo perpolicy-absent'
$ADB shell 'cat /sys/devices/system/cpu/cpufreq/interactive/go_hispeed_load'   # expect 85
$ADB shell 'cat /sys/devices/system/cpu/cpufreq/interactive/target_loads'      # expect 80
$ADB shell 'cat /sys/devices/system/cpu/cpufreq/interactive/io_is_busy'        # expect 1
```

**If the values are the stock 99 / 90 / 0**, the writes went nowhere. init's
`write` failures are non-fatal, so nothing else signals this. Confirm with:

```bash
$ADB shell 'dmesg | grep -i "cpufreq/interactive"'
```

**Fix:** change the eight tunable paths in `init.E70Q10.rc` from
`/sys/devices/system/cpu/cpufreq/interactive/` to
`/sys/devices/system/cpu/cpu0/cpufreq/interactive/` and rebuild `ramdisk`. The
governor itself is unaffected, because it is now the kernel default rather than
something init has to set.

### C2. The governor is interactive from boot

**Assumed:** `CONFIG_CPU_FREQ_DEFAULT_GOV_INTERACTIVE=y` means interactive
governs from the moment cpufreq registers the policy, and the redundant init
write is harmless because `store_scaling_governor` returns early when the
governor is unchanged.

**Check:**

```bash
$ADB shell 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor'
$ADB shell 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors'
```

Expect `interactive`, and the available list to contain at least `interactive`,
`ondemand`, `performance`, `conservative`, `powersave`, `userspace`.

### C3. ondemand's real up_threshold

**Assumed:** ondemand was resolving to `up_threshold` 95, not 80. This depends on
`get_cpu_idle_time_us()` returning a value at runtime
(`cpufreq_ondemand.c:370-385`), which cannot be settled by reading source.

This only matters for describing the before state accurately. Now that interactive
is the boot default, read it by switching back temporarily:

```bash
$ADB root
$ADB shell 'echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor'
$ADB shell 'cat /sys/devices/system/cpu/cpu0/cpufreq/ondemand/up_threshold'    # 95 or 80
$ADB shell 'cat /sys/devices/system/cpu/cpu0/cpufreq/ondemand/sampling_rate'   # expect ~61000
$ADB shell 'echo interactive > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor'
```

### C4. zram size and compressor

**Assumed:** `zramsize=25%` is resolved by `fs_mgr` against `_SC_PHYS_PAGES`
(`fs_mgr_fstab.cpp:150-156`) and written to `/sys/block/zram0/disksize`. The
actual byte count was never computed, because how much of the 1018 MB the kernel
reports as usable is unknown.

```bash
$ADB shell 'cat /sys/block/zram0/disksize'
$ADB shell 'cat /proc/meminfo | head -3'
$ADB shell 'cat /sys/block/zram0/comp_algorithm'
```

`comp_algorithm` shows the active choice in brackets. Expect `[lz4]` on a kernel
built after `CONFIG_CRYPTO_LZ4=y` landed; `[lzo]` means the
`write /sys/block/zram0/comp_algorithm lz4` in `on post-fs` failed, which is the
documented behaviour on an older kernel but a real problem on a new one.

**Assumed:** writing `max_comp_streams` is a no-op that cannot fail, because
`max_comp_streams_store` in this kernel just returns `len`. If `/proc/swaps` is
empty (see B3) this assumption is the first thing to re-check.

### C5. swapon_all ordering

**Assumed:** placing `swapon_all` in `on post-fs` is late enough, because
`fs_mgr` execs `/system/bin/mkswap` (`fs_mgr.cpp:64`) and `/system` is mounted by
`mount_all` in `on fs`.

If `/proc/swaps` is empty, look for the mkswap failure:

```bash
$ADB shell 'dmesg | grep -iE "mkswap|swapon|zram"'
```

`mkswap failed for /dev/block/zram0` means the ordering assumption is wrong and
the call needs to move later, for example into `on post-fs-data`.

### C6. Frontlight brightness curve

The kernel fix in `lm3630a_bl.c` splits the *level* by colour weight instead of
splitting the compressed LUT's PWM code. It has never been built.

```bash
$ADB shell 'echo 50 > /sys/class/backlight/lm3630a_led/brightness'
$ADB shell 'cat /sys/class/backlight/lm3630a_led/brightness'
```

Sweep brightness 10 to 100 at colour 0, then repeat at colour 5 and colour 10.
The failure being fixed was a collapse in total output in the middle of the
range, so watch for perceived brightness dropping as the number rises.

### C7. Screensaver full-screen page

`RidiScreensaverSettingsActivity` and its three layouts are new and have only
been type-checked against the built framework jars.

```bash
$ADB shell 'am start -n com.android.settings/.ridi.RidiScreensaverSettingsActivity'
$ADB shell 'uiautomator dump /sdcard/ss.xml' && $ADB shell 'cat /sdcard/ss.xml' | tr '>' '>\n' | grep -oE 'text="[^"]+"'
```

Expect the master switch, the three style rows and the battery row. The point of
the change was that the previous `AlertDialog` left the panel showing stale
pixels, so also confirm the page renders as one clean update rather than in
strips.

### C8. Nav bar four keys and black icons

The `values-sw600dp` overlay was added because the panel reports
`smallestScreenWidthDp=748`, so the AOSP `sw600dp` config was winning over the
`values` overlay. Not yet booted.

```bash
$ADB shell 'dumpsys window | grep -i navigationbar | head -3'
```

Expect four keys: back, home, frontlight, refresh. Icons should be black on
white; if they look like faint outlines, the `darkIntensity` forcing in
`NavigationBarTransitions.applyDarkIntensity()` is not taking effect.

---

## D. Measurements that make the tuning real

None of the three changes can be called an improvement without these. Do each
before and after, on the same task, from the same starting state.

### D1. Frequency residency

`CONFIG_CPU_FREQ_STAT=y` was added for this. The stock 4.4.2 kernel had it; this
port did not.

```bash
$ADB shell 'cat /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state'
```

Three rows, for 396000 / 792000 / 996000. Read it, do a fixed task such as ten
page turns, read it again, and compare the deltas. Time spent at 396000 dropping
in favour of 792000/996000 is the intended effect.

If the directory is missing, the kernel in the flashed boot image predates the
defconfig change.

### D2. Is the CPU the bottleneck at all

`CONFIG_CPU_FREQ_GOV_PERFORMANCE=y` is now available as a side effect of the
default-governor choice selecting it. An earlier audit recorded it as
unavailable; that is no longer true.

```bash
$ADB shell 'echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor'
# repeat the task
$ADB shell 'echo interactive > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor'
```

If pinning to 996 MHz changes nothing perceptible, the bottleneck is the EPDC
update path or storage, and further governor tuning is wasted effort.

### D3. Memory pressure and swap usage

```bash
$ADB shell 'cat /sys/block/zram0/mm_stat'    # orig_data / compr_data / mem_used
$ADB shell 'dmesg | grep -i lowmemorykiller | tail -20'
```

`zramsize=25%` was chosen conservatively because every swap-in costs
decompression on the only core. Raise it if lmkd is still killing recent apps;
lower it if interaction stutters under pressure.

### D4. App start cost, and let the first boot finish first

```bash
$ADB shell 'am start -W -n com.android.settings/.ridi.RidiReaderSettingsActivity'
```

`TotalTime` from a cold start is the number to compare, but **only after on-device
dexopt has finished**. The device compiles every application once on the first
boot after a new image, so measurements taken during that window describe dex2oat
competing for the single core, not the tuning.

Confirm the cache is populated and settled before measuring:

```bash
$ADB shell 'ls /data/dalvik-cache/arm | head'
$ADB shell 'dumpsys package dexopt | head -40'
$ADB shell 'ps -A | grep dex2oat'      # expect nothing
```

If `dex2oat` is still running, wait. Comparing a first boot against a warm boot
is the easiest way to produce a meaningless result here.

### D5. WebView multiprocess is off

```bash
$ADB shell 'ps -A | grep -i webview'
$ADB shell 'dumpsys webviewupdate | grep -i multiprocess'
```

Expect no `webview_zygote32` process and multiprocess reported disabled. The
backported Android 9 rule
(`Build.SUPPORTED_64_BIT_ABIS.length > 0 || !isLowRamDeviceStatic()`) evaluates
false here only because `ro.config.low_ram=true` is now set, so this check also
confirms the property is live.

---

## E. Regression checks for the UI work in this image

These were changed earlier in the session and ride along in the same build.

```bash
# 12/24h clock option and battery percentage
$ADB shell 'settings get system time_12_24; settings get system status_bar_show_battery_percent'

# notification shade must not pull down
$ADB shell 'cmd statusbar expand-notifications' ; $ADB shell 'dumpsys window | grep -i "StatusBar.*EXPANDED"'

# settings pages that previously crashed or looked broken
$ADB shell 'am start -n com.android.settings/.Settings\$DeviceInfoSettingsActivity'
$ADB shell 'am start -n com.android.settings/.ridi.RidiFrontlightActivity'

# Korean IME
$ADB shell 'ime list -s'
```

The device info page was confirmed working before this build; the others were
not.

---

## What was already verified, and how

So the list above is not treated as uniformly uncertain:

- Kernel config values were checked by resolving the defconfig into a scratch
  directory (`make O=/tmp/kcfg ARCH=arm e70q10_defconfig`) and reading the
  produced `.config`, not by reading the defconfig
- `CONFIG_SWAP=y` was proven this way, correcting an earlier note that claimed
  the kernel lacked it
- The Settings `ridi` package and the modified `BarTransitions.java` were
  compiled with `javac` against the real `framework`, `core-oj` and `core-libart`
  jars from the previous build: zero errors
- All new and edited XML was parsed for well-formedness
- init builtin arities (`write` takes 2, `swapon_all` takes 1) and the five-field
  fstab format were read from `system/core`
- `oatdump`, `dexdump` and `dex2oat` are all present in the image, so the
  on-device dexopt checks above are runnable

None of that says anything about runtime behaviour.

## One earlier conclusion that was wrong

An intermediate version of this work claimed that, because the image contains zero
application `.odex` files, SystemUI and Settings are "interpreted and JIT-compiled
on every boot", and enabled build-time dexpreopt to fix it.

That was incorrect on both counts. The device compiles applications itself once,
during the first boot after a new image, and reuses `/data/dalvik-cache`
afterwards. And build-time dexpreopt cannot run on this host at all, because the
host `dex2oat` must map the target boot image at its fixed base address while
`-Xnorelocate` forbids relocation, and current kernel ASLR ignores the hint.

Both the change and the reasoning were reverted. `BoardConfig.mk` and
`e70q10_reader_base.mk` carry the explanation as comments, and
`PERF_TUNING_ROLLBACK.md` section 3 records it so the idea is not retried.
