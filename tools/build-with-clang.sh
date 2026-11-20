#!/usr/bin/env bash
# 直接用 clang + Theos iOS SDK 编译 dylib（不需要 Theos/make），供本机无 Theos 时使用。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${1:?usage: build-with-clang.sh <path-to-iPhoneOS.sdk> [clang]}"
CLANG="${2:-clang}"
OUT="$ROOT/packages/TrollAutoClicker.dylib"
mkdir -p "$ROOT/packages"

SRC="$ROOT/Source"
VENDOR="$SRC/Vendor"

"$CLANG" -target arm64-apple-ios14.0 \
  -isysroot "$SDK" \
  -fobjc-arc -fobjc-runtime=ios-14.0 \
  -O2 -Wall -Wno-unused-parameter -Wno-deprecated-declarations \
  -I"$VENDOR" \
  -dynamiclib \
  -o "$OUT" \
  "$SRC/AutoTap.m" "$SRC/ATSession.m" "$SRC/ATViews.m" \
  "$VENDOR/TSPrivateUIKit.m" "$VENDOR/TSTouchSynthesizer.m" "$VENDOR/TSTouchLogic.c" \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
  -Wl,-undefined,dynamic_lookup

echo "built $OUT"
