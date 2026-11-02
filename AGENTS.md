# Local Lab working conventions

- UI authority: `docs/design/motion.md` and the existing Aurora, AppearanceStore and Motion components. Prefer existing conventions over external redesigns. New effects respect Reduce Motion and do not add idle polling.
- No background AI requests. The user explicitly sends the current file. Review-only must never reach an edit/apply path; applying suggestions checks document identity and source snapshot.
- Secrets live in Application Support or ignored personal resources. Never commit/upload API keys, builtin-token.txt, credentials or .local-signing. Release builds use a resource allowlist and omit the personal built-in token.
- `VERSION` (SemVer) and `BUILD_NUMBER` control packaging. Feature branches use `feature/<name>`; fixes use `fix/<name>`. Use PRs and passing macOS checks before main.
- Verify with `script/test.sh`, `script/test_ai.sh` and a release build. AI tests use only a synthetic key and loopback fixture. UI fixtures belong in Tests/Support, never in production Sources.
- Publish tags `vX.Y.Z`; assets use `LocalLab-X.Y.Z-macOS-arm64.zip`, `release-manifest.json`, `SHA256SUMS`. Package only clean committed source; never move an existing published tag.
