#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "Building quickTerminal..."
swiftc -O quickTerminal.swift -o quickTerminal -framework Cocoa -framework Carbon -framework AVKit \
  -Xlinker -sectcreate -Xlinker __FONTS -Xlinker __jbmono -Xlinker _JetBrainsMono-LightItalic-terminal.ttf \
  -Xlinker -sectcreate -Xlinker __FONTS -Xlinker __monocraft -Xlinker _Monocraft-terminal.ttf \
  -Xlinker -sectcreate -Xlinker __DATA -Xlinker __readme -Xlinker README.md \
  -Xlinker -sectcreate -Xlinker __DATA -Xlinker __commands -Xlinker COMMANDS.md
echo "Done! Run with: ./quickTerminal"
