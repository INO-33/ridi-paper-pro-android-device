# E70Q10 partial-update diagnostics

This checkpoint adds observation and host replay only. It does not change the
waveform, update policy, dirty thresholds, PxP rotation, or normal update
geometry.

## Connected data flow

1. `hwcomposer_v10/hwcomposer.cpp::collect_target_damage()` unions
   SurfaceFlinger's exclusive-edge `surfaceDamage` rectangles in logical
   1404x1872 coordinates.
2. `set_epdc_damage()` forwards that union unchanged to
   `framebuffer.cpp::fb_setUpdateRect()`.
3. `epdc_refresh()` clips the logical rectangle, scans framebuffer versus
   `epdc_shadow`, refines dirty pixels, expands each final rectangle outward to
   8-pixel boundaries, and calls `MXCFB_SEND_UPDATE`.
4. `mxc_epdc_fb_send_single_update()` captures the selected framebuffer page
   offset and queues the descriptor.
5. The kernel workqueue later runs `epdc_process_update()`. It computes the
   RGB565 source offset/pitch, the PxP 8x8 input, CCW rotation, P5N output
   offset/pitch, and the physical EPDC rectangle.
6. `adjust_coordinates(FB_ROTATE_CCW)` maps a logical half-open rectangle
   `(x,y,w,h)` to physical `(y, 1404-(x+w), h, w)`.
7. EPDC receives the processed-buffer address plus `epdc_offs`, the rotated
   physical rectangle, waveform, update mode, and marker.

## Geometry findings

There are three distinct pitches in the tree and they must not be conflated:

- visible logical framebuffer: 1404x1872;
- logical RGB565 framebuffer pitch: 1408 pixels / 2816 bytes;
- visible physical panel: 1872x1404.

The 1888-pixel output pitch exists in the standalone HWC/PxP benchmark and the
experimental local-compositor design. The active stock-path kernel PxP path
does not use 1888 as the framebuffer pitch: its full-screen processed P5N
output has `epdc_stride=1872`, while partial output pitch is the 8-aligned
logical update height. Runtime trace now prints all of these values so this can
be confirmed on the next device build.

For the logical right-edge pixel `(1403,0,1,1)` the current code computes:

```text
original       = 1403,0 1x1
gralloc aligned= 1400,0 4x8
physical rect  = 0,0 8x4
RGB565 offset  = 2800 bytes, pitch 2816 bytes
PxP input      = 0,0 8x8
PxP ROT_270    = padding rows 0..3, visible rows 4..7
EPDC offset    = 4 * 8 = 32 bytes (P5N partial buffer)
```

The visible rows at the adjusted address correspond to logical x=1403..1400;
the four padded rows are skipped. The current transform therefore preserves
this edge pixel.

## Host results

Run:

```bash
python3 device/ridi/e70q10/tools/epdc_panel_replay.py fuzz \
  --iterations 50000 --seed 3696
python3 device/ridi/e70q10/tools/epdc_panel_replay.py demo \
  --output-dir .orchestrator/logs/epdc-host-diag/replay
```

The checked run covered 53,600 boundary and random rectangles:

- current outward alignment/rotation/PxP-offset containment failures: **0**;
- deliberately broken exclusive-end floor failures: **52,643**;
- current-alignment black-to-white edge replay stale pixels: **0**;
- floor-end negative-control stale pixels: **16**;
- deferred framebuffer-page reuse replay mismatches: **800**.

Thus the current ordinary no-collision rectangle math does not reproduce the
reported point/line loss. The simulator does prove that a normal final
framebuffer can coexist with stale panel pixels when either the submitted
rectangle is reduced or the bytes consumed later differ from the bytes used to
advance the userspace shadow.

## Confirmed source-lifetime hazard

`MXCFB_SEND_UPDATE` under the queue scheme returns after adding a descriptor to
the kernel workqueue. The descriptor captures `fb_offset`, but PxP reads that
page later. At the same time `hwc_set()` returns `releaseFenceFd=-1` and
`retireFenceFd=-1`, so SurfaceFlinger receives no fence protecting that page
until PxP has consumed it. `epdc_refresh()` advances `epdc_shadow` immediately
after successful queueing.

This is a code-level lifetime contract violation: page identity is retained,
but page contents are not retained. The host replay proves panel/shadow
divergence if that page is reused before PxP. Whether it is the observed device
artifact still requires runtime queue-delay/page-reuse correlation. The new
trace reports `fb_offset`, queue-to-PxP microseconds, source offset/pitch, and
the final processed-buffer offset/pitch for that purpose.

No production synchronization change is made in this checkpoint. A proven fix
should provide a source-consumed fence or snapshot the affected source region
before releasing the HWC target. Waiting for the complete E-Ink waveform is not
required and would be the wrong performance tradeoff.

## Shadow consistency

The current userspace shadow is updated only after every `SEND_UPDATE` ioctl in
that post returns success, and only over the union of found/submitted regions.
An immediate ioctl failure leaves both pending damage and the old shadow. That
is correct for synchronous failure.

However, ioctl success means “queued”, not “PxP consumed and EPDC submitted”.
A later kernel PxP failure, dropped collision path, or source-page reuse is not
reported back to gralloc. In those cases gralloc can believe the panel contains
bytes it never received. Trace correlation is required before changing this
contract.

## Runtime trace

The existing trace controls remain default-off:

```text
setprop debug.ridi.epd.trace 1
echo 1 > /sys/class/graphics/fb0/e70q10_trace
```

The trace now covers original/clipped/aligned logical damage, refined and final
regions, logical geometry and RGB565 pitch, source offset, shadow sync range,
kernel queue/merge/collision, queue-to-PxP latency, rotated physical rectangle,
PxP alignment before/after, processed-buffer offset/pitch, waveform, FULL versus
PARTIAL, marker, and final hardware submit rectangle.

After a device is available, run:

```bash
device/ridi/e70q10/tools/capture_epdc_trace.sh
```

It always targets serial `PP1A1GK166561`, does not clear existing buffers, and
writes filtered output below `.orchestrator/logs/`.

## UI-line track

Generate matched integer, anti-aliased, subpixel, black/white, and gray lines:

```bash
python3 device/ridi/e70q10/tools/epdc_panel_replay.py line-pattern \
  --output-dir .orchestrator/logs/epdc-host-diag/line-pattern
```

The output includes the source plus RGB565 round-trip, 8-bit grayscale, 4-bit
grayscale, and binary-threshold views. This intentionally remains independent
from the partial-update investigation.

## Minimal device A/B sequence

1. Enable both traces and show a static all-white screen.
2. Draw then erase a 1x1 logical pixel at x=1403; verify logical aligned
   `1400..1404` and physical top `0..4` in the trace.
3. Repeat at x=0, y=0, y=1871 and all four corners.
4. Draw/erase a one-pixel vertical line at x=1403 and a one-pixel horizontal
   line at y=0.
5. Repeat the vertical-line test with one-second pauses, then with rapid
   updates, comparing `queue_us` and `fb_offset` reuse.
6. Reproduce Total Launcher once with animation disabled and once with its
   normal clock/widget updates.
7. If a stale pixel appears, immediately trigger explicit fullscreen GC16 and
   confirm it disappears without changing the framebuffer dump.
8. Run the UI-line pattern with AA/integer/gray variants using the same
   waveform.
9. Compare PxP boundary logs and collision/resubmit logs for the failed and
   passing run.
10. Disable traces and repeat one static-screen CPU/postFramebuffer baseline to
    confirm instrumentation is dormant.

## Production fix gate

Do not change alignment, waveform, or force fullscreen updates based on the
host results. The only current fix candidate is source-page lifetime
synchronization, and it should be implemented only after device trace shows a
non-trivial queue delay plus reuse of the same `fb_offset` before PxP consumes
it. If runtime bytes are stable, continue with collision/resubmit and PxP
boundary provenance rather than changing gralloc rectangle math.
