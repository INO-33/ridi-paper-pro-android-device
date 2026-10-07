# Standard 32-bit ARMv7 Goldfish/Ranchu image layout. This board is selected
# only by PRODUCT_DEVICE=e70q10_arm.
include build/target/board/generic/BoardConfig.mk

# Keep the boot image preoptimized, but compile applications in guest /data.
# This avoids old host dex2oat address assumptions on current Linux hosts.
WITH_DEXPREOPT := true
WITH_DEXPREOPT_BOOT_IMG_ONLY := true

# The RIDI E Ink policy transport is implemented on the Oreo HWC1 path.
TARGET_USES_HWC2 := false

# Keep the legacy non-Treble META-EGL lookup compatible with the paper target.
PAPER_EMULATOR_SYSTEM_EGL := true

BOARD_SYSTEMIMAGE_PARTITION_SIZE := 1073741824
