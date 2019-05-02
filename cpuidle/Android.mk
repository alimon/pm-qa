include $(call all-subdir-makefiles)
LOCAL_PATH:= $(call my-dir)

module_name = cpuidle

define $(module_name)_add_executable
    include $(CLEAR_VARS)
    LOCAL_MODULE_TAGS := optional 
    LOCAL_MODULE_CLASS := tests
    LOCAL_MODULE := $1.sh
    systemtarball: $1.sh
    systemimage: $1.sh
    LOCAL_SRC_FILES := $1.sh
    LOCAL_MODULE_PATH := $(TARGET_OUT_EXECUTABLES)/pm-qa/$(module_name)
    include $(BUILD_PREBUILT)
endef

test_num := sanity 01 02 03
$(foreach item,$(test_num),$(eval $(call $(module_name)_add_executable, $(module_name)_$(item))))

include $(CLEAR_VARS)
LOCAL_MODULE := cpuidle_killer
systemtarball: cpuidle_killer
systemimage: cpuidle_killer
LOCAL_SRC_FILES:= cpuidle_killer.c
LOCAL_CFLAGS += -Wno-error
LOCAL_SHARED_LIBRARIES := libcutils libc
LOCAL_MODULE_TAGS := tests
LOCAL_MODULE_PATH := $(TARGET_OUT_EXECUTABLES)/pm-qa/$(module_name)
include $(BUILD_EXECUTABLE)
