# RIDI PAPER PRO userspace emulator using the AOSP ARMv7 Goldfish/Ranchu ABI.
# This remains separate from both the x86 emulator and the physical i.MX6SL
# products, so changing emulator architectures cannot alter a device image.
-include device/fsl/common/imx_path/ImxPathConfig.mk
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_arm.mk)

PRODUCT_PACKAGE_OVERLAYS := device/ridi/e70q10/overlay $(PRODUCT_PACKAGE_OVERLAYS)

PRODUCT_PACKAGES += \
    Dropship \
    ridi_webview

PRODUCT_PROPERTY_OVERRIDES += \
    ro.hardware.app=freescale \
    ro.sf.lcd_density=320 \
    ro.config.low_ram=true \
    ro.ridi.disable_nav_animations=true \
    ro.paper.virtual_epdc=true \
    ro.ridi.epd.vsync_hz=15

PRODUCT_AAPT_CONFIG := normal xhdpi
PRODUCT_AAPT_PREF_CONFIG := xhdpi

PRODUCT_COPY_FILES += \
    device/generic/goldfish-opengl/system/egl/egl.cfg:system/lib/egl/egl.cfg \
    frameworks/native/data/etc/android.hardware.ethernet.xml:system/etc/permissions/android.hardware.ethernet.xml \
    device/ridi/e70q10/assets/bootanimation-stock-702x936.zip:system/media/bootanimation.zip \
    device/ridi/e70q10/e70q10_emulator/init.paper_emulator.rc:system/etc/init/init.paper_emulator.rc

PRODUCT_NAME := e70q10_emulator_armv7
PRODUCT_DEVICE := e70q10_arm
PRODUCT_BRAND := RIDI
PRODUCT_MODEL := RIDI PAPER PRO Emulator ARMv7
PRODUCT_MANUFACTURER := RIDI
PRODUCT_CHARACTERISTICS := tablet
