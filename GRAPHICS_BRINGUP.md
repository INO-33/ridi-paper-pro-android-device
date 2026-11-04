# E70Q10 graphics bring-up

The i.MX6SoloLite has no 3D GPU. The default is a hybrid path:

- CPU Skia renders normal Android Views;
- the HWC uses PxP for rotation and RGB565 conversion;
- Mesa softpipe supplies the GLES2 ABI only to applications that explicitly
  create an EGL context.

`ViewRootImpl` disables HWUI when `ro.ridi.eink_mode=true`. This is essential:
softpipe is compatible with GLES2 but is not fast enough to render ordinary
YES24 or Total Launcher View hierarchies.

## PxP HWC

The HWC accepts an opaque 1404x1872 `ROT_270` app layer, stages it in
PxP-addressable memory and produces an 1872x1404 RGB565 result. The PxP v2
rotation block leaves four rows blank because 1404 is not divisible by eight;
the HWC repairs only those rows on the CPU and then posts through the EPDC
gralloc policy. Any allocation, fence or PxP error falls back to the existing
software compositor.

Measured on the E70Q10:

- staging pattern: 16.5 ms;
- PxP rotate plus RGB565 conversion: 24.1 ms;
- sequential 5.3 MB copy: 26.5 ms;
- total synthetic pipeline: about 67 ms.

The old full CPU RGB565 rotation measured about 419 ms. Run the non-display
test with:

```bash
/system/bin/e70q10_pxp_bench
```

The NXP `libpxp` is patched to use `mmap64()`. Physical DMA addresses such as
`0xa5f00000` become negative through Android's 32-bit `off_t` and make the
original `mmap()` call fail with `EINVAL`.

## AGL / GLES1 recovery path

Select AGL explicitly for recovery comparisons:

Build the current AGL fix:

```bash
E70Q10_GRAPHICS_BACKEND=agl \
E70Q10_LUNCH=e70q10_reference-eng \
E70Q10_OUT_DIR=/media/juwon/build/android-out/e70q10_reference \
E70Q10_BUILD_JOBS=6 \
./tools/build_android8.sh build \
libpixelflinger surfaceflinger libGLES_android ramdisk
```

The PixelFlinger patch rejects scanlines outside the actual color-buffer
width and height. It addresses the repeatable one-pixel write at the end of
the second EPDC framebuffer mapping.

## Mesa softpipe GLES2 compatibility

Mesa is now the default EGL backend, but keep its output separate from the
AGL recovery tree:

```bash
E70Q10_GRAPHICS_BACKEND=mesa \
E70Q10_LUNCH=e70q10_reference-eng \
E70Q10_OUT_DIR=/media/juwon/build/android-out/e70q10_reference_mesa \
E70Q10_BUILD_JOBS=6 \
./tools/build_android8.sh build \
libGLES_mesa gallium_dri libglapi libEGL \
e70q10_egl_bench surfaceflinger ramdisk
```

The Android Mesa backend has an E70Q10 fallback that:

1. tries the normal gralloc DRM FD and `/dev/dri/renderD*` paths;
2. loads Gallium `swrast` when neither exists;
3. uses CPU-accessible ANativeWindow buffers through gralloc lock/unlock;
4. copies the softpipe scanline output using the native buffer stride.

This is sufficient for applications that require a GLES2 context. It is not
the primary SurfaceFlinger or Android View renderer.

Run the benchmark on a Mesa boot:

```bash
/system/bin/e70q10_egl_bench
```

It reports separate `glFinish()` times for:

- full-size 1872x1404 `glClear`;
- full-size clear plus one nearest-filtered textured quad.

EPDC panel update latency is intentionally excluded. The E70Q10 result was:

- full-size clear: 154 ms average;
- clear plus one textured quad: 4194 ms average.

Consequently, a GLES-heavy application remains impractical. CPU Skia apps
can still use the fast PxP/EPDC presentation path, while an occasional GLES2
screen at least has a compatible implementation instead of failing at EGL
initialization.

## Building a Mesa RAM-boot image with the known-good kernel

The separate Mesa output can reuse the AGL kernel, DTB and `mkbootimg`:

```bash
E70Q10_OUT_DIR=/media/juwon/build/android-out/e70q10_reference_mesa \
E70Q10_KERNEL_IMAGE=/media/juwon/build/android-out/e70q10_reference/target/product/e70q10/obj/KERNEL_OBJ/kernel_img \
E70Q10_DTB_IMAGE=/media/juwon/build/android-out/e70q10_reference/target/product/e70q10/obj/KERNEL_OBJ/imx6sl-e70q10.dtb \
E70Q10_MKBOOTIMG=/media/juwon/build/android-out/e70q10_reference/host/linux-x86/bin/mkbootimg \
./tools/make_stock_ramboot.sh \
/media/juwon/build/android-out/e70q10_reference_mesa/target/product/e70q10/e70q10-reference-mesa-swrast-ramboot.img
```

All device tests remain RAM boot plus external SD. Do not flash eMMC.

## Static E Ink update policy

The default AGL path compares every posted framebuffer against a shadow copy.
It skips identical frames and aligns a changed bounding box to eight pixels.
Changes below 70 percent of the panel use an `AUTO` partial update. A large
change, the first frame, or 24 accumulated partial updates uses a full GC16
cleanup update.

These values follow the Tolino/Netronix i.MX6SL waveform numbering and
queue-and-merge behavior, but requests use the Linux 4.9
`mxcfb_update_data` layout. Do not copy the Android 4.4.2 ioctl structure
binary: the newer structure adds dithering and quantization fields.

The current gralloc queues EPDC updates asynchronously, skips identical
frames, aligns dirty rectangles and periodically forces a GC16 cleanup. HWC
waits producer acquire fences before CPU/PxP access and reports synchronous
release after composition.
