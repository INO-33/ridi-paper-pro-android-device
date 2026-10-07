# E70Q10 performance tuning: what changed and how to undo it

Two low-spec tuning changes were applied: the CPU governor and zram, plus a
smaller `NR_CPUS` correction. None of them has been run on hardware yet, so this
file exists to make each one individually reversible.

A third change was attempted and then dropped. Forcing application dexpreopt at
build time is impossible on this host, and it would not have helped anyway.
Section 3 records why, so the idea is not retried.

For what to check after building, and specifically for the conclusions that were
derived by reading source and still need confirmation on hardware, see
`POST_BUILD_VERIFICATION.md`.

Hardware context that the values are derived from:

- i.MX6SL, **single** Cortex-A9, three OPPs: 396 / 792 / 996 MHz
- `clock-latency = 61036` ns (`imx6sl.dtsi`)
- 1 GB DDR minus a 6 MB carveout (`memory` node `0x80000000 + 0x3fa00000`)
- 32-bit only (`ro.product.cpu.abilist64` is empty)

```bash
ADB="/home/juwon/ridi/host-tools/android-platform-tools/platform-tools/adb -s PP1A1ID154423"
OUT=/media/juwon/build/android-out/e70q10_reference_agl_stockpath/target/product/e70q10
```

---

## 1. CPU governor: ondemand to interactive

**Files:** `vendor/nxp-opensource/kernel_imx/arch/arm/configs/e70q10_defconfig`
(kernel default), `device/ridi/e70q10/init.E70Q10.rc` `on boot` (tunables)

This is a regression fix, not a new idea. The 4.4.2 firmware RIDI shipped on this
same hardware built with `CONFIG_CPU_FREQ_DEFAULT_GOV_INTERACTIVE=y` (visible in
the stock `/proc/config.gz`, extracted to
`ridi-paper-pro-stock-4.4.2-20260721/metadata/kernel-config.txt`). This port had
regressed to ondemand, which on this SoC resolves to a 61 ms sampling period
(`LATENCY_MULTIPLIER` 1000 x 61 us) and `up_threshold` 95 with
`sampling_down_factor` 1. A UI burst loading the single core to 80-90% for a few
tens of ms never raised the clock.

The default is set in the kernel **and** written from init:

- `CONFIG_CPU_FREQ_DEFAULT_GOV_INTERACTIVE=y` replaces
  `CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y`, so interactive governs from the moment
  cpufreq registers the policy instead of only after init runs
- `CONFIG_CPU_FREQ_GOV_ONDEMAND=y` is now listed explicitly. It used to be pulled
  in by the default-governor choice; without the explicit entry it would not be
  built at all and the runtime rollback below would fail
- `CONFIG_CPU_FREQ_STAT=y` was added for measurement. The stock 4.4.2 kernel had
  it, this port did not
- The init write is kept as well. It is redundant once the kernel default lands
  (`store_scaling_governor` returns early when the governor is unchanged) but it
  keeps the intent visible next to the tunables, which is what actually needs
  setting

Tunables written from `on boot`:

| Path (under `/sys/devices/system/cpu/`) | Value | Default it replaces |
|---|---|---|
| `cpu0/cpufreq/scaling_governor` | `interactive` | `ondemand` |
| `cpufreq/interactive/hispeed_freq` | `996000` | same (996000) |
| `cpufreq/interactive/go_hispeed_load` | `85` | 99 |
| `cpufreq/interactive/target_loads` | `80` | 90 |
| `cpufreq/interactive/timer_rate` | `20000` | same (20 ms) |
| `cpufreq/interactive/above_hispeed_delay` | `20000` | same (20 ms) |
| `cpufreq/interactive/min_sample_time` | `80000` | same (80 ms) |
| `cpufreq/interactive/io_is_busy` | `1` | 0 |

Times are microseconds, `hispeed_freq` is kHz. Tunables sit under the **global**
`/sys/devices/system/cpu/cpufreq/interactive/` because `imx6q-cpufreq` does not
set `CPUFREQ_HAVE_GOVERNOR_PER_POLICY`. That path is an inference from source, not
something observed on hardware; see `POST_BUILD_VERIFICATION.md` C1.

### Roll back at runtime (no build)

```bash
$ADB root
$ADB shell 'echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor'
$ADB shell 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor'
```

`ondemand`, `conservative`, `powersave`, `userspace` and `performance` are all
compiled in. Check what the running kernel offers with:

```bash
$ADB shell 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors'
```

The change comes back on the next boot; runtime rollback is for A/B comparison.

### Roll back permanently

Two places, because the governor is now set in both:

1. `e70q10_defconfig`: change `CONFIG_CPU_FREQ_DEFAULT_GOV_INTERACTIVE=y` back to
   `CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y`, and drop the now-redundant explicit
   `CONFIG_CPU_FREQ_GOV_ONDEMAND=y`. Requires `kernelimage`.
2. `init.E70Q10.rc`: delete the block starting at the
   `write ... scaling_governor interactive` line. This file is installed as
   `root/init.E70Q10.rc`, i.e. into the ramdisk, **not** into `system.img`.
   Requires `ramdisk`.

Reverting only (2) leaves interactive active with stock tunables, which is a
useful middle step if the tunable values turn out to be the problem rather than
the governor.

### Verify it took effect

```bash
$ADB shell 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor'        # interactive
$ADB shell 'cat /sys/devices/system/cpu/cpufreq/interactive/go_hispeed_load'  # 85
$ADB shell 'cat /sys/devices/system/cpu/cpufreq/interactive/io_is_busy'       # 1
```

With `CONFIG_CPU_FREQ_STAT=y` the residency table is the best way to judge the
change:

```bash
$ADB shell 'cat /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state'
```

Three rows are expected, for 396000 / 792000 / 996000. Compare the deltas before
and after the same task. If the directory does not exist, the flashed boot image
predates the defconfig change; poll the current frequency instead:

```bash
$ADB shell 'for i in $(seq 40); do cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq; sleep 0.25; done'
```

### If it misbehaves

Symptoms to watch for: higher idle drain, or the panel feeling no different. A
failed `write` in init is non-fatal, so a wrong path silently leaves the stock
tunables in place with no other symptom.

---

## 2. zram swap

**Files:** `device/ridi/e70q10/fstab.E70Q10`, `device/ridi/e70q10/init.E70Q10.rc`
(`on post-fs`), `vendor/nxp-opensource/kernel_imx/arch/arm/configs/e70q10_defconfig`

An earlier audit recorded that this kernel lacked `CONFIG_SWAP`. That was wrong.
`CONFIG_SWAP` is `default y` in `init/Kconfig` and defconfig files omit symbols
sitting at their default. Resolving the defconfig confirms it:

```bash
cd vendor/nxp-opensource/kernel_imx
make O=/tmp/kcfg ARCH=arm e70q10_defconfig
grep -E '^CONFIG_SWAP|^CONFIG_ZRAM|^CONFIG_ZSMALLOC' /tmp/kcfg/.config
```

So **zram needs no kernel rebuild**. What was added:

- `fstab.E70Q10`: `/dev/block/zram0 none swap defaults zramsize=25%,max_comp_streams=1`
- `init.E70Q10.rc` `on post-fs`: `write /sys/block/zram0/comp_algorithm lz4`
  followed by `swapon_all /fstab.E70Q10`
- `e70q10_defconfig`: `CONFIG_CRYPTO_LZ4=y` (pulls in `LZ4_COMPRESS` and
  `LZ4_DECOMPRESS` automatically)

`swapon_all` sits in `on post-fs` because `fs_mgr` shells out to
`/system/bin/mkswap`, which only exists after `on fs` has run `mount_all`.
`comp_algorithm` must be written before `disksize`, and `fs_mgr` writes
`disksize` inside `swapon_all`, hence the ordering.

**The `lz4` write fails on the currently flashed kernel.** `CONFIG_CRYPTO_LZ4`
only lands with the next kernel build, so until then init logs the failed write
and zram stays on lzo, which `CONFIG_ZRAM` selects anyway. This is expected, not
a defect.

### Roll back at runtime (no build)

```bash
$ADB root
$ADB shell 'swapoff /dev/block/zram0'
$ADB shell 'echo 1 > /sys/block/zram0/reset'
$ADB shell 'cat /proc/swaps'      # should now be empty
```

### Roll back permanently

Remove the `zram0` line from `fstab.E70Q10` and the two lines
(`write ... comp_algorithm`, `swapon_all ...`) from `on post-fs`, then rebuild
`ramdisk`. Both files live in the ramdisk.

`CONFIG_CRYPTO_LZ4=y` in the defconfig is inert on its own and can be left in
place; removing it only matters if kernel size is being trimmed.

### Verify it took effect

```bash
$ADB shell 'cat /proc/swaps'                       # /dev/block/zram0 listed
$ADB shell 'cat /sys/block/zram0/disksize'         # ~25% of visible RAM, in bytes
$ADB shell 'cat /sys/block/zram0/comp_algorithm'   # active one is in [brackets]
$ADB shell 'cat /sys/block/zram0/mm_stat'          # orig / compressed / used
```

An empty `/proc/swaps` means the entry was **skipped**, not that zram is idle:
`fs_mgr_swapon_all` does `ret = -1; continue` if it cannot open
`/sys/block/zram0/max_comp_streams`.

### Tuning it instead of removing it

`zramsize=25%` is deliberately conservative because every swap-in costs
decompression on the only core. If lmkd is still killing recent apps, raise it
(`zramsize=40%`); if interaction stutters under memory pressure, lower it. The
value is resolved by `fs_mgr` against `_SC_PHYS_PAGES`, so it tracks whatever the
kernel actually reports as usable.

`max_comp_streams` is a no-op on this kernel (`max_comp_streams_store` just
returns `len`; zram has used per-CPU streams since 4.7). It is spelled out only
so the intent survives a kernel bump.

---

## 2b. NR_CPUS sized for the real core count

**File:** `vendor/nxp-opensource/kernel_imx/arch/arm/configs/e70q10_defconfig`

`imx6sl.dtsi` declares only `cpu@0`, but `arch/arm/Kconfig` defaults `NR_CPUS` to
4, so every per-cpu allocation was sized for three cores that do not exist.
Added `CONFIG_NR_CPUS=2`, which is the floor while SMP is on
(`range 2 32 depends on SMP`).

This saves memory, not time. Do not expect it to be perceptible.

### Roll back

Delete the `CONFIG_NR_CPUS=2` line and rebuild the kernel. The Kconfig default
takes over again.

### Two things that could not be changed

`CONFIG_HOTPLUG_CPU` is dead code on a single core but cannot be disabled:
`kernel/power/Kconfig` declares `PM_SLEEP_SMP` as `def_bool y` and it
`select HOTPLUG_CPU`. Suspend is required on this device, so the select always
wins.

`CONFIG_SMP` was left on deliberately. `CONFIG_SMP_ON_UP=y` makes the kernel patch
out the SMP-only instruction sequences at boot on uniprocessor hardware, so the
usual penalty is already handled and the remaining gain is only tree preemptible
RCU becoming tiny RCU. Worth noting for the future: the stock 4.4.2 kernel did
build with `# CONFIG_SMP is not set`, so uniprocessor is proven on this hardware,
just not on this 4.9 kernel.

---

## 3. Application dexpreopt: attempted, reverted

**No files carry this change.** It was applied and then backed out. The reasoning
now lives as comments in `BoardConfig.mk` and `e70q10_reader_base.mk`; this
section exists so the idea is not retried from scratch.

### What was tried

`WITH_DEXPREOPT_BOOT_IMG_ONLY := false` in `BoardConfig.mk` to clear the eng-build
default from `build/make/core/dex_preopt.mk`, plus
`PRODUCT_DEXPREOPT_SPEED_APPS += SystemUI Settings Launcher2 LatinIME` to force
full AOT on the components on the critical path.

### Why it cannot be built here

Application dexpreopt makes the host `dex2oat` load the target boot image at the
fixed base address it was built for, and dexpreopt passes `-Xnorelocate` so it may
not be moved. A current kernel ignores the address hint:

```
Failed to mmap at expected address, mapped at 0x7ffff4c00000 instead of 0x7036b000
Dex file fallback disabled, cannot continue without image
```

Every application then fails to compile and no system image is produced.
`setarch -R` does not help; it would need `sudo sysctl -w vm.mmap_rnd_bits=28` on
the build host, which is a host-wide change to ASLR entropy.

Building the boot image alone does work, which is why
`/system/framework/arm/boot*.oat` exists while no application odex does.

### Why it would not have helped anyway

The reasoning behind the change was wrong. An image with zero `.odex` files does
**not** mean applications are interpreted on every boot. The device runs
`dex2oat` itself once, on the first boot after a new image is written, and caches
the result in `/data/dalvik-cache`. Later boots reuse that cache.

So the cost of not preopting is a slow first boot, not a permanently slow device,
and `system.img` stays smaller.

### If full AOT for core apps is ever wanted

Use the runtime's own knobs rather than build-time dexpreopt: the `pm.dexopt.*`
properties select the compiler filter per reason (`first-boot`, `boot`, `install`,
`bg-dexopt`). That moves the cost into the first boot on the device, where it can
at least be measured, and does not depend on the host at all.

---

## Rolling everything back at once

Only two files carry the tuning: the ramdisk pair `init.E70Q10.rc` and
`fstab.E70Q10`, and the kernel `e70q10_defconfig`. Nothing here touches
`system.img`.

```bash
cd /home/juwon/ridi/android-sources/nxp-o8.0.0_1.0.0-ga
git -C device/ridi/e70q10 checkout -- fstab.E70Q10 init.E70Q10.rc
git -C vendor/nxp-opensource/kernel_imx checkout -- arch/arm/configs/e70q10_defconfig
```

Rebuild `ramdisk` for the first, `kernelimage` for the second.

Two cautions. `init.E70Q10.rc` carries **other** uncommitted porting work, and so
does `e70q10_defconfig` (the `CONFIG_BACKLIGHT_LM3630A` entry belongs to the
frontlight work). Check `git diff` before reverting a whole file, and prefer
removing the specific blocks described above.

`ro.config.low_ram=true` and the dalvik heap settings are a separate change in
`e70q10_eink_defaults.mk` and are not covered by the commands above. They do land
in `system.img`, and they are what makes the `BarTransitions` white-bar patch
necessary, so revert them together with that patch or not at all.

A known-good RAM boot image to fall back to:
`/home/juwon/ridi/porting/e70q10/e70q10-agl-stockpath-current-ramboot.img`

---

## What was checked, and what was not

Verified statically:

- The whole defconfig change set resolves as intended, by running
  `make O=<scratch> ARCH=arm e70q10_defconfig` and reading the produced
  `.config`: `CONFIG_SWAP=y`, `CONFIG_ZRAM=y`, `CONFIG_ZSMALLOC=y`,
  `CONFIG_CRYPTO_LZ4=y` (which pulls in `LZ4_COMPRESS`/`LZ4_DECOMPRESS`),
  `CONFIG_NR_CPUS=2`, `CONFIG_CPU_FREQ_STAT=y`,
  `CONFIG_CPU_FREQ_DEFAULT_GOV_INTERACTIVE=y`, and ondemand still built
- interactive tunable names and units read from `cpufreq_interactive.c`
- tunable location derived from `imx6q-cpufreq.c` not setting
  `CPUFREQ_HAVE_GOVERNOR_PER_POLICY`
- `swapon_all` exists as an init builtin taking exactly one argument, `write`
  takes exactly two, and the fstab format is five fields
- `/system/bin/mkswap` is present (toybox symlink)

Not verified:

- Nothing has been built or booted with these changes
- No measurement of responsiveness or battery drain
- Whether ondemand was resolving to `up_threshold` 95 or 80 on the real device
  (the 95 branch depends on `get_cpu_idle_time_us()` at runtime)

---

## Comparison against the stock 4.4.2 kernel

Source: `ridi-paper-pro-stock-4.4.2-20260721/metadata/kernel-config.txt`, the
stock `/proc/config.gz` for Linux 3.0.35.

| Symbol | 4.4.2 stock | This port | Note |
|---|---|---|---|
| `CPU_FREQ_DEFAULT_GOV_INTERACTIVE` | y | y (was ondemand) | the regression fixed above |
| `CPU_FREQ_STAT` | y | y (was n) | added for diagnostics |
| `SMP` | **n** | y | uniprocessor is proven on this hardware |
| `NR_CPUS` | n/a | 2 (was 4) | |
| `CPU_IDLE` | **n** | y | stock had no cpuidle framework at all |
| `CPU_IDLE_GOV_MENU` | n/a | y, forced | see below |
| `SWAP` | y | y | |
| `ZRAM` | n | y | stock shipped no zram |
| `CPUSETS` | y | n | no loss on one core |
| `HZ` | 100 | 100 | |
| `PREEMPT` | y | y | |
| `DEFAULT_IOSCHED` | cfq | cfq | |

Two conclusions worth keeping:

**The cpuidle governor cannot be swapped.** `drivers/cpuidle/Kconfig` has
`CONFIG_CPU_IDLE` do `select CPU_IDLE_GOV_MENU if (NO_HZ || NO_HZ_IDLE)` and
`select CPU_IDLE_GOV_LADDER if (!NO_HZ && !NO_HZ_IDLE)`. With
`CONFIG_NO_HZ_IDLE=y` the menu governor is forced; reaching ladder would mean
giving up tickless idle, which costs more power than the menu governor's
per-idle computation. Stock 4.4.2 sidestepped this by not enabling `CPU_IDLE`
at all, which is not worth copying because it also gives up the i.MX6SL deep
idle states.

**`CONFIG_CPU_FREQ_GOV_PERFORMANCE=y` is now available** as a side effect of the
default-governor choice selecting it. An earlier audit recorded the performance
governor as unavailable without a defconfig change; that is no longer true, so it
can be used for a quick "is this a CPU bottleneck at all" test:

```bash
$ADB shell 'echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor'
```

Leave it only for the duration of a measurement.

---

## Related work that is deliberately not included

- **Touch boost.** interactive exposes `boost` and `boostpulse`, but the product
  uses `power.default`, the AOSP stub HAL, which does not forward
  `POWER_HINT_INTERACTION`. Wiring that up needs a small power HAL and is a
  separate change.
- **`scaling_min_freq`.** Raising the floor to 792 MHz is a simpler alternative
  to the governor switch. It was left out so the two are not entangled; it
  raises idle voltage from 975 to 1175 mV.
- **lmkd tuning.** The `ro.lmk.*` properties do not exist in this release;
  `system/core/lmkd/lmkd.c` contains no such strings. Oom levels come from
  `ProcessList` instead, so there is no property to tune.
- **I/O scheduler.** Both stock 4.4.2 and this port default to `cfq`. `deadline`
  or `noop` are often better on a single core with SD storage, and this can be
  tried at runtime without a build:
  `echo deadline > /sys/block/mmcblk1/queue/scheduler`.
