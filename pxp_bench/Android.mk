LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := e70q10_pxp_bench
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := pxp_bench.cpp
LOCAL_SHARED_LIBRARIES := libpxp liblog
LOCAL_C_INCLUDES := vendor/nxp-opensource/imx-lib/pxp
LOCAL_CLANG := true
LOCAL_CFLAGS := -Wall -Wextra -Werror
include $(BUILD_EXECUTABLE)
