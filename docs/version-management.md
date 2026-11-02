# Repository and release conventions

Canonical repository: https://github.com/XiangyuanZhang/local-lab (private).

## Source and workflow

- `main` is the deliverable line. Features use `feature/<short-name>`, fixes `fix/<short-name>`; changes go through a PR with concrete behavior and verification evidence.
- Required working gates are the `macOS checks` workflow: release compilation, existing native workspace checks, AI review checks against a localhost fixture and version metadata validation. CI has read-only repository permissions and no provider or signing credentials.
- `AGENTS.md` records implementation invariants; `docs/design/motion.md` is the established UI authority.
- `VERSION` contains SemVer `major.minor.patch`; `BUILD_NUMBER` contains a monotonically increasing integer. New features increment minor; fixes increment patch; incompatible changes increment major.
- Source files use feature/type names, scripts use snake_case, branch and doc names use lowercase hyphenated names. Versions are not encoded into source directory names.

## Build outputs and releases

- `.build/`: reproducible compiler/test state. `dist/debug/Local Lab.app`: personal development build. `dist/release/Local Lab.app`: credential-free optimized bundle.
- Run `python3 script/package_release.py` from clean committed source on Apple Silicon. It builds, signs, validates version/resources, creates and validates the ZIP, then emits `dist/X.Y.Z/`:
  - `LocalLab-X.Y.Z-macOS-arm64.zip`
  - `release-manifest.json` (commit, version/build, SHA-256, platform, signing/distribution limits)
  - `SHA256SUMS` (ZIP and manifest checksums)
- Publish immutable tag `vX.Y.Z` from verified main. The GitHub release title is `Local Lab X.Y.Z`; attach exactly the above assets. GitHub supplies source archives from the tag; do not commit generated App/ZIP artifacts to Git.
- Release notes say what was checked and what was not. Never move an already published tag to hide a fix; publish the next version instead.
- Local fixed-certificate signing is retained, not Developer ID notarization. Private signing material remains only in ignored `.local-signing/`.
- Debug builds can retain the pre-existing ignored Jupyter built-in token for personal use; release resources use an allowlist and always omit it. AI settings/keys live outside the repo and are never bundled.
- Keep one canonical local checkout, latest installed app, and latest release assets. Delete old copies only after source push and remote asset SHA-256 verification. User data, credentials and signing identity are not disposable build caches.

## History

- v1.0.1 preserves imported source baseline 799bfd3; the corresponding legacy backup release stores historical binaries and diagnostic evidence. Multiple different historical binaries shared version 1.0.1.
- v1.0.2 / build 3 consolidated the pre-existing appearance/background changes and credential-free packaging.
- v1.1.0 / build 4 adds the AI reviewer and this standardized workflow. Earlier overview/status documents are historical snapshots, not a statement of current feature completeness.
