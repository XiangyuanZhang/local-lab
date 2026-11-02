# Versions and backup policy

Updated 2026-11-02. Canonical repository: https://github.com/XiangyuanZhang/local-lab (private).

- Current source: main, tagged v1.0.2 after verification and push.
- Current app version: 1.0.2, bundle build 3. VERSION is authoritative.
- Imported historical source: 799bfd3; tag v1.0.1 preserves that baseline, not a claim that every historical binary matches it.
- Historical local binaries, source ZIP, reports and diagnostics not already represented by source are uploaded as a legacy backup ZIP on the v1.0.1 release. SHA-256 checksums inside and alongside the archive permit verification.
- The newer 1.0.1 personal app contains an ignored credential resource; its source is backed by Git, but its credential-bearing binary must not be uploaded. The personal credential remains local for rebuilding the personal app.
- Latest distributable ZIP is attached to the v1.0.2 GitHub release, without builtin-token.txt, runtime credentials or private signing material.
- Keep one source checkout, the latest installed /Applications/Local Lab.app, and latest 1.0.2 release ZIP/checksums locally. Remove duplicate ZIPs, stale bundles and old release directories only after remote backup verification.
- Preserve .local-signing, Resources/builtin-token.txt, Application Support data and stored credentials. They are not old release backups and are never uploaded.
- .build is reproducible and may be removed after verification to save disk space.

The previously paused/unpublished notes in older documents are historical. Newer code, CHANGELOG and tests take precedence. This housekeeping does not certify live connectivity or long-duration stability.
