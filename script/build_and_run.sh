#!/bin/bash
set -euo pipefail
MODE="${1:-run}"
CONFIGURATION=debug
if [[ "$MODE" == "--release" ]]; then CONFIGURATION=release; fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_NAME=LocalLab
BUNDLE_ID=local.edward.LocalLab
VERSION="$(cat "$ROOT_DIR/VERSION")"
BUILD_NUMBER="$(cat "$ROOT_DIR/BUILD_NUMBER")"
APP_BUNDLE="$ROOT_DIR/dist/debug/Local Lab.app"
if [[ "$MODE" == "--release" ]]; then APP_BUNDLE="$ROOT_DIR/dist/release/Local Lab.app"; fi
# Do not force-kill a running session; the app owns remote resources.
if pgrep -x "$APP_NAME" >/dev/null; then
  echo 'Local Lab is running. Quit it normally before rebuilding so its remote kernel can be cleaned up.' >&2
  exit 1
fi
"$ROOT_DIR/script/swift.sh" build --configuration "$CONFIGURATION" --scratch-path "$ROOT_DIR/.build"
BUILD_BINARY="$("$ROOT_DIR/script/swift.sh" build --configuration "$CONFIGURATION" --scratch-path "$ROOT_DIR/.build" --show-bin-path)/$APP_NAME"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
xcrun clang -O2 -Wall -Wextra "$ROOT_DIR/Support/ShellBridge.c" -o "$ROOT_DIR/.build/LocalLabShellBridge"
cp "$ROOT_DIR/.build/LocalLabShellBridge" "$APP_BUNDLE/Contents/MacOS/LocalLabShellBridge"
# Release artifacts must not carry the personal credential.
for name in AppIcon.png AppIcon.icns marked.js purify.js markdown.css marked-LICENSE DOMPurify-LICENSE python-3.10.12.tar.gz; do
  cp "$ROOT_DIR/Resources/$name" "$APP_BUNDLE/Contents/Resources/$name"
done
rm -f "$APP_BUNDLE/Contents/Resources/builtin-token.txt"
if [[ "$MODE" != "--release" && -f "$ROOT_DIR/Resources/builtin-token.txt" ]]; then
  cp "$ROOT_DIR/Resources/builtin-token.txt" "$APP_BUNDLE/Contents/Resources/builtin-token.txt"
fi
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>Local Lab</string>
<key>CFBundleDisplayName</key><string>Local Lab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 "$ROOT_DIR/script/setup_signing.py"
SIGNING_DIR="$ROOT_DIR/.local-signing"
CERTIFICATE_HASH="$(/usr/bin/openssl x509 -in "$SIGNING_DIR/cert.pem" -noout -fingerprint -sha1 | /usr/bin/sed 's/.*=//;s/://g')"
codesign --force --keychain "$SIGNING_DIR/local-lab.keychain-db" --sign "$CERTIFICATE_HASH" --identifier local.edward.LocalLab.shell "$APP_BUNDLE/Contents/MacOS/LocalLabShellBridge"
codesign --force --keychain "$SIGNING_DIR/local-lab.keychain-db" --sign "$CERTIFICATE_HASH" \
  --requirements "=designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$CERTIFICATE_HASH\"" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --build-only|--release) ;;
  --verify|verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|logs|--telemetry|telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "LocalLab"' ;;
  *) echo 'Usage: build_and_run.sh [--build-only|--release|--verify|--debug|--logs|--telemetry]' >&2; exit 2 ;;
esac
