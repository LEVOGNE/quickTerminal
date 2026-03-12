#!/bin/bash
set -e
cd "$(dirname "$0")"

APP_NAME="quickTerminal"
BUNDLE="${APP_NAME}.app"
ICON_SRC="icon.png"
# NOTE: Keep VERSION in sync with kAppVersion in quickTerminal.swift
VERSION="1.3.0"
BUNDLE_ID="com.l3v0.quickterminal"

echo "=== Building ${APP_NAME}.app ==="

# ─── Step 1: Create .icns from PNG ───
echo "[1/4] Creating app icon..."
ICONSET="${APP_NAME}.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Generate all required icon sizes
sips -z 16 16     "$ICON_SRC" --out "${ICONSET}/icon_16x16.png"      > /dev/null 2>&1
sips -z 32 32     "$ICON_SRC" --out "${ICONSET}/icon_16x16@2x.png"   > /dev/null 2>&1
sips -z 32 32     "$ICON_SRC" --out "${ICONSET}/icon_32x32.png"      > /dev/null 2>&1
sips -z 64 64     "$ICON_SRC" --out "${ICONSET}/icon_32x32@2x.png"   > /dev/null 2>&1
sips -z 128 128   "$ICON_SRC" --out "${ICONSET}/icon_128x128.png"    > /dev/null 2>&1
sips -z 256 256   "$ICON_SRC" --out "${ICONSET}/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 256 256   "$ICON_SRC" --out "${ICONSET}/icon_256x256.png"    > /dev/null 2>&1
sips -z 512 512   "$ICON_SRC" --out "${ICONSET}/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 512 512   "$ICON_SRC" --out "${ICONSET}/icon_512x512.png"    > /dev/null 2>&1
sips -z 1024 1024 "$ICON_SRC" --out "${ICONSET}/icon_512x512@2x.png" > /dev/null 2>&1

iconutil -c icns "$ICONSET" -o AppIcon.icns
rm -rf "$ICONSET"
echo "    AppIcon.icns created"

# ─── Step 2: Compile binary ───
echo "[2/4] Compiling binary..."
swiftc -O quickTerminal.swift -o "${APP_NAME}_bin" \
  -framework Cocoa -framework Carbon \
  -Xlinker -sectcreate -Xlinker __FONTS -Xlinker __jbmono -Xlinker _JetBrainsMono-LightItalic-terminal.ttf \
  -Xlinker -sectcreate -Xlinker __FONTS -Xlinker __monocraft -Xlinker _Monocraft-terminal.ttf \
  -Xlinker -sectcreate -Xlinker __DATA -Xlinker __readme -Xlinker README.md \
  -Xlinker -sectcreate -Xlinker __DATA -Xlinker __commands -Xlinker COMMANDS.md
echo "    Binary compiled"

# ─── Step 3: Assemble .app bundle ───
echo "[3/4] Assembling ${BUNDLE}..."
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

# Binary
mv "${APP_NAME}_bin" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

# Fonts (loaded relative to binary)
cp _FiraCode-Regular-terminal.ttf "${BUNDLE}/Contents/MacOS/"
cp _FiraCode-Bold-terminal.ttf    "${BUNDLE}/Contents/MacOS/"
cp _IosevkaThin-terminal.ttf      "${BUNDLE}/Contents/MacOS/"

# Shell configs (loaded relative to binary)
cp -R shell "${BUNDLE}/Contents/MacOS/shell"
# Remove .zsh_history from bundle
rm -f "${BUNDLE}/Contents/MacOS/shell/.zsh_history"

# Icon
cp AppIcon.icns "${BUNDLE}/Contents/Resources/"

# PkgInfo
echo -n "APPL????" > "${BUNDLE}/Contents/PkgInfo"

# Info.plist
cat > "${BUNDLE}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>quickTERMINAL</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>quickTERMINAL needs accessibility access for the global hotkey.</string>
</dict>
</plist>
PLIST

echo "    Bundle assembled"

# ─── Step 4: Summary ───
echo "[4/4] Done!"
echo ""
TOTAL_SIZE=$(du -sh "$BUNDLE" | cut -f1)
BIN_SIZE=$(ls -lh "${BUNDLE}/Contents/MacOS/${APP_NAME}" | awk '{print $5}')
echo "    ${BUNDLE}  →  ${TOTAL_SIZE} total  (binary: ${BIN_SIZE})"
echo "    Run with:  open ${BUNDLE}"
echo "    Install:   cp -R ${BUNDLE} /Applications/"
