#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p .build/ui-smoke
python3 - <<'PY'
from pathlib import Path
import plistlib
import shutil
import subprocess
root = Path.cwd()
app = root / '.build/ui-smoke/Local Lab AI Test.app'
binary = app / 'Contents/MacOS/AIReviewSmoke'
binary.parent.mkdir(parents=True, exist_ok=True)
sources = [str(p) for p in (root / 'Sources/LocalLab').rglob('*.swift') if p.name != 'LocalLabApp.swift']
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-target', subprocess.check_output(['uname', '-m'], text=True).strip() + '-apple-macosx14.0', '-module-cache-path', str(root / '.build/swift-cache'), *sources, str(root / 'Tests/Support/AIReviewSmokeApp.swift'), '-o', str(binary)], check=True)
subprocess.run(['xcrun', 'clang', '-O2', '-Wall', '-Wextra', str(root / 'Support/ShellBridge.c'), '-o', str(binary.parent / 'LocalLabShellBridge')], check=True)
resources = app / 'Contents/Resources'
resources.mkdir(parents=True, exist_ok=True)
for p in (root / 'Resources').iterdir():
    if p.is_file() and p.name != 'builtin-token.txt': shutil.copy2(p, resources / p.name)
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'local.edward.LocalLab.AITest', 'CFBundleExecutable': 'AIReviewSmoke', 'CFBundleName': 'Local Lab AI Test', 'CFBundlePackageType': 'APPL', 'LSMinimumSystemVersion': '14.0', 'NSPrincipalClass': 'NSApplication', 'NSHighResolutionCapable': True}))
subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
print(app)
PY
