# Initial RIDI PAPER PRO product definition.  Not flashable until the partition
# map, EPDC support and kernel drivers listed in README.md are completed.
$(call inherit-product, device/fsl/imx6/evk_6sl.mk)

PRODUCT_NAME := e70q10
PRODUCT_DEVICE := e70q10
PRODUCT_BRAND := RIDI
PRODUCT_MODEL := RIDI PAPER PRO
PRODUCT_MANUFACTURER := RIDI
PRODUCT_CHARACTERISTICS := tablet

PRODUCT_PROPERTY_OVERRIDES += \
    ro.ridi.disable_nav_animations=true

PRODUCT_PACKAGES += \
    Dropship \
    ridi_webview

PRODUCT_AAPT_CONFIG := normal xhdpi
PRODUCT_AAPT_PREF_CONFIG := xhdpi

PRODUCT_COPY_FILES += \
    device/ridi/e70q10/assets/bootanimation-stock-1404x1872.zip:system/media/bootanimation.zip \
    device/ridi/e70q10/gpio-keys.idc:system/usr/idc/gpio-keys.idc \
    device/ridi/e70q10/cyttsp5_mt.idc:system/usr/idc/cyttsp5_mt.idc \
    device/ridi/e70q10/imx-keypad.kl:system/usr/keylayout/imx-keypad.kl
