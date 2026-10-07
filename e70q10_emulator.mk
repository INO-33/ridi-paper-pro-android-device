# RIDI PAPER PRO userspace emulator.
#
# This deliberately inherits the AOSP x86 emulator instead of the i.MX6SL
# board product.  Running the guest with KVM removes ARM instruction
# translation from framework/UI latency measurements while still exercising
# the same patched Android framework and virtual E Ink policy transport.  It
# does not pretend to emulate EPDC, PMIC, touch or Wi-Fi hardware.
-include device/fsl/common/imx_path/ImxPathConfig.mk
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_x86.mk)

# PRODUCT overlays are evaluated before DEVICE overlays. Keep RIDI here so it
# wins over the goldfish device overlay inherited by aosp_x86; otherwise
# goldfish's Google-only WebView provider list replaces our AOSP provider.
PRODUCT_PACKAGE_OVERLAYS := device/ridi/e70q10/overlay $(PRODUCT_PACKAGE_OVERLAYS)

PRODUCT_PACKAGES += Dropship

PRODUCT_PROPERTY_OVERRIDES += \
    ro.hardware.app=freescale \
    ro.sf.lcd_density=320 \
    ro.config.low_ram=true \
    ro.ridi.disable_nav_animations=true \
    ro.paper.virtual_epdc=true \
    ro.ridi.epd.vsync_hz=15

PRODUCT_AAPT_CONFIG := normal xhdpi
PRODUCT_AAPT_PREF_CONFIG := xhdpi

# The legacy non-Treble META-EGL loader also expects its driver selector in
# /system/lib/egl.  This copy is part of the emulator product only.
PRODUCT_COPY_FILES += \
    device/generic/goldfish-opengl/system/egl/egl.cfg:system/lib/egl/egl.cfg \
    device/ridi/e70q10/assets/bootanimation-stock-702x936.zip:system/media/bootanimation.zip \
    device/ridi/e70q10/e70q10_emulator/init.paper_emulator.rc:system/etc/init/init.paper_emulator.rc

PRODUCT_NAME := e70q10_emulator
PRODUCT_DEVICE := e70q10_emulator
PRODUCT_BRAND := RIDI
PRODUCT_MODEL := RIDI PAPER PRO Emulator
PRODUCT_MANUFACTURER := RIDI
PRODUCT_CHARACTERISTICS := tablet
