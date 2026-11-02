#!/bin/bash
set -euo pipefail
[[ "${1:-}" == "--live" ]] || { echo 'Usage: live_ai_check.sh --live (one paid toy-code request using the locally saved DeepSeek key)'; exit 2; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/.build/swift-cache"
ARCH="$(uname -m)"
CORE_SOURCES=( "$ROOT_DIR"/Sources/LocalLab/{Models,Services,Stores,AI}/*.swift )
xcrun swiftc -parse-as-library -swift-version 5 -target "$ARCH-apple-macosx14.0" -module-cache-path "$ROOT_DIR/.build/swift-cache" "${CORE_SOURCES[@]}" "$ROOT_DIR/Tests/Support/AIReviewLiveCheck.swift" -o "$ROOT_DIR/.build/AIReviewLiveCheck"
"$ROOT_DIR/.build/AIReviewLiveCheck" --live
