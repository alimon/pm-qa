include $(call all-subdir-makefiles)
LOCAL_PATH:= $(call my-dir)

module_name = utils

define $(module_name)_etc_add_executable
    include $(CLEAR_VARS)
    LOCAL_MODULE_TAGS := optional 
    LOCAL_MODULE_CLASS := tests
    LOCAL_MODULE := $1
    systemtarball: $1
    systemimage: $1
    LOCAL_SRC_FILES := $1.c
    LOCAL_CFLAGS += -Wno-error
    LOCAL_MODULE_PATH := $(TARGET_OUT_EXECUTABLES)/pm-qa/$(module_name)
    include $(BUILD_EXECUTABLE)
endef

test_names := cpuburn cpucycle heat_cpu nanosleep uevent_reader
$(foreach item,$(test_names),$(eval $(call $(module_name)_etc_add_executable, $(item))))
