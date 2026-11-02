# Changelog

## 1.0.2 — 2026-11-02

Consolidates the UI, appearance, background transparency, idle motion, and credential-flow changes already committed through d10dddb. No new application behavior is introduced here beyond release versioning and excluding the personal built-in token from release bundles.

- One VERSION file controls the app version and release output directory; bundle build 3.
- Release builds omit Resources/builtin-token.txt, including stale copies. Personal debug builds retain the existing local-only behavior.
- Historical 1.0.1 archives and diagnostic evidence are preserved as a legacy backup release asset before local duplicate cleanup.
- Native basic checks and release build/signature verification are recorded separately; no claim of live server or long-duration validation.

## 1.0.1 — historical builds

Multiple different binaries used this version. The imported source baseline is commit 799bfd3. Historical artifacts retain their original names and checksums in the legacy backup; they must not be confused with current source.
