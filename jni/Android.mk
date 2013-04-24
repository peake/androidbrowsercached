LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE	:= androidbrowsercached
LOCAL_SRC_FILES	:= androidbrowsercached.c

include $(BUILD_EXECUTABLE)
