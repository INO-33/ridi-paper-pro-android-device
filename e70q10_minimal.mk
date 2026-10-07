# Minimal Android 8 bring-up product for RAM boot and external-SD filesystems.
# It deliberately omits Wi-Fi, Bluetooth, camera, audio, OMX and GMS.
-include device/fsl/common/imx_path/ImxPathConfig.mk

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_minimal.mk)

PRODUCT_NAME := e70q10_minimal
PRODUCT_DEVICE := e70q10
PRODUCT_BRAND := RIDI
PRODUCT_MODEL := RIDI PAPER PRO (bring-up)
PRODUCT_MANUFACTURER := RIDI
PRODUCT_CHARACTERISTICS := tablet

PRODUCT_AAPT_CONFIG := normal xhdpi
PRODUCT_AAPT_PREF_CONFIG := xhdpi

$(call inherit-product, device/ridi/e70q10/e70q10_eink_defaults.mk)

PRODUCT_PACKAGES += \
    ridi_webview \
    gralloc.imx6 \
    hwcomposer.imx6 \
    libion \
    vndk-sp \
    android.hardware.graphics.mapper@2.0-impl \
    android.hardware.graphics.allocator@2.0-impl

PRODUCT_COPY_FILES += \
    device/ridi/e70q10/init.E70Q10.rc:root/init.E70Q10.rc \
    device/ridi/e70q10/fstab.E70Q10:root/fstab.E70Q10 \
    device/ridi/e70q10/ueventd.E70Q10.rc:root/ueventd.E70Q10.rc \
    device/ridi/e70q10/manifest-minimal.xml:vendor/manifest.xml \
    device/ridi/e70q10/gpio-keys.idc:system/usr/idc/gpio-keys.idc \
    device/ridi/e70q10/cyttsp5_mt.idc:system/usr/idc/cyttsp5_mt.idc \
    device/ridi/e70q10/imx-keypad.kl:system/usr/keylayout/imx-keypad.kl \
    frameworks/native/data/etc/android.hardware.touchscreen.xml:system/etc/permissions/android.hardware.touchscreen.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.xml:system/etc/permissions/android.hardware.touchscreen.multitouch.xml \
    frameworks/native/data/etc/android.hardware.screen.portrait.xml:system/etc/permissions/android.hardware.screen.portrait.xml

PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.secure=0 \
    ro.adb.secure=0 \
    ro.debuggable=1 \
    persist.sys.usb.config=adb

PRODUCT_PROPERTY_OVERRIDES += \
    ro.sf.lcd_density=300 \
    ro.opengles.version=131072 \
    debug.sf.nobootanimation=1
