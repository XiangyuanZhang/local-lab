# 1.1.0 verification record

2026-11-02. Native macOS SwiftUI App, Apple Silicon. Evidence from the current feature worktree, not copied from older reports.

## Completed local checks

- Debug application compilation passed.
- Existing native workspace assertion suite passed (7 groups: heartbeat completion races, unauthenticated execution, local-failure gate, cleanup state, retry state, draft persistence and token reuse/removal).
- `script/test_ai.sh` passed 10 groups: persona/mode/model/key persistence and POSIX permissions; endpoint isolation/normalization/removal; persona validation; current-file request contract/input bounds; strict responses and review-only edit stripping; apply/undo/stale/busy gates; automatic persona/key use without background requests; cancellation and missing-key state; bounded diff; actual URLSession loopback HTTP integration.
- Actual localhost HTTP checks cover review/edit outputs, Authorization and body contract, 401/429/500, redirect refusal without credential forwarding, truncated/empty/invalid responses, response bounds and cancellation. Only synthetic `test-ai-only` is used.
- Native UI fixture: opened right inspector, created 課程助教 persona and custom prompt, entered synthetic key once, saved, reviewed unchanged source, switched to edit, generated preview, displayed complete proposed code, explicitly applied, verified editor changed, then restored original source. No school connection or real drafts are loaded by the fixture.
- Native sheet and inspector visually checked in the user's dark appearance. Aurora accents/cards are reused. The diff now starts at the top-left; both the full-source and changed-block views were checked after restart.
- Restarted the isolated App: selected persona, edit mode and saved synthetic key were reused; generating a new result required no key entry.
- Edited the source after receiving an AI proposal: the preview displayed a stale-source warning and disabled Apply, preserving the newer edit.
- Inspector uses a SwiftUI horizontal container inside the existing workspace split: no native inspector divider extends into the titlebar; slide/fade transition respects Reduce Motion. The user confirmed the divider and animation fixes. At the user's final request, editor height/titlebar spacing and native draggable workspace splits were restored.

- Static titlebar status preview compiled and visually checked above the restored editor: 10:24, Wi-Fi icon and 78% battery. It follows the sidebar width, shares the toolbar centre line, ignores input, and has no clock, battery or network observer. Values are explicitly marked as examples for accessibility. Both status capsules are 36 pt high to match the native toolbar buttons. The API capsule lists model, per-request tokens, launch-total tokens and tokens/second on one row; all values remain static examples. Sidebar hide/show, widths 180/240/280, inspector open/close and window zoom were visually exercised.

## Publication gates

- Optimized release compilation and strict deep signature validation passed after the final inspector layout fix. Packaging verified bundle version 1.1.0 / build 4, clean committed source, ZIP integrity, and absence of credential resources.
- Restart/reuse and stale-source UI checks are recorded above. The final restored layout was compiled, relaunched and visually checked.
- CI evidence is attached to [PR #1](https://github.com/XiangyuanZhang/local-lab/pull/1); release publication requires its final checks to pass. The initial full feature check passed in [run 41504061863](https://github.com/XiangyuanZhang/local-lab/actions/runs/41504061863).
- The published [v1.1.0 release](https://github.com/XiangyuanZhang/local-lab/releases/tag/v1.1.0) supplies the authoritative source commit and artifact SHA-256 through release-manifest.json and SHA256SUMS. Uploaded asset digests are compared before delivery.

## Scope limits

No paid live DeepSeek call, live school-server regression or 1–2 hour soak was performed. The HTTP fixture checks the documented API contract and application behavior; it does not measure real model quality or validate a personal account's balance/key. Enter a real DeepSeek key once in the installed App for real use. Reduce Motion is respected by new view modifiers in source; no global macOS accessibility preference was changed during testing.
