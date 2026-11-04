# NXP Oreo graphics-to-EPDC path

## Source-selected interfaces

The checked-out NXP O8.0.0_1.0.0 tree uses:

- allocator 2.0, mapper 2.0 and composer 2.1
- `TARGET_GRALLOC_VERSION := v3`
- `TARGET_USES_HWC2 := true`
- `TARGET_HWCOMPOSER_VERSION := v2.0`

Generic Android 8 documentation may describe mapper 1.0, but this vendor tree
ships and selects mapper 2.0. The checked-out source is authoritative.

## Default call path

```text
SurfaceFlinger (HWC2)
  -> android.hardware.graphics.composer@2.1-impl
  -> hwcomposer.imx6 (NXP HWC v2.0)
  -> libfsldisplay
  -> FbDisplay::updateScreen()
  -> MXCFB_UPDATE_SCREEN or FBIOPAN_DISPLAY
  -> /dev/graphics/fb0
```

The E70Q10 driver instead requires `MXCFB_SEND_UPDATE` with
`mxcfb_update_data`. The default v3/v2.0 path currently does not submit that
ioctl, so framebuffer pan alone does not prove that the panel will refresh.

## Existing NXP implementation

`vendor/nxp-opensource/imx/display/gralloc_v1/framebuffer.cpp` already detects
`epdc` in `/sys/class/graphics/fb0/name`, submits `MXCFB_SEND_UPDATE`, assigns
update markers, optionally waits for completion and retries when update slots
are exhausted.

Composer 2.1 cannot wrap this implementation because `HWC2On1Adapter` rejects
HWC versions below 1.1. The selected product therefore compiles
SurfaceFlinger's direct HWC1 path and does not package composer 2.1.

## Chosen initial direction

The default HWC2/libfsldisplay module cannot be rebuilt from the supplied tree:
`g2dExt.h` and the matching `libg2d` are not present. The reproducible initial
path is therefore:

```text
SurfaceFlinger_hwc1
  -> NXP hwcomposer v1.0
  -> EGL swap
  -> NXP gralloc v1 fb_post()
  -> existing update_to_display()
  -> MXCFB_SEND_UPDATE
```

Set `TARGET_USES_HWC2 := false`, `TARGET_HWCOMPOSER_VERSION := v1.0` and
`TARGET_GRALLOC_VERSION := v1`. Do not declare or package composer 2.1 for this
profile. Allocator and mapper 2.0 remain.

First implementation uses the existing full-screen automatic-waveform update
and synchronous completion wait. This is deliberately slow but gives a clear
correctness baseline.

Second implementation:

- completion worker instead of SurfaceFlinger blocking
- pending-frame coalescing and newest-frame retention
- damage-region updates
- fast partial versus page-quality waveform policy
- periodic full refresh

Instrumentation must cover EGL swap, gralloc `fb_post()`, buffer format, stride,
dimensions, submit result, marker, completion latency, coalesced frames and
SurfaceFlinger restarts.

The initial instrumentation patch logs the first eight updates, every 120th
update, every retry and every error under the `E70Q10_EPDC` tag text. It records
the update marker, rectangle, waveform, retry count, ioctl result and
submit-to-completion latency without logging every normal frame.
