# Software-only bitmap requests

2026-11-16. Independent platform-bitmap compatibility work; this does not advance
WebView or sleep-overlay checkpoints.

## Product capability

`ro.ridi.software_bitmaps=true` opts a product into CPU-backed replacements for
hardware-bitmap allocation requests. The read-only flag is cached once per process
by `android::Bitmap::shouldUseSoftwareBitmaps()` in libhwui. It does not probe EGL,
start RenderThread or depend on a particular View's hardware-acceleration state.

The reference/default AGL and minimal products opt in through the shared E Ink
defaults. PAPER x86/ARMv7 emulator products opt in explicitly. The Mesa experiment
and other products retain the existing behavior by leaving the flag unset.
No GLES version, rendering backend, compositor or host-window setting changes.

## Request paths

- BitmapFactory resolves a HARDWARE preference to the existing software allocator
  before computing `outConfig`, bounds-only metadata or selecting the allocator.
  Ordinary decoding does not create a temporary hardware-upload bitmap or perform
  an additional fallback copy. Existing scaling, density, nine-patch and inBitmap
  paths are retained. Invalid HARDWARE + mutable options still fail validation.
- BitmapRegionDecoder resolves the same preference before output metadata. Region
  clipping and reuse semantics remain; a newly allocated hardware replacement is
  marked immutable. Caller-provided inBitmap reuse retains AOSP precedence.
- Bitmap.copy(HARDWARE, false) goes through the common allocator below and exposes
  its actual software format. JNI creation flags also respect unpremultiplied
  input, preventing alpha metadata from contradicting the returned storage.
- The common Bitmap::allocateHardwareBitmap fallback uses readable CPU pixels,
  allocates checked heap storage and never queues RenderProxy/GL work. N32/F16
  pixel bytes, alpha and color space are retained, with row-wise visible-byte
  copies that do not import source padding. Other readable formats use Skia's
  CPU conversion to N32 when supported. Allocation/conversion/invalid-size failures
  return null; no empty placeholder or EGL failure suppression is used.

New replacements are immutable CPU storage and report their actual N32/F16/etc.
configuration; they do not claim Config.HARDWARE. Both alpha representations and
color-space metadata remain attached to the pixels. Source pixels are unchanged.

## Limits

A genuinely GPU-backed imported source needs readback and is not made CPU-readable
by this policy. Bitmap.copy returns null on the software-only product before
getSkBitmap can start GL readback; copy is already a nullable API. Other products
retain readback behavior. GraphicBuffer import, protected buffers, PixelCopy,
GLSurfaceView, shader APIs and WebGL are not universally emulated here. This is
not a software GLES implementation and does not claim to cover every GPU entry.

## Verification and integration

Evidence: `/home/juwon/ridi/.orchestrator/logs/software_bitmaps_20261116/`.

- Actual modified policy/common-allocation/JNI-copy function bodies run with
  host bitmap/JNI fixtures: 13,463 assertions across SW-only and other-product
  profiles. Tests cover GL dispatch avoidance, property caching, padded rows,
  N32/F16, alpha/color-space identity, immutable flags, safe failures and lifetime.
- AddressSanitizer and UndefinedBehaviorSanitizer enabled. LeakSanitizer cannot
  operate in the tool's traced host environment, so its automatic scan is disabled;
  explicit fixture storage-lifetime assertions still run.
- Four complete changed native C++ translation units pass the BSP ARM compiler's
  syntax checks using existing Soong compile rules. No native library link or
  firmware build performed.
- Actual GNU Make evaluation verifies default/AGL versus Mesa property gating;
  both emulator declarations and decoder metadata/reuse/error-path placement are
  checked. Java validation and bitmap-configuration mapping remain unchanged.
- Actual Skia codec/color-converter execution, native library linking, APK behavior,
  latency and peak memory still need confirmation after the user builds/applies.
  Host fixtures do not substitute for those integration checks.

Rebuild the complete `systemimage` for the current non-split property layout:
libhwui, libandroid_runtime and the new product property must be applied together.
No boot/kernel/vendor source was changed. No clean, image build, installation,
ADB state change, reboot, WebView test or emulator state change was performed.
