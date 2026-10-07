# Device-local System WebView prebuilt for the RIDI Android O product.
# The APK is copied byte-for-byte so libwebviewchromium.so remains stored and
# the package name inside the signed artifact stays com.android.webview.

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := ridi_webview
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_PATH := $(TARGET_OUT_APPS)
LOCAL_MODULE_STEM := webview.apk
LOCAL_BUILT_MODULE_STEM := webview.apk
LOCAL_OVERRIDES_PACKAGES := webview
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := false
LOCAL_SRC_FILES := SystemWebView.apk

include $(BUILD_PREBUILT)
