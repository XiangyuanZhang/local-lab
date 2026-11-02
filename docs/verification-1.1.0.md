# 1.1.0 verification record

2026-11-02. Native macOS SwiftUI App, Apple Silicon. Evidence from the current feature worktree, not copied from older reports.

## Completed local checks

- Debug application compilation passed.
- Existing native workspace assertion suite passed (7 groups: heartbeat completion races, unauthenticated execution, local-failure gate, cleanup state, retry state, draft persistence and token reuse/removal).
- `script/test_ai.sh` passed 10 groups: persona/mode/model/key persistence and POSIX permissions; endpoint isolation/normalization/removal; persona validation; current-file request contract/input bounds; strict responses and review-only edit stripping; apply/undo/stale/busy gates; automatic persona/key use without background requests; cancellation and missing-key state; bounded diff; actual URLSession loopback HTTP integration.
- Actual localhost HTTP checks cover review/edit outputs, Authorization and body contract, 401/429/500, redirect refusal without credential forwarding, truncated/empty/invalid responses, response bounds and cancellation. Only synthetic `test-ai-only` is used.
- Native UI fixture: opened right inspector, created 課程助教 persona and custom prompt, entered synthetic key once, saved, reviewed unchanged source, switched to edit, generated preview, displayed complete proposed code, explicitly applied, verified editor changed, then restored original source. No school connection or real drafts are loaded by the fixture.
- Native sheet and inspector visually checked in the user's dark appearance. Aurora accents/cards are reused. A discovered centered diff layout was corrected to top-leading; final rerender/restart confirmation is recorded below before publication.

## Publication gates

Final release compile/signature, restart/reuse UI confirmation, GitHub CI result and tag/asset validation are completed before publishing. Their authoritative URLs and local observation details will be recorded here after completion.

## Scope limits

No paid live DeepSeek call, live school-server regression or 1–2 hour soak was performed. The HTTP fixture checks the documented API contract and application behavior; it does not measure real model quality or validate a personal account's balance/key. Enter a real DeepSeek key once in the installed App for real use. Reduce Motion is respected by new view modifiers in source; no global macOS accessibility preference was changed during testing.
