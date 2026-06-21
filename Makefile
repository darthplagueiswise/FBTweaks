TARGET := iphone:clang:26.2:16.3
INSTALL_TARGET_PROCESSES = Facebook
ARCHS = arm64

# Rootless por padrão (pode ser sobrescrito pelo build.sh / CI).
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FBTweak

# Todos os fontes de src/ (.x/.xm/.m) + fishhook.
# Theos roteia por extensão: Logos p/ .x/.xm, clang p/ .m/.c.
$(TWEAK_NAME)_FILES = $(shell find src -type f \( -iname \*.x -o -iname \*.xm -o -iname \*.m \)) modules/fishhook/fishhook.c

$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CoreServices Security SystemConfiguration
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(TWEAK_NAME)_USE_MODULES = 0

# Defines TARGET_OS_* para os headers do SDK iPhoneOS26.2 resolverem sob Theos.
FBT_TARGET_FLAGS = -DTARGET_OS_MAC=1 -DTARGET_OS_OSX=0 -DTARGET_OS_IPHONE=1 -DTARGET_OS_IOS=1 -DTARGET_OS_EMBEDDED=1 -DTARGET_OS_SIMULATOR=0 -DTARGET_OS_MACCATALYST=0 -DTARGET_OS_UIKITFORMAC=0 -DTARGET_OS_TV=0 -DTARGET_OS_WATCH=0 -DTARGET_OS_VISION=0 -DTARGET_OS_BRIDGE=0 -DTARGET_OS_DRIVERKIT=0

# Logger master switch. Build com FBT_FILELOG=0 para producao.
FBT_FILELOG ?= 1

$(TWEAK_NAME)_CFLAGS = -I$(CURDIR)/src -fobjc-arc -F$(THEOS)/sdks/iPhoneOS26.2.sdk/System/Library/SubFrameworks $(FBT_TARGET_FLAGS) -Wno-unsupported-availability-guard -Wno-unused-value -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-unused-function -Wno-incompatible-pointer-types -DFBT_FILELOG=$(FBT_FILELOG) -include src/FBTPrefix.h
$(TWEAK_NAME)_LOGOSFLAGS = --c warnings=none

# UI é UIKit puro; sem Swift/bridging header/modulemap.

ifeq ($(FINALPACKAGE),1)
	$(TWEAK_NAME)_LDFLAGS += -Wl,-x
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,_FBT*
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,_fbt*
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,_kFBT*
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,__Z*
endif

CCFLAGS += -std=c++11

include $(THEOS_MAKE_PATH)/tweak.mk
