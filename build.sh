#!/bin/zsh
# Buduje Samotnik.app z main.swift
set -e
cd "$(dirname "$0")"
APP=Samotnik.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macos14.0 -o "$APP/Contents/MacOS/Samotnik" Core.swift Texture.swift Data.swift BoardWear.swift Solver.swift main.swift -framework Cocoa -framework SceneKit -framework SpriteKit -framework AVFoundation
cp Resources/wordmark.svg "$APP/Contents/Resources/"
# ikona: generowana z Icon.swift, gdy jej brak albo skrypt ikony jest nowszy
if [ ! -f Resources/AppIcon.icns ] || [ Icon.swift -nt Resources/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset && mkdir -p build
  swift Icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Samotnik</string>
  <key>CFBundleDisplayName</key><string>Samotnik</string>
  <key>CFBundleIdentifier</key><string>pl.marchewka.samotnik</string>
  <key>CFBundleExecutable</key><string>Samotnik</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.puzzle-games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force -s - "$APP" >/dev/null 2>&1 || true
echo "Gotowe: $(pwd)/$APP"
