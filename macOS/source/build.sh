#!/bin/bash
# Builds DaySpindle.app from the sources in this folder with the Swift compiler in Xcode or the
# Xcode Command Line Tools (no other dependencies), and puts it in the folder above as
#   ../DaySpindle-2.1-macOS.zip
# ready to upload to GitHub. Nothing else is left behind.
set -euo pipefail

cd "$(dirname "$0")"
SRC="$(pwd -P)"
TOP="$(cd .. && pwd -P)"
BUNDLE_ID="org.dayspindle.DaySpindle"
VERSION="2.1"
MIN_MACOS="14.0"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
APP="$BUILD/DaySpindle.app"
ZIP="$TOP/DaySpindle-$VERSION-macOS.zip"

# One app for both Apple silicon and Intel Macs.
for ARCH in arm64 x86_64; do
  echo "==> Compiling ($ARCH, macOS $MIN_MACOS+)"
  xcrun swiftc -O -swift-version 5 \
    -target "$ARCH-apple-macos$MIN_MACOS" -sdk "$SDK" \
    -module-name DaySpindle \
    Sources/*.swift -o "$BUILD/DaySpindle-$ARCH"
done
lipo -create "$BUILD/DaySpindle-arm64" "$BUILD/DaySpindle-x86_64" -output "$BUILD/DaySpindle"

# Light icon (AppIcon, used by Finder) and dark icon (AppIcon-Dark, shown in the Dock while the
# app is in its dark appearance).
make_icon() { # make_icon <name> <light|dark>
  local name="$1" style="$2"
  echo "==> Rendering $style icon"
  xcrun swift -sdk "$SDK" Scripts/make_icon.swift "$BUILD/$name-1024.png" "$style" >/dev/null
  local iconset="$BUILD/$name.iconset"
  mkdir -p "$iconset"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$BUILD/$name-1024.png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" "$BUILD/$name-1024.png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$BUILD/$name.icns"
}
make_icon AppIcon light
make_icon AppIcon-Dark dark

echo "==> Assembling DaySpindle.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/DaySpindle" "$APP/Contents/MacOS/DaySpindle"
cp "$BUILD/AppIcon.icns" "$BUILD/AppIcon-Dark.icns" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>DaySpindle</string>
  <key>CFBundleExecutable</key><string>DaySpindle</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>DaySpindle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 Ruichen Li. MIT License.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS treats the bundle as one sealed app.
codesign --force --sign - "$APP"

echo "==> Zipping"
rm -f "$ZIP"
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
echo "==> Built $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
