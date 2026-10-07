# E70Q10 suspend and battery recorder

This is an **optional** device-only diagnostic. It is installed in the Android
image but is disabled until `sys.ridi.power_diag=1`. The enable property is not persistent across reboots and the service is
oneshot, so a crash will not cause an init restart loop. It reads existing
kernel power counters; it changes no suspend policy and holds no wake lock.
The 60-second `CLOCK_MONOTONIC` timer does not wake the device from suspend.

## Use

1. Build/apply the updated Android system and boot/ramdisk image as usual.
2. With ADB connected and USB debugging enabled, run:
   `adb shell setprop sys.ridi.power_diag 1`
3. Disconnect USB, leave the device awake for at least 60 seconds so a
   battery-only sample is recorded, then put it to sleep for the test period.
4. Wake the device while USB is still disconnected, and leave it awake for
   at least 60 seconds for a final battery-only sample. Then reconnect USB
   and request an immediate confirmation sample:
   `adb shell 'kill -USR1 $(cat /data/ridi/logs/power-diag/recorder.pid)'`
5. Read the files with `adb pull /data/ridi/logs/power-diag/ .` (root ADB is
   required for the mode-0700 directory). If ADB is unavailable, the files stay
   on the device until access is restored.
6. Stop the recorder: `adb shell setprop sys.ridi.power_diag 0`
7. Run the host analyzer on `samples.log` (add `samples.previous.log` first if
   it exists):

   ```sh
   python3 device/ridi/e70q10/power_diag/analyze.py samples.previous.log samples.log
   ```

The log rotates at 16 MiB and keeps one previous file. Each sample records both
`CLOCK_BOOTTIME` and `CLOCK_MONOTONIC`; their difference over a test window is
actual suspend residency. It also records wakeup-source counters, suspend
success/failure counts, last resume IRQ, CPU ticks, and every power-supply
uevent (including capacity, voltage and current if the driver exposes them).
It also takes non-clearing Android BatteryStats snapshots at start and at the
requested/end sample. These are saved as `batterystats-start.txt` and
`batterystats-end.txt`; the analyzer uses them to rank UID wake locks and CPU
time. It never resets Android battery statistics.

The analyzer uses the first and last discharging samples when available.
If Android BatteryStats resets around a charging transition, app-level deltas
are skipped rather than reported as zero.

`prevent_suspend_time` identifies wake locks that kept the kernel awake.
`wakeup_count` identifies sources that woke it. These are **time and event
counts**, not a measurement of each app's power. Some sources (such as
`PowerManagerService`) aggregate several apps. Use Android BatteryStats for
further app-level attribution when a kernel source is generic. Battery percent
is coarse; voltage varies with load. To establish physical power draw during
true suspend, an external current meter is still required if the battery
power-supply driver has no reliable current sensor.

## Removal

Set the property to `0` to stop the process immediately. For a later firmware
cleanup, remove the `e70q10_power_diag` package line in
`e70q10_reference.mk`, the diagnostic service/triggers and data-directory lines
in `init.E70Q10.rc`, the device policy path in `BoardConfig.mk`, the
`device/ridi/e70q10/sepolicy` directory, and this `power_diag` directory.
Existing logs can be removed separately.
