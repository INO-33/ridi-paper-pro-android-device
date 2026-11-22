# PAPER PRO magnetic cover sleep/wake

## Original stock behavior

Evidence: extracted `classes.dex` from the original PAPER PRO Android 4.4.2
`android.policy.jar`, not an assumption based on generic Android lid defaults.
Original binaries and resource dump are identified in the checkpoint packet at
`.orchestrator/logs/cover_sleep_20261117/`.

- `PhoneWindowManager.notifyLidSwitchChanged` checks
  `SystemProperties.getBoolean("persist.sys.enable_hallsensor", true)`.
- When disabled it ignores both directions. Otherwise, after its stock-specific
  headless / `getIsStarted` guard and duplicate-state check, opening calls `wakeUp`;
  closing calls `HallSensor_goToSleep`, which calls `goToSleep` if the screen is on.
- Stock `config_lidControlsSleep` is false. Merely copying this resource would
  miss the custom hall sleep behavior entirely.

## Android 8 integration

The current board DTS already exposes GPIO5_12, active low, as `EV_SW/SW_LID`
with 50 ms debounce and `wakeup-source`. InputManagerService maps SW_LID=1 to
closed (`lidOpen=false`) and SW_LID=0 to open. No kernel or DTS edit was needed.
Existing hardware wiring and real cover operation still require physical testing.

For `ro.ridi.eink_mode=true`, PhoneWindowManager reads the same stock persistent
property, default true. Enabled: close uses the existing `goToSleep` wrapper with
LID_SWITCH/NO_DOZE; open uses the existing normal `wakeUp` wrapper. This retains
Android power policy, theater-mode handling, the existing sleep-image path,
SEND-before-blank ordering and existing resume behavior. An enabled, closed cover
also suppresses the normal wake gesture listener. It does not disable the power
button or intercept application input.

Disabled: lid events still update physical state and gesture policy, but do not
sleep, wake, lock, send user activity, or request rotation from this callback.
Boot-time lid application respects the switch as well. Non-RIDI products retain
the original Android behavior and ignore the RIDI property.

Settings -> 화면 -> 커버로 슬립 및 깨우기 uses the existing moon icon and switch
row. Settings writes the property directly as the system UID, using the existing
`system_prop` permission; no SELinux broadening is needed. The choice survives
reboot and applies on subsequent cover transitions without a reboot. Changing
the switch does not synthesize an event for an already stationary cover.

OFF controls screen actions, not GPIO wake capability: a hall interrupt may still
briefly wake the CPU to deliver an ignored event. No polling, background service,
new wake lock or persistent logger is introduced.

## Integration and remaining verification

Build target: `systemimage` (framework policy + Settings together). This change
contains no boot/vendor edit. No firmware build, installation, reboot or physical
cover test was performed by this task.

Host checks execute the modified policy methods and Settings click lambda:
default ON, close/open, duplicate suppression, OFF in both directions, state
tracking, re-enable, boot-closed, wake-gesture gating, and non-RIDI sleep/lock
configurations. Source checks cover the input mapping and property permission.
These fixtures do not validate actual GPIO edges, suspend current, panel timings,
or real wake from suspend. Apply the image, verify the selected sleep image on
close and normal wake on open, then disable and repeat both directions; confirm
OFF survives reboot. Existing graphics regression baselines remain applicable.
