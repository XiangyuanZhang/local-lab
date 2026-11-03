#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/.build/check-cache"
ARCH="$(uname -m)"
xcrun clang -O2 -Wall -Wextra "$ROOT_DIR/Support/ShellBridge.c" -o "$ROOT_DIR/.build/LocalLabShellBridge"
# CLT-only installations omit XCTest. Compile a native, async assertion harness.
xcrun swiftc -parse-as-library -swift-version 5 -target "$ARCH-apple-macosx14.0" \
  -module-cache-path "$ROOT_DIR/.build/swift-cache" \
  "$ROOT_DIR/Sources/LocalLab/Models/Workspace.swift" \
  "$ROOT_DIR/Sources/LocalLab/Models/RemoteFile.swift" \
  "$ROOT_DIR/Sources/LocalLab/Services/DraftLibrary.swift" \
  "$ROOT_DIR/Sources/LocalLab/Services/TokenVault.swift" \
  "$ROOT_DIR/Sources/LocalLab/Services/BuiltinCredential.swift" \
  "$ROOT_DIR/Sources/LocalLab/Services/LocalPythonRunner.swift" \
  "$ROOT_DIR/Sources/LocalLab/Services/ShellTerminal.swift" \
  "$ROOT_DIR/Sources/LocalLab/Services/MarkdownHTML.swift" \
  "$ROOT_DIR/Sources/LocalLab/Services/NotebookMarkdown.swift" \
  "$ROOT_DIR/Sources/LocalLab/Services/NotebookDocument.swift" \
  "$ROOT_DIR/Tests/MarkdownCheck.swift" \
  "$ROOT_DIR/Sources/LocalLab/Services/BackgroundStore.swift" \
  "$ROOT_DIR/Sources/LocalLab/Views/MarkdownPreview.swift" \
  "$ROOT_DIR/Sources/LocalLab/Services/JupyterClient.swift" \
  "$ROOT_DIR/Sources/LocalLab/Services/AppLiveVerifier.swift" \
  "$ROOT_DIR/Sources/LocalLab/Stores/WorkspaceStore.swift" \
  "$ROOT_DIR/Sources/LocalLab/Stores/RemoteSync.swift" \
  "$ROOT_DIR/Sources/LocalLab/Stores/TerminalStore.swift" \
  "$ROOT_DIR/Tests/Checks.swift" -o "$ROOT_DIR/.build/LocalLabChecks"
"$ROOT_DIR/.build/LocalLabChecks"
