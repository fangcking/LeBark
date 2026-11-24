# WeChatJumpBlocker — 巨魔(TrollStore)环境可用的 iOS dylib 插件
#
# 功能：拦截 QQ音乐内"跳转微信/分享到微信"，让 QQ音乐认为跳转成功，实际不打开微信。
# 不依赖 Substrate：用 Objective-C runtime method_exchangeImplementations 做 hook。
# 产出 dylib，make package 打成 .deb，用 TrollFools 注入 QQ音乐即生效。

THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeChatJumpBlocker

SRC = Source

WeChatJumpBlocker_FILES = $(SRC)/Tweak.m \
                          $(SRC)/WJBlocker.m \
                          $(SRC)/WJOverlay.m

WeChatJumpBlocker_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
WeChatJumpBlocker_CFLAGS = -fobjc-arc -O2 -Wall -Wno-unused-parameter -Wno-deprecated-declarations

# 不链接 Substrate，保证注入 App Store / TrollStore 应用后可直接运行。
WeChatJumpBlocker_USE_SUBSTRATE = 0

include $(THEOS_MAKE_PATH)/tweak.mk
