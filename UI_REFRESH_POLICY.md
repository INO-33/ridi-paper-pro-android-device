# General UI refresh policy

Updated 2026-11-16. This is RIDI8's product policy, informed by current BOOX
documentation, rather than a claim that all manufacturers use the same rules.

## Ordinary interaction

Launcher, Settings, scrolling, keyboard, menus, popup dismissal, new windows and
activity changes within the same foreground package use partial updates by
default. Full-window damage does not mean a flashing whole-panel cleanup.
There is no tap/frame-count or dirty-area-based automatic panel cleanup.

On products with `ro.ridi.eink_mode=true`, transient pressed feedback is handled
centrally rather than deleting each app's selector XML. Drawable selectors
(including animated selectors), color/tint/text selectors and state-list
animators use `StateSet.stateSetMatchesForDrawable`, which visually treats
`state_pressed` as absent. The public state matcher, drawable state arrays and
View input/pressed state are unchanged. Checked, selected, enabled, focus and
custom states still work. Thus standard widgets in third-party apps also inherit
the policy. Non-RIDI products use the original matching and animation behavior.

Plain `AbsListView` touch selectors are also omitted; keyboard-focus selectors
remain. State-list fades, animated selector transitions, state-list property
animations and the platform Switch's 250 ms thumb animation snap to the final
state on RIDI. Dragging and real checked-state updates remain functional.
Ordinary RippleDrawable was already disabled on RIDI; navigation ripple was
already gated by `ro.ridi.disable_nav_animations`.

REAGL is a waveform, not an alternative to the partial/full update-mode field.
Settings already requests REAGL/PARTIAL/NOWAIT. Two different pressed/unpressed
images still require two pixel transitions even with that waveform. This policy
removes the transient images at their common source; it does not suppress dirty
frames or force all apps to REAGL. Custom Canvas effects, app-specific animation
logic and WebView/CSS content do not necessarily use these selectors and are not
claimed fixed by the shared policy. Launcher shelf touch-down itself does not
invalidate; real navigation, redraws and frontlight slider changes remain.

The existing 35% damage threshold in gralloc selects ROI validation versus a
full framebuffer comparison. It is not a cleanup trigger and remains intact.

## App boundaries

On RIDI E Ink products, `RidiAppRefreshController` observes WindowAnimator after
the show transaction has closed. A different foreground package/UID must have
a drawn, shown main window on the default display and a completed app
transition before the controller posts one refresh request on the WM handler.
Returning to the launcher is an app boundary. A same-package activity change,
rotation/recreation, keyboard, floating activity, framework chooser or SystemUI
panel is not. Requests are rechecked before dispatch and rapid switches cancel
the superseded request. A boot/wake baseline does not add another cleanup.

The controller reuses `sys.ridi.epd.full_refresh_seq` and SurfaceFlinger's
existing 1004 repaint command, so even a static third-party app need not
invalidate a View or implement the RIDI API. A manual/wake sequence change
between show observation and dispatch suppresses the duplicate request.
No polling, delayed redraw loop, new recorder, compositor backend or kernel
waveform change is introduced.

## Preserved paths

- Manual whole-panel cleanup, including the configured page-button chord.
- Explicit application waveform requests, including FULL and first-draw APIs.
- Existing boot, wake, shutdown/low-battery and sleep-overlay handling.
- Sleep EPDC SEND -> blank -> suspend synchronization.
- Existing scan/diff cache, ROI, geometry and rotation handling; ordinary frames
  gain no EPDC WAIT. The existing explicit-cleanup wait behavior is unchanged.

Consequently, an app that explicitly requests FULL can still cause a cleanup
inside that app. This policy removes framework-generated UI cleanup; it does
not strip the application's waveform API requests.

## Evidence and validation

Official general-system/app references (consulted 2026-11-16):

- https://booxsupport.zendesk.com/hc/en-us/articles/10701172864916-Display-Settings
- https://booxsupport.zendesk.com/hc/en-us/articles/8569262708372-Refresh-Modes
- https://booxsupport.zendesk.com/hc/en-us/articles/360027486972-Understanding-E-Ink-Technology-in-BOOX-Devices

Host tests execute the actual controller and extracted actual View policy
methods. Android 8 framework API compilation checks the controller and Settings
refresh helper. Results, originals and a non-Git diff are in
`/home/juwon/ridi/.orchestrator/logs/ui_refresh_policy_20261116/`.
No firmware build, clean, installation, physical refresh/latency measurement or
WebView checkpoint validation was performed for this change.

Common feedback follow-up: source inventory across ten framework/app/device roots
(including unshipped resource variants), 223 pressed selectors, public matcher
compatibility and extracted actual widget-state methods were checked on both
RIDI and non-RIDI profiles. Logs and a non-Git diff are in
`/home/juwon/ridi/.orchestrator/logs/common_pressed_feedback_20261116/`.
This replaces the earlier Settings-only row-background resource change.
