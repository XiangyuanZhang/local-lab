#!/usr/bin/env python3
"""Repeatable local release packaging. Never reads or embeds runtime API credentials."""
import argparse
import hashlib
import json
import platform
import plistlib
import re
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--check-version', action='store_true')
parser.add_argument('--allow-dirty', action='store_true', help='Local packaging verification only; never publish this artifact')
args = parser.parse_args()
version = (root / 'VERSION').read_text().strip()
build = (root / 'BUILD_NUMBER').read_text().strip()
assert re.fullmatch(r'\d+\.\d+\.\d+', version), 'VERSION must be a SemVer release'
assert build.isdigit() and int(build) > 0, 'BUILD_NUMBER must be a positive integer'
if args.check_version:
    print(f'{version} ({build})')
    raise SystemExit(0)
assert platform.machine() == 'arm64', 'The bundled Python runtime requires an Apple Silicon release build'
status = subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip()
assert not status or args.allow_dirty, 'Commit and verify the release source before packaging'
subprocess.run([str(root / 'script/build_and_run.sh'), '--release'], cwd=root, check=True)
app = root / 'dist/release/Local Lab.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == version and info['CFBundleVersion'] == build
for path in app.rglob('*'):
    assert path.name not in {'builtin-token.txt', 'credential.txt', 'api-keys.json'}, 'Private credential resource in release'
    assert '.local-signing' not in path.parts, 'Signing key in release'
output = root / 'dist' / version
output.mkdir(parents=True, exist_ok=True)
archive = output / f'LocalLab-{version}-macOS-arm64.zip'
subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
with zipfile.ZipFile(archive) as check:
    assert check.testzip() is None, 'Corrupt ZIP'
    assert not any(n.endswith(('builtin-token.txt', 'credential.txt', 'api-keys.json')) for n in check.namelist()), 'Credential in ZIP'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
manifest = output / 'release-manifest.json'
manifest.write_text(json.dumps({'version': version, 'build': int(build), 'platform': 'macOS 14+ arm64', 'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(), 'dirty': bool(status), 'artifact': archive.name, 'sha256': sha(archive), 'credentials_included': False, 'notarized': False}, indent=2) + '\n')
(output / 'SHA256SUMS').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in (archive, manifest)))
print(output)
