# Reuse the NXP i.MX6SoloLite SoC and common Android baseline without pulling
# in the EVK partition table, Broadcom Wi-Fi, camera or modem configuration.
include device/fsl/imx6/soc/imx6sl.mk
include device/fsl/imx6/BoardConfigCommon.mk
include device/ridi/e70q10/graphics_backend.mk

BUILD_TARGET_FS := ext4
include device/fsl/imx6/imx6_target_fs.mk

TARGET_BOOTLOADER_BOARD_NAME := E70Q10
PRODUCT_MODEL := RIDI_PAPER_PRO
TARGET_KERNEL_DEFCONF := e70q10_defconfig
TARGET_BOARD_DTS_CONFIG := imx6sl:imx6sl-e70q10.dtb

# The public NXP HWC2 path requires unavailable proprietary g2dExt/libg2d
# components. Oreo still provides its direct HWC1 SurfaceFlinger path, and the
# NXP v1 gralloc already contains the EPDC update implementation.
TARGET_GRALLOC_VERSION := v1
TARGET_USES_HWC2 := false
TARGET_HWCOMPOSER_VERSION := v1.0
TARGET_HAVE_VIV_HWCOMPOSER := false
PREBUILT_FSL_IMX_GPU := false
NUM_FRAMEBUFFER_SURFACE_BUFFERS := 3
TARGET_USE_PAN_DISPLAY := true
# Keep the legacy gralloc0 allocator in SurfaceFlinger. Its HW_FB page
# allocator and passthrough mapper must share one module instance so
# registerBuffer()/unregisterBuffer() describe the real BufferQueue lifetime.
SF_START_GRAPHICS_ALLOCATOR_SERVICE := true
ifeq ($(E70Q10_GRAPHICS_BACKEND),mesa)
BOARD_GPU_DRIVERS := swrast
endif

BOARD_KERNEL_CMDLINE := console=ttymxc0,115200 init=/init \
    androidboot.console=ttymxc0 consoleblank=0 no_console_suspend \
    androidboot.hardware=E70Q10 video=mxcepdcfb:ED078KH1,bpp=16 mem=1018M \
    panic=10 oops=panic loglevel=7

ifneq ($(TARGET_BUILD_VARIANT),user)
BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive
endif

# RAM/SD bring-up images. These values do not describe the stock eMMC layout.
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 805306368
# Avoid the legacy make_ext4fs one-block-group boundary at exactly 128 MiB.
# This is an SD bring-up image; sparse output does not consume the empty size.
BOARD_VENDORIMAGE_PARTITION_SIZE := 268435456
BOARD_CACHEIMAGE_PARTITION_SIZE := 67108864
BOARD_USERDATAIMAGE_PARTITION_SIZE := 2147483648
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_VENDOR := vendor

TARGET_NO_RECOVERY := true
BOARD_HAVE_BLUETOOTH := false
BOARD_HAVE_WIFI := true
BOARD_NOT_HAVE_MODEM := true
BOARD_HAVE_IMX_CAMERA := false
USE_CAMERA_STUB := true
PREBUILT_FSL_IMX_CODEC := false
PREBUILT_FSL_IMX_OMX := false

# RTL8189FTV (SDIO 024c:f179). The ported driver exposes nl80211/cfg80211.
# A small legacy vendor HAL supplies the wlan0 handle Android O's HIDL service
# requires; wificond and wpa_supplicant perform scanning and association.
BOARD_WLAN_DEVICE := rtl8189fs
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_HOSTAPD_DRIVER := NL80211
WIFI_DRIVER_MODULE_PATH := "/vendor/lib/modules/8189fs.ko"
WIFI_DRIVER_MODULE_NAME := "8189fs"
WIFI_DRIVER_MODULE_ARG := "rtw_power_mgnt=0 rtw_enusbss=0"

TARGET_RECOVERY_FSTAB := device/ridi/e70q10/fstab.E70Q10
TARGET_BOARD_KERNEL_HEADERS := device/fsl/common/kernel-headers

BOARD_SEPOLICY_DIRS := \
    device/fsl/imx6/sepolicy \
    device/ridi/e70q10/sepolicy

# These images are not flashable to the stock 6 MiB boot / 384 MiB system
# partitions. They are inputs for fastboot RAM boot and external-SD bring-up.

# Applications are deliberately not dexpreopted at build time.
#
# build/make/core/dex_preopt.mk defaults WITH_DEXPREOPT_BOOT_IMG_ONLY to true on
# eng builds, which is what this device wants. Clearing it does not buy anything:
# the device runs dex2oat once, during the first boot after the image is
# written, and caches the result in /data/dalvik-cache. Later boots reuse that
# cache, so applications are not interpreted "on every boot". PackageManager
# gives SystemUI and the two HOME packages a product-specific quicken pass
# before SystemUI starts; other applications retain the normal eng policy.
#
# It also cannot be built here. Application dexpreopt makes the host dex2oat
# load the target boot image at the fixed base address it was built for
# (0x7036b000), dexpreopt passes -Xnorelocate so it may not move it, and a
# current kernel ignores the address hint:
#
#   Failed to mmap at expected address, mapped at 0x7ffff4c00000
#       instead of 0x7036b000
#   Dex file fallback disabled, cannot continue without image
#
# Every application then fails to compile and no system image can be built.
# setarch -R does not help; it would need "sudo sysctl -w vm.mmap_rnd_bits=28"
# on the build host. Not worth a host-wide change to ASLR entropy for work the
# device already does once by itself.
