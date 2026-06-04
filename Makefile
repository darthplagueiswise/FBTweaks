TARGET := iphone:clang:26.0:16.3
INSTALL_TARGET_PROCESSES = Facebook
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FBTweaks

FBTWEAKS_SRC_FILES := $(shell find src -type f \( -iname \*.x -o -iname \*.xm -o -iname \*.m \))

$(TWEAK_NAME)_FILES = $(FBTWEAKS_SRC_FILES) modules/fishhook/fishhook.c

$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(TWEAK_NAME)_LIBRARIES = substrate z
$(TWEAK_NAME)_USE_MODULES = 0

$(TWEAK_NAME)_CFLAGS = \
	-fobjc-arc \
	-F$(THEOS)/sdks/iPhoneOS26.0.sdk/System/Library/SubFrameworks \
	-F$(THEOS)/sdks/iPhoneOS26.0.sdk/System/Library/Frameworks/Accelerate.framework/Frameworks \
	-Wno-unsupported-availability-guard \
	-Wno-unused-value \
	-Wno-deprecated-declarations \
	-Wno-nullability-completeness \
	-Wno-unused-function \
	-Wno-incompatible-pointer-types \
	-Imodules/fishhook

$(TWEAK_NAME)_LOGOSFLAGS = --c warnings=none
$(TWEAK_NAME)_LDFLAGS += -fuse-ld=lld -lcompression

CCFLAGS += -std=c++11

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support/FBTweaks"
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support/FBTweaks/runtime"
	@cp -f resources/runtime/*.json.gz "$(THEOS_STAGING_DIR)/Library/Application Support/FBTweaks/runtime/" 2>/dev/null || true
	@cp -f resources/runtime/*.json "$(THEOS_STAGING_DIR)/Library/Application Support/FBTweaks/runtime/" 2>/dev/null || true
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support/FBTweaks/docs"
	@cp -f docs/*.md "$(THEOS_STAGING_DIR)/Library/Application Support/FBTweaks/docs/" 2>/dev/null || true
