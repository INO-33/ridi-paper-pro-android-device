# Safe framework reference for non-destructive SD-root bring-up.
# Do not inherit the full EVK product: it imports eMMC/verity configuration
# and unavailable private codec payloads.
-include device/fsl/common/imx_path/ImxPathConfig.mk
include device/ridi/e70q10/graphics_backend.mk

$(call inherit-product, device/ridi/e70q10/e70q10_reader_base.mk)

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
    gallium_dri \
    libglapi \
    e70q10_egl_bench
else
PRODUCT_PACKAGES += libGLES_android
endif

PRODUCT_PACKAGES += \
    e70q10_pxp_bench \
    libpxp \
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
    android.hardware.graphics.allocator@2.0-service \
    lights.imx6 \
    android.hardware.light@2.0-impl \
    android.hardware.light@2.0-service \
    android.hardware.wifi@1.0-service \
    wificond \
    wpa_supplicant \
    wpa_supplicant_overlay.conf

PRODUCT_COPY_FILES += \
    device/ridi/e70q10/init.E70Q10.rc:root/init.E70Q10.rc \
    device/fsl/imx6/etc/init.usb.rc:root/init.freescale.usb.rc \
    device/ridi/e70q10/fstab.E70Q10:root/fstab.E70Q10 \
    device/ridi/e70q10/ueventd.E70Q10.rc:root/ueventd.E70Q10.rc \
    device/ridi/e70q10/manifest-minimal.xml:vendor/manifest.xml \
    device/ridi/e70q10/prebuilt/8189fs.ko:vendor/lib/modules/8189fs.ko \
    device/ridi/e70q10/e70q10-wifi-prepare.sh:system/bin/e70q10-wifi-prepare \
    device/ridi/e70q10/wpa_supplicant.conf:system/etc/wifi/wpa_supplicant.conf \
    device/ridi/e70q10/gpio-keys.idc:system/usr/idc/gpio-keys.idc \
    device/ridi/e70q10/cyttsp5_mt.idc:system/usr/idc/cyttsp5_mt.idc \
    device/ridi/e70q10/imx-keypad.kl:system/usr/keylayout/imx-keypad.kl \
    frameworks/native/data/etc/android.hardware.touchscreen.xml:system/etc/permissions/android.hardware.touchscreen.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.xml:system/etc/permissions/android.hardware.touchscreen.multitouch.xml \
    frameworks/native/data/etc/android.hardware.screen.portrait.xml:system/etc/permissions/android.hardware.screen.portrait.xml \
    frameworks/native/data/etc/android.hardware.wifi.xml:system/etc/permissions/android.hardware.wifi.xml

E70Q10_EPDC_WAVEFORM := device/ridi/e70q10/stock-blobs/imx/epdc/epdc_ED078KH1.fw
ifneq ($(wildcard $(E70Q10_EPDC_WAVEFORM)),)
PRODUCT_COPY_FILES += \
    $(E70Q10_EPDC_WAVEFORM):vendor/firmware/imx/epdc/epdc_ED078KH1.fw
else
$(warning Missing extracted E70Q10 EPDC waveform: $(E70Q10_EPDC_WAVEFORM))
endif

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
    ro.hardware.app=freescale \
    ro.radio.noril=yes \
    hw.backlight.dev=lm3630a_led \
    wifi.interface=wlan0 \
    ro.sf.lcd_density=300 \
    debug.sf.nobootanimation=1

ifeq ($(E70Q10_GRAPHICS_BACKEND),mesa)
PRODUCT_PROPERTY_OVERRIDES += ro.opengles.version=131072
else
PRODUCT_PROPERTY_OVERRIDES += ro.opengles.version=65537
endif
