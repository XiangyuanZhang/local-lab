#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/.build/swift-cache"
ARCH="$(uname -m)"
CORE_SOURCES=( "$ROOT_DIR"/Sources/LocalLab/{Models,Services,Stores,AI}/*.swift )
xcrun swiftc -parse-as-library -swift-version 5 -target "$ARCH-apple-macosx14.0" \
  -module-cache-path "$ROOT_DIR/.build/swift-cache" \
  "${CORE_SOURCES[@]}" "$ROOT_DIR/Tests/AIReviewChecks.swift" -o "$ROOT_DIR/.build/AIReviewChecks"
python3 "$ROOT_DIR/script/run_ai_tests.py" "$ROOT_DIR/.build/AIReviewChecks"
