#!/bin/bash
# 编译：
#  1) WebShell        — 独立 ObjC 可执行文件（替换主程序用，已验证仍闪）
#  2) WebShell.dylib  — 注入到游戏 mt3（保留能开的主程序，覆盖 WebView）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CACHE="$(cd "$ROOT/.." && pwd)/cache"
mkdir -p "$CACHE"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MIN="${IPHONEOS_DEPLOYMENT_TARGET:-12.0}"

echo "SDK=$SDK MIN=$MIN"

xcrun -sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min="$MIN" \
  -fobjc-arc -O2 \
  -framework UIKit -framework WebKit -framework Foundation \
  -o "$CACHE/WebShell" \
  "$ROOT/main.m"
codesign --remove-signature "$CACHE/WebShell" 2>/dev/null || true

xcrun -sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min="$MIN" \
  -fobjc-arc -O2 -dynamiclib \
  -install_name "@executable_path/WebShell.dylib" \
  -framework UIKit -framework WebKit -framework Foundation \
  -o "$CACHE/WebShell.dylib" \
  "$ROOT/WebShellDylib.m"
codesign --remove-signature "$CACHE/WebShell.dylib" 2>/dev/null || true

file "$CACHE/WebShell" "$CACHE/WebShell.dylib"
otool -L "$CACHE/WebShell.dylib" | head -n 20
ls -la "$CACHE/WebShell" "$CACHE/WebShell.dylib"
echo "完成"
