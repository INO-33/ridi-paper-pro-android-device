# Safe framework reference for non-destructive SD-root bring-up.
# Do not inherit the full EVK product: it imports eMMC/verity configuration
# and unavailable private codec payloads.
-include device/fsl/common/imx_path/ImxPathConfig.mk
include device/ridi/e70q10/graphics_backend.mk

$(call inherit-product, $(SRC_TARGET_DIR)/product/generic_no_telephony.mk)

PRODUCT_NAME := e70q10_reference
PRODUCT_DEVICE := e70q10
PRODUCT_BRAND := RIDI
PRODUCT_MODEL := RIDI PAPER PRO (reference)
PRODUCT_MANUFACTURER := RIDI
PRODUCT_CHARACTERISTICS := tablet

PRODUCT_AAPT_CONFIG := normal xhdpi
PRODUCT_AAPT_PREF_CONFIG := xhdpi

ifeq ($(E70Q10_GRAPHICS_BACKEND),mesa)
PRODUCT_PACKAGES += \
    libGLES_mesa \
    e70q10_egl_bench
else
PRODUCT_PACKAGES += libGLES_android
endif

PRODUCT_PACKAGES += \
    gralloc.imx6 \
    hwcomposer.imx6 \
    libion \
    vndk-sp \
    android.hardware.audio@2.0-impl \
    android.hardware.audio@2.0-service \
    android.hardware.audio.effect@2.0-impl \
    android.hardware.keymaster@3.0-impl \
    android.hardware.keymaster@3.0-service \
    android.hardware.graphics.mapper@2.0-impl \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.allocator@2.0-service

PRODUCT_COPY_FILES += \
    device/ridi/e70q10/init.E70Q10.rc:root/init.E70Q10.rc \
    device/fsl/imx6/etc/init.usb.rc:root/init.freescale.usb.rc \
    device/ridi/e70q10/fstab.E70Q10:root/fstab.E70Q10 \
    device/ridi/e70q10/ueventd.E70Q10.rc:root/ueventd.E70Q10.rc \
    device/ridi/e70q10/manifest-minimal.xml:vendor/manifest.xml \
    device/ridi/e70q10/gpio-keys.idc:system/usr/idc/gpio-keys.idc \
    device/ridi/e70q10/cyttsp5_mt.idc:system/usr/idc/cyttsp5_mt.idc \
    device/ridi/e70q10/imx-keypad.kl:system/usr/keylayout/imx-keypad.kl \
    frameworks/native/data/etc/android.hardware.touchscreen.xml:system/etc/permissions/android.hardware.touchscreen.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.xml:system/etc/permissions/android.hardware.touchscreen.multitouch.xml \
    frameworks/native/data/etc/android.hardware.screen.portrait.xml:system/etc/permissions/android.hardware.screen.portrait.xml

$(call inherit-product, device/ridi/e70q10/e70q10_eink_defaults.mk)

PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.secure=0 \
    ro.adb.secure=0 \
    ro.debuggable=1 \
    sys.viewroot.hw=false \
    persist.enable_task_snapshots=false \
    persist.sys.usb.config=adb

ifeq ($(E70Q10_GRAPHICS_BACKEND),mesa)
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += ro.hardware.egl=mesa
else
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += ro.sf.force_gles1=1
endif

PRODUCT_PROPERTY_OVERRIDES += \
    ro.ridi.eink_mode=true \
    ro.sf.lcd_density=300 \
    debug.sf.nobootanimation=1

ifeq ($(E70Q10_GRAPHICS_BACKEND),mesa)
PRODUCT_PROPERTY_OVERRIDES += ro.opengles.version=131072
else
PRODUCT_PROPERTY_OVERRIDES += ro.opengles.version=65537
endif
