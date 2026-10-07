# Positive application allowlist for the E70Q10 reference/reader image.
#
# Do not inherit generic_no_telephony or core.mk here. Despite its name,
# generic_no_telephony still imports phone, Bluetooth, NFC, printing, calendar,
# contacts, mail, music and decorative applications.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_minimal.mk)

# Korean is the reader's default UI language; retain English as fallback.
PRODUCT_LOCALES := ko_KR en_US

# Korean/English reader text, the stock soft keyboard maps, and WebView are
# retained for YES24 login, store and document workflows.
$(call inherit-product-if-exists, frameworks/base/data/fonts/fonts.mk)
$(call inherit-product-if-exists, external/noto-fonts/fonts.mk)
$(call inherit-product-if-exists, external/roboto-fonts/fonts.mk)
$(call inherit-product-if-exists, external/hyphenation-patterns/patterns.mk)
$(call inherit-product-if-exists, frameworks/base/data/keyboards/keyboards.mk)
# WebView needs no inherit here: frameworks/webview/chromium/chromium.mk does not
# exist in this tree, so that line was a silent no-op. core_minimal.mk above is
# what actually installs webview, webview_zygote, libwebviewchromium_loader,
# libwebviewchromium_plat_support and android.software.webview.xml.

# User-visible and provider components required by the reader workflow.
# PAPER Home draws the fixed shelf itself without a wallpaper service.
PRODUCT_PACKAGES += \
    Browser2 \
    CaptivePortalLogin \
    CertInstaller \
    DefaultContainerService \
    DocumentsUI \
    Dropship \
    DownloadProviderUi \
    ExternalStorageProvider \
    InputDevices \
    KeyChain \
    Keyguard \
    LatinIME \
    RidiPaperLauncher \
    MtpDocumentsProvider \
    PacProcessor \
    PackageInstaller \
    Provision \
    ProxyHandler \
    Settings \
    StorageManager \
    SystemUI \
    UserDictionaryProvider \
    VpnDialogs \
    ridi_webview \
    libpac

# These packages are loaded into system_server and must be declared here as
# well as being installed. dex_preopt_odex_install.mk already forces the 'speed'
# filter on this list.
PRODUCT_SYSTEM_SERVER_APPS += \
    InputDevices \
    KeyChain

# PRODUCT_DEXPREOPT_SPEED_APPS is intentionally not set. It only affects
# build-time dexpreopt, which BoardConfig.mk explains cannot run on this host.
# PackageManager instead gives only the boot-critical UI packages a targeted
# on-device speed compile before SystemUI starts; all other applications keep
# the normal eng policy so first boot does not turn into a full-device AOT pass.

# Preserve the already validated no-device audio fallback and basic power/time
# HALs. No music, TTS, recorder or hardware audio application is included.
PRODUCT_PACKAGES += \
    audio.primary.default \
    local_time.default \
    power.default \
    librs_jni

# Ship the complete stock sleep-image collection inside the read-only system image.
PRODUCT_COPY_FILES += $(foreach image,$(wildcard device/ridi/e70q10/sleep/*),$(image):system/usr/sleep/$(notdir $(image)))
PRODUCT_COPY_FILES += device/ridi/e70q10/preferred-apps.xml:system/etc/preferred-apps/ridi-home.xml

# Defaults for fresh userdata; an explicitly saved timezone remains authoritative.
PRODUCT_PROPERTY_OVERRIDES += persist.sys.timezone=Asia/Seoul
