# Keep the standard 32-bit x86 Goldfish/Ranchu ABI and emulator image layout.
# This board file is selected only by PRODUCT_DEVICE=e70q10_emulator and has
# no effect on the physical i.MX6SL products.
include build/target/board/generic_x86/BoardConfig.mk

# Current x86_64 hosts may ignore Oreo dex2oat's requested 32-bit boot-image
# address while preoptimizing individual applications.  Keep the boot image
# preoptimized, but let Android compile applications into /data on first boot.
# This is also the policy used by the physical E70Q10 engineering product.
WITH_DEXPREOPT := true
WITH_DEXPREOPT_BOOT_IMG_ONLY := true

# The E70Q10 policy transport is implemented on the Oreo HWC1 path.  Goldfish
# supplies both HWC generations, so select HWC1 for the paper emulator.
TARGET_USES_HWC2 := false

# Oreo's Goldfish GLES modules are marked as vendor modules, but this legacy
# non-Treble emulator image uses a META-EGL loader which looks in
# /system/lib/egl when qemu.gles=1.  Keep this exception scoped to this board;
# physical E70Q10 products do not include this BoardConfig.
PAPER_EMULATOR_SYSTEM_EGL := true

# The AOSP emulator image is comfortably below this size.  Keeping the image
# smaller avoids wasting host disk space in this old non-sparse configuration.
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 1073741824
