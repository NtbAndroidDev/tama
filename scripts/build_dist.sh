#!/bin/bash
# Builds a universal (arm64 + x86_64) Tama.app, signs it ad-hoc and zips it
# for hand-off to a tester. Ad-hoc (not "Tama Local Signing") on purpose:
# the local identity is self-signed and isn't trusted on anyone else's Mac.
set -e

APP_NAME="dist/Tama.app"
BUILD_DIR=".build/apple/Products/Release"

echo "✨ Building Tama (universal: arm64 + x86_64)..."
swift build -c release --arch arm64 --arch x86_64

echo "📦 Packaging $APP_NAME..."
rm -rf dist && mkdir -p "$APP_NAME/Contents/MacOS" "$APP_NAME/Contents/Resources" "$APP_NAME/Contents/Frameworks"

cp "$BUILD_DIR/Tama" "$APP_NAME/Contents/MacOS/Tama"
chmod +x "$APP_NAME/Contents/MacOS/Tama"
cp "$BUILD_DIR/libTamaMediaRemoteAdapter.dylib" "$APP_NAME/Contents/Frameworks/"
cp Info.plist "$APP_NAME/Contents/Info.plist"
[ -f CHANGELOG.md ] && cp CHANGELOG.md "$APP_NAME/Contents/Resources/CHANGELOG.md"

if [ -d "Resources/Integrations/Alfred" ]; then
    scripts/build_alfred_workflow.sh
    cp "Resources/Integrations/Tama.alfredworkflow" "$APP_NAME/Contents/Resources/Tama.alfredworkflow"
fi

if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$APP_NAME/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_NAME/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_NAME/Contents/Info.plist" 2>/dev/null || true
fi

echo "🔏 Code-signing ad-hoc..."
codesign --force --sign - "$APP_NAME/Contents/Frameworks/libTamaMediaRemoteAdapter.dylib"
codesign --force --sign - "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"

# ditto, not zip: keeps symlinks, exec bits and the code signature intact.
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
ZIP="dist/Tama-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME" "$ZIP"

echo "✅ $ZIP"
lipo -archs "$APP_NAME/Contents/MacOS/Tama"
du -h "$ZIP"
