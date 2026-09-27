#!/bin/bash
set -e

APP_NAME="Tama.app"
BUNDLE_ID="app.tama.macos"
BUILD_DIR=".build/release"
PLIST_FILE="Info.plist"

echo "✨ Building Tama for Mac in Release mode..."
swift build -c release

echo "📦 Packaging $APP_NAME bundle..."
rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/Tama" "$APP_NAME/Contents/MacOS/Tama"
chmod +x "$APP_NAME/Contents/MacOS/Tama"

# Now Playing adapter, loaded by /usr/bin/perl (see MediaRemoteAdapterProcess.swift)
mkdir -p "$APP_NAME/Contents/Frameworks"
cp "$BUILD_DIR/libTamaMediaRemoteAdapter.dylib" "$APP_NAME/Contents/Frameworks/"

# Copy Info.plist
if [ -f "$PLIST_FILE" ]; then
    cp "$PLIST_FILE" "$APP_NAME/Contents/Info.plist"
fi

# The changelog shown in Settings › About
if [ -f "CHANGELOG.md" ]; then
    cp "CHANGELOG.md" "$APP_NAME/Contents/Resources/CHANGELOG.md"
fi

# The Alfred workflow offered in Settings › General › Integrations
if [ -d "Resources/Integrations/Alfred" ]; then
    scripts/build_alfred_workflow.sh
    cp "Resources/Integrations/Tama.alfredworkflow" "$APP_NAME/Contents/Resources/Tama.alfredworkflow"
fi

# Copy AppIcon if available
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_NAME/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_NAME/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_NAME/Contents/Info.plist" 2>/dev/null || true
fi

# Sign with the stable local identity when it exists (scripts/setup_signing.sh):
# ad-hoc signatures change every build, and macOS then drops the permission grants.
SIGN_IDENTITY="Tama Local Signing"
# Before the rename the identity was "Droppy Local Signing". Fall back to it
# so builds keep a stable signature until scripts/setup_signing.sh is re-run.
if ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1 \
   && security find-certificate -c "Droppy Local Signing" >/dev/null 2>&1; then
    SIGN_IDENTITY="Droppy Local Signing"
fi
echo "🔏 Code-signing $APP_NAME..."
sign_adhoc() {
    codesign --force --sign - "$APP_NAME/Contents/Frameworks/libTamaMediaRemoteAdapter.dylib"
    codesign --force --sign - "$APP_NAME"
}
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    # The key can be locked away from codesign (errSecInternalComponent) when
    # the build runs outside a GUI session or before "Always Allow"; still
    # finish the build, ad-hoc, and say how to fix it.
    if ! { codesign --force --sign "$SIGN_IDENTITY" "$APP_NAME/Contents/Frameworks/libTamaMediaRemoteAdapter.dylib" \
           && codesign --force --sign "$SIGN_IDENTITY" "$APP_NAME"; }; then
        echo "⚠️  Couldn't use '$SIGN_IDENTITY' — signing ad-hoc instead (permissions will need granting again)."
        echo "   Run the build once from Terminal and choose \"Always Allow\" for codesign, or:"
        echo "   security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <login password> ~/Library/Keychains/login.keychain-db"
        sign_adhoc
    fi
else
    echo "   (ad-hoc — run scripts/setup_signing.sh once so permissions survive rebuilds)"
    sign_adhoc
fi

echo "✅ Successfully built $APP_NAME!"

# Optional install to /Applications
if [ "$1" == "--install" ] || [ "$1" == "-i" ]; then
    echo "🚀 Installing to /Applications/Tama.app..."
    pkill -x Tama || true
    rm -rf "/Applications/Tama.app"
    cp -R "$APP_NAME" "/Applications/"
    echo "🎉 Installed! Launching Tama..."
    open "/Applications/Tama.app"
fi
