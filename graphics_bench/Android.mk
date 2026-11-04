LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := e70q10_egl_bench
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := egl_pbuffer_bench.cpp
LOCAL_SHARED_LIBRARIES := libEGL libGLESv2 liblog
LOCAL_CLANG := true
LOCAL_CFLAGS := -Wall -Wextra -Werror
include $(BUILD_EXECUTABLE)
