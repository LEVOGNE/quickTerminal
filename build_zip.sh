#!/bin/bash
# Build quickTerminal.zip for GitHub Releases
# NOTE: Keep VERSION in sync with kAppVersion in quickTerminal.swift
set -e
cd "$(dirname "$0")"

VERSION="1.3.0"
ZIP_NAME="quickTERMINAL_v${VERSION}.zip"

echo "=== Building ${ZIP_NAME} (v${VERSION}) ==="

# ─── Step 1: Build .app bundle ───
echo "[1/2] Building .app bundle..."
bash build_app.sh

# ─── Step 2: Package zip ───
echo "[2/2] Packaging ${ZIP_NAME}..."
rm -f "$ZIP_NAME"
ditto -ck --sequesterRsrc --keepParent quickTerminal.app "$ZIP_NAME"

# Add documentation files into the zip
# (ditto creates a clean zip, we use /usr/bin/zip to append extra files)
/usr/bin/zip -j "$ZIP_NAME" install.sh FIRST_READ.txt LICENSE README.md

ZIP_SIZE=$(du -sh "$ZIP_NAME" | cut -f1)
echo ""
echo "    ${ZIP_NAME}  →  ${ZIP_SIZE}"
echo "    Contents:"
echo "      quickTerminal.app"
echo "      install.sh"
echo "      FIRST_READ.txt"
echo "      LICENSE"
echo "      README.md"
echo ""
echo "    Ready for GitHub Release v${VERSION}"
echo "    Upload: gh release create v${VERSION} ${ZIP_NAME} --title \"v${VERSION}\""
