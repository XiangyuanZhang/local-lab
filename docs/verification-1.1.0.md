# 1.1.0 verification record

2026-11-02. Native macOS SwiftUI App, Apple Silicon. Evidence from the current feature worktree, not copied from older reports.

## Completed local checks

- Debug application compilation passed.
- Existing native workspace assertion suite passed (7 groups: heartbeat completion races, unauthenticated execution, local-failure gate, cleanup state, retry state, draft persistence and token reuse/removal).
- `script/test_ai.sh` passed 12 groups: persona/mode/model/key persistence and POSIX permissions; endpoint isolation/normalization/removal; persona validation; current-file request contract/input bounds; strict responses and review-only edit stripping; apply/undo/stale/busy gates; automatic persona/key use without background requests; cancellation and missing-key state; bounded diff; actual URLSession loopback HTTP integration.
- Actual localhost HTTP checks cover review/edit outputs, Authorization and body contract, 401/429/500, redirect refusal without credential forwarding, truncated/empty/invalid responses, response bounds and cancellation. Only synthetic `test-ai-only` is used.
- Native UI fixture: opened right inspector, created 課程助教 persona and custom prompt, entered synthetic key once, saved, reviewed unchanged source, switched to edit, generated preview, displayed complete proposed code, explicitly applied, verified editor changed, then restored original source. No school connection or real drafts are loaded by the fixture.
- Native sheet and inspector visually checked in the user's dark appearance. Aurora accents/cards are reused. The diff now starts at the top-left; both the full-source and changed-block views were checked after restart.
- Restarted the isolated App: selected persona, edit mode and saved synthetic key were reused; generating a new result required no key entry.
- Edited the source after receiving an AI proposal: the preview displayed a stale-source warning and disabled Apply, preserving the newer edit.
- Inspector uses a SwiftUI horizontal container inside the existing workspace split: no native inspector divider extends into the titlebar; slide/fade transition respects Reduce Motion. The user confirmed the divider and animation fixes. At the user's final request, editor height/titlebar spacing and the native vertical workspace split were restored; subsequent sidebar refinements are recorded below.

- The approved status design now uses real clock, IOKit battery/charging and NWPathMonitor network data. Both capsules are 36 pt high, matching native toolbar buttons. Model, per-request tokens, launch-total tokens and average token consumption rate stay on one row. The UI read 80% / AC attached and local time matching macOS. Two loopback requests displayed per-request 150 and launch totals 150 then 300 with a provider-reported model. Tests cover malformed/negative/missing usage, zero duration, resets, rejected-result accounting and cancellation without double counting.
- Sidebar now uses a stable-width, clipped SwiftUI column for animated hide/show; its divider stays below the titlebar. The toggle reuses native toolbar styling with a square target. Sidebar card/header rows share rounded Aurora styling; headers cannot be selected. A viewport-tracking wrapping editor keeps both minimum document height and scroll origin valid after panel resizing. Final hide/show was visually checked: the complete code remained visible, no horizontal scroller appeared, selected document stayed selected, rounded headers and cards were intact. A short idle observation showed 0.0% CPU; this is not a soak-test result.

## Publication gates

- Optimized release compilation and strict deep signature validation passed after the final inspector layout fix. Packaging verified bundle version 1.1.0 / build 4, clean committed source, ZIP integrity, and absence of credential resources.
- Restart/reuse and stale-source UI checks are recorded above. The final restored layout was compiled, relaunched and visually checked.
- CI evidence is attached to [PR #1](https://github.com/XiangyuanZhang/local-lab/pull/1); release publication requires its final checks to pass. The initial full feature check passed in [run 41504061863](https://github.com/XiangyuanZhang/local-lab/actions/runs/41504061863).
- The published [v1.1.0 release](https://github.com/XiangyuanZhang/local-lab/releases/tag/v1.1.0) supplies the authoritative source commit and artifact SHA-256 through release-manifest.json and SHA256SUMS. Uploaded asset digests are compared before delivery.

## Scope limits

One user-authorized live DeepSeek review of a fixed non-sensitive toy file passed: model deepseek-flash, 379 prompt + 226 completion = 605 total tokens, 2 findings, approximately 2.55 seconds end-to-end (237.5 total tokens/s). The key was saved in the private App credential file, never in source/test outputs or release resources. No live school-server regression or 1–2 hour soak was performed. Synthetic fixture speeds are not model benchmarks. Reduce Motion is respected by new view modifiers in source; no global macOS accessibility preference was changed during testing.
