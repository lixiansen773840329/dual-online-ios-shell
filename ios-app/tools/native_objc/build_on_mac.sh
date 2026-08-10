#!/bin/bash
# 在 Mac 上编译非 Swift 的 ObjC WebView 壳（arm64），供 Windows 打包注入。
# 用法：
#   cd ios-app/tools/native_objc
#   chmod +x build_on_mac.sh
#   ./build_on_mac.sh
# 产物：../cache/WebShell  （复制到 Windows 同路径后重新 python build_ipa.py）

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CACHE="$(cd "$ROOT/.." && pwd)/cache"
mkdir -p "$CACHE"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MIN="${IPHONEOS_DEPLOYMENT_TARGET:-13.0}"
OUT="$CACHE/WebShell"

echo "SDK=$SDK"
echo "编译 ObjC WebShell -> $OUT"
xcrun -sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min="$MIN" \
  -fobjc-arc \
  -O2 \
  -framework UIKit \
  -framework WebKit \
  -framework Foundation \
  -o "$OUT" \
  "$ROOT/main.m"

# 去掉 ad-hoc 以外的本地签名痕迹，交给分发平台重签
codesign --remove-signature "$OUT" 2>/dev/null || true
ls -la "$OUT"
file "$OUT"
echo "完成。把 $OUT 拷到 Windows 的 ios-app/tools/cache/WebShell 后执行 build_ipa.py"
