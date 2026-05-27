TARGET := iphone:clang:16.2:15.0
INSTALL_TARGET_PROCESSES = Facebook
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FBTweaks

FBTWEAKS_SRC_FILES := $(shell find src -type f \( -iname \*.x -o -iname \*.xm -o -iname \*.m \))

$(TWEAK_NAME)_FILES = $(FBTWEAKS_SRC_FILES) modules/fishhook/fishhook.c

$(TWEAK_NAME)_FRAMEWORKS = \
	UIKit \
	Foundation \
	CoreGraphics \
	QuartzCore \
	Security

$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(TWEAK_NAME)_LIBRARIES = substrate

$(TWEAK_NAME)_CFLAGS = \
	-fobjc-arc \
	-Wno-unsupported-availability-guard \
	-Wno-unused-value \
	-Wno-deprecated-declarations \
	-Wno-nullability-completeness \
	-Wno-unused-function \
	-Wno-incompatible-pointer-types \
	-Imodules/fishhook

$(TWEAK_NAME)_LOGOSFLAGS = --c warnings=none

CCFLAGS += -std=c++11

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support/FBTweaks"
	@cp -f docs/*.md "$(THEOS_STAGING_DIR)/Library/Application Support/FBTweaks/" 2>/dev/null || true
