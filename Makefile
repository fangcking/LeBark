# TrollAutoClicker — 巨魔(TrollStore)环境可用的 iOS 悬浮连点器
#
# 不依赖 Substrate / Substitute：入口是 AutoTap.m 中的 constructor。
# 编译产物是 dylib，make package 会把 dylib 打进 .deb。
# 用 TrollFools 把 dylib（或新版 TrollFools 直接把 deb）注入目标 App 即可生效。

THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TrollAutoClicker

SRC = Source
VENDOR = $(SRC)/Vendor

TrollAutoClicker_FILES = Source/Tweak.xm \
                         $(SRC)/AutoTap.m \
                         $(SRC)/ATSession.m \
                         $(SRC)/ATViews.m \
                         $(VENDOR)/TSPrivateUIKit.m \
                         $(VENDOR)/TSTouchSynthesizer.m \
                         $(VENDOR)/TSTouchLogic.c

TrollAutoClicker_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
TrollAutoClicker_CFLAGS = -fobjc-arc -O2 -Wall -Wno-unused-parameter -Wno-deprecated-declarations \
                          -I$(VENDOR)

# 关键：不链接 Substrate，保证注入 App Store / TrollStore 应用后可直接运行。
TrollAutoClicker_USE_SUBSTRATE = 0

include $(THEOS_MAKE_PATH)/tweak.mk
