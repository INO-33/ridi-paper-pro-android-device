# E70Q10 graphics bring-up

The i.MX6SoloLite has no 3D GPU. Two isolated graphics paths are kept so an
experimental Mesa build cannot replace the AGL recovery candidate.

## AGL / GLES1 / CPU Skia (default)

This is the primary path for YES24 and Total Launcher:

- `libGLES_android` / PixelFlinger for SurfaceFlinger composition
- forced GLES1 SurfaceFlinger context
- `sys.viewroot.hw=false` for CPU-backed application Canvas rendering
- all three Android animation scales set to zero after framework boot

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

## Mesa softpipe (experimental)

Select it only for a separate output directory:

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

This is sufficient to measure an off-screen GLES2 pbuffer and to continue
window-surface bring-up. Importing arbitrary Android layer buffers into
softpipe still needs validation before Mesa is considered a complete
SurfaceFlinger replacement.

Run the benchmark on a Mesa boot:

```bash
/system/bin/e70q10_egl_bench
```

It reports separate `glFinish()` times for:

- full-size 1872x1404 `glClear`;
- full-size clear plus one nearest-filtered textured quad.

EPDC panel update latency is intentionally excluded. Treat the result as:

- 100-300 ms: worth optimizing;
- 300-700 ms: usable only for carefully limited static UI;
- over 1000 ms: do not use softpipe for the complete compositor.

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

The first validation keeps synchronous update completion. This prevents a
page-flipped buffer from being reused while EPDC/PXP still consumes it.
Asynchronous coalescing is deferred until the physical panel output is stable.
