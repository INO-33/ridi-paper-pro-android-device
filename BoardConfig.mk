# Reuse the NXP i.MX6SoloLite SoC and common Android baseline without pulling
# in the EVK partition table, Broadcom Wi-Fi, camera or modem configuration.
include device/fsl/imx6/soc/imx6sl.mk
include device/fsl/imx6/BoardConfigCommon.mk

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
BOARD_HAVE_WIFI := false
BOARD_NOT_HAVE_MODEM := true
BOARD_HAVE_IMX_CAMERA := false
USE_CAMERA_STUB := true
PREBUILT_FSL_IMX_CODEC := false
PREBUILT_FSL_IMX_OMX := false

TARGET_RECOVERY_FSTAB := device/ridi/e70q10/fstab.E70Q10
TARGET_BOARD_KERNEL_HEADERS := device/fsl/common/kernel-headers

BOARD_SEPOLICY_DIRS := \
    device/fsl/imx6/sepolicy

# These images are not flashable to the stock 6 MiB boot / 384 MiB system
# partitions. They are inputs for fastboot RAM boot and external-SD bring-up.
