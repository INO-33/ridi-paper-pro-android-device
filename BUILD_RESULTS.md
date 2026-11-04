# E70Q10 reference build results

## Successful build

- Product: `e70q10_reference-eng`
- Output: `/media/juwon/build/android-out/e70q10_reference`
- Result: `systemimage` and `vendorimage` completed successfully
- Output tree size: approximately 45 GiB

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `boot.img` | 11,753,472 | `f605d14c26a44026dfd405736968a945a4026e62fb41f0ed42d9e7d05783002f` |
| `ramdisk.img` | 1,704,886 | `aa36ecf08baacd8e80c87113e08140d26ecf168dc3d9bd7fed873e74ddddfe2d` |
| `system.img` | 504,504,404 | `2d6a7caab7ba68bf9a674df656e04f326c50d0925d7c46b7ed89d9b404e98f89` |
| `vendor.img` | 8,590,168 | `371a5d85e5903529bf9192646f328d32530752d6770d10cdf318f47d0ed70874` |
| `e70q10-reference-stock-ramboot.img` | 11,751,424 | `3b9b2f5cd017782846f9cdf940a2d3ef59526ceacdeb107f20513394e673ebfb` |

The sparse image sizes above are not the required SD partition sizes. Use the
partition sizes from `BoardConfig.mk` and leave additional operational margin.

## Host compatibility fixes confirmed by the build

- Android Python wrappers find the local Python 2 through `PATH`.
- Jack uses a localhost-only legacy TLS compatibility policy on current
  OpenJDK 8.
- The unavailable private NXP FSL extractor is omitted while AOSP extractors
  remain.
- The DocumentsUI USB shortcut resource typo is fixed.
- The 256 MiB vendor partition avoids the legacy `make_ext4fs` 128 MiB
  block-group boundary.

## Runtime validation

The reference userspace now reaches `sys.boot_completed=1` from the external
SD while the kernel is started with `fastboot boot`. SurfaceFlinger runs on
AGL/PixelFlinger GLES1, the no-device audio and software keymaster services
start, Total Launcher runs, and the YES24 fixed-orientation launch path no
longer crashes `system_server`.

No eMMC partition is written. The remaining display validation is the static
E Ink framework policy plus gralloc changed-region EPDC refresh build currently
described in `GRAPHICS_BRINGUP.md`.
