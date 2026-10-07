LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := e70q10_power_diag
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := power_diag.c
LOCAL_CFLAGS := -Wall -Wextra -Werror
include $(BUILD_EXECUTABLE)
