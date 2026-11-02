#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_LIB="$(xcode-select -p)/usr/lib/swift/pm"
PUBLIC="$SDK_LIB/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface"
PRIVATE="$SDK_LIB/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface"
# Some CLT installations retain a 2024 private interface beside the current runtime.
# Use an isolated copy of the vendor's current public interface; never edit the SDK.
if test -f "$PRIVATE" && grep -q 'swiftLanguageModes' "$PUBLIC" && ! grep -q 'swiftLanguageModes' "$PRIVATE"; then
    LOCAL_LIB="$ROOT_DIR/.build/manifest-toolchain"
    mkdir -p "$LOCAL_LIB"
    if ! test -d "$LOCAL_LIB/ManifestAPI"; then
        cp -R "$SDK_LIB/ManifestAPI" "$LOCAL_LIB/ManifestAPI"
        for arch in arm64 x86_64; do
            cp "$LOCAL_LIB/ManifestAPI/PackageDescription.swiftmodule/$arch-apple-macos.swiftinterface" "$LOCAL_LIB/ManifestAPI/PackageDescription.swiftmodule/$arch-apple-macos.private.swiftinterface"
        done
    fi
    export SWIFTPM_CUSTOM_LIBS_DIR="$LOCAL_LIB"
fi
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swift-cache"
exec /usr/bin/swift "$@"
