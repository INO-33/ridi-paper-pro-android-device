# Defaults shared by E70Q10 engineering products.
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += persist.ridi.buffer_age_partial=1

DEVICE_PACKAGE_OVERLAYS += device/ridi/e70q10/overlay

PRODUCT_COPY_FILES += \
    device/ridi/e70q10/e70q10-eink-settings.sh:system/bin/e70q10-eink-settings

# ---------------------------------------------------------------------------
# Low-memory profile
#
# The board has 1 GB of DDR minus a 6 MB carveout (imx6sl-e70q10.dts memory
# node is 0x80000000 + 0x3fa00000) and ships no GMS, so the reader is treated
# as a low-RAM device. In AOSP Oreo ro.config.low_ram is read through
# RoSystemProperties.CONFIG_LOW_RAM and measurably changes:
#   - ActiveServices: concurrent background services 8 -> 1
#   - BroadcastQueue: history/summary buffers 50/300 -> 10/25
#   - ActivityManager.getMaxRecentTasksStatic(): 48 -> 36
#   - ActivityManager.isHighEndGfx(): false, so persistent processes stop
#     using hardware drawing acceleration
# The only capability lost is multi-window, which this device never exposes.
#
# isHighEndGfx() also gates the system bar background in BarTransitions; that
# path now honours config_fixedColorSystemBars so the bars stay white here.
# ---------------------------------------------------------------------------
$(call inherit-product, frameworks/native/build/phone-xhdpi-1024-dalvik-heap.mk)

PRODUCT_PROPERTY_OVERRIDES += \
    ro.config.low_ram=true \
    ro.ridi.disable_nav_animations=true
