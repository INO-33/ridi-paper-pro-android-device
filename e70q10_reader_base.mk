# Positive application allowlist for the E70Q10 reference/reader image.
#
# Do not inherit generic_no_telephony or core.mk here. Despite its name,
# generic_no_telephony still imports phone, Bluetooth, NFC, printing, calendar,
# contacts, mail, music and decorative applications.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_minimal.mk)

# Korean/English reader text, the stock soft keyboard maps, and WebView are
# retained for YES24 login, store and document workflows.
$(call inherit-product-if-exists, frameworks/base/data/fonts/fonts.mk)
$(call inherit-product-if-exists, external/noto-fonts/fonts.mk)
$(call inherit-product-if-exists, external/roboto-fonts/fonts.mk)
$(call inherit-product-if-exists, external/hyphenation-patterns/patterns.mk)
$(call inherit-product-if-exists, frameworks/base/data/keyboards/keyboards.mk)
$(call inherit-product-if-exists, frameworks/webview/chromium/chromium.mk)

# User-visible and provider components required by the reader workflow.
# Launcher2 remains as a recovery HOME until Total Launcher is preinstalled in
# the product rather than only in /data.
PRODUCT_PACKAGES += \
    CaptivePortalLogin \
    CertInstaller \
    DefaultContainerService \
    DocumentsUI \
    DownloadProviderUi \
    ExternalStorageProvider \
    InputDevices \
    KeyChain \
    Keyguard \
    LatinIME \
    Launcher2 \
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
    libpac

# These packages are loaded into system_server and must be declared here as
# well as being installed.
PRODUCT_SYSTEM_SERVER_APPS += \
    InputDevices \
    KeyChain

# Preserve the already validated no-device audio fallback and basic power/time
# HALs. No music, TTS, recorder or hardware audio application is included.
PRODUCT_PACKAGES += \
    audio.primary.default \
    local_time.default \
    power.default \
    librs_jni
