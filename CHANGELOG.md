# 1.1.5

- 使用用户确认的蓝紫玻璃学者角色图标。

- 修复学校 Jupyter 服务拒绝 Notebook format 参数造成 HTTP 400 的兼容问题。

# Changelog

## 1.1.4 — 2026-11-03

- Open remote Notebook files inside the App rather than launching a browser.
- Read Notebook JSON through the Contents API and passively render Markdown, code, saved text/error outputs and bounded PNG images. Notebook previews are read-only; text-style writes are rejected.
- Remove confirmed missing remote files from sidebar caches while preserving unsaved local copies.
- Add Notebook preview, in-app selection and readonly regression checks, plus isolated Jupyter integration checks in CI.

## 1.1.3 — 2026-11-03

- Use one adaptive accent selection fill for bottom tabs and Markdown controls, improving dark-mode contrast.
- Expose Markdown preview/edit/split modes as real accessible buttons with Option-Command-1/2/3 shortcuts.
- Keep Markdown header chips on one line, move mode controls to a separate row, and let split panes fit compact editor widths.
- Adapt Markdown typography and padding in narrow preview panes to prevent clipped headings.

## 1.1.2 — 2026-11-02

- Preserve native fullscreen hover controls while keeping workspace actions inside the content area; use compact native chrome.
- Unify content frost and navigation glass, improve light-mode status contrast, add a readable fullscreen document-title capsule and remove nested button fills.
- Bound native long titles to prevent status overlap; retain terminal leading padding and horizontal position across resize/fullscreen transitions.
- Expand isolated UI fixtures for light/dark, compact windows, long Unicode names, code wrapping, Markdown and output rendering; bundle the real terminal helper.

## 1.1.1 — 2026-11-02

- Restore the transparent native titlebar and status capsules across full-screen transitions using a small window lifecycle bridge. Full-screen style masks are never rewritten.
- Remove the rectangular workspace scrim and double card dimming with custom backgrounds; dimming now stays inside rounded content cards, preserving configured transparency.
- Confirmed full-screen entry/exit, native toolbar action, visible code and background continuity in an isolated window using the existing background image.

## 1.1.0 — 2026-11-02

- Live titlebar clock, battery/charging/network state and single-row API model/token/average-rate metrics; launch accounting handles unknown/cancelled usage.
- Rounded sidebar and header rows, native-sized toggle, smooth retained-list transitions, and viewport-tracking code editor.

- Add DeepSeek-compatible AI code review with persistent editable persona presets, optional per-request instructions and separate review-only/edit modes.
- Store endpoint-scoped API credentials in a private local directory, without repeated Keychain prompts or embedding keys in the app.
- Preview proposed changes before applying; reject stale/changed documents and offer guarded undo. Applying never automatically executes code or saves to the remote server.
- Reuse Aurora cards, accents and existing motion conventions; no background AI polling.
- Add native checks, real URLSession loopback integration tests and an isolated native UI fixture.
- Standardize feature branches, PR checks, VERSION/BUILD_NUMBER, dist outputs and reproducible credential-free release packaging.

## 1.0.2 — 2026-11-02

Consolidates the UI, appearance, background transparency, idle motion, and credential-flow changes already committed through d10dddb. No new application behavior is introduced here beyond release versioning and excluding the personal built-in token from release bundles.

- One VERSION file controls the app version and release output directory; bundle build 3.
- Release builds omit Resources/builtin-token.txt, including stale copies. Personal debug builds retain the existing local-only behavior.
- Historical 1.0.1 archives and diagnostic evidence are preserved as a legacy backup release asset before local duplicate cleanup.
- Native basic checks and release build/signature verification are recorded separately; no claim of live server or long-duration validation.

## 1.0.1 — historical builds

Multiple different binaries used this version. The imported source baseline is commit 799bfd3. Historical artifacts retain their original names and checksums in the legacy backup; they must not be confused with current source.
