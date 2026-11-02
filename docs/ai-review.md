# AI code review / AI 審碼

Version 1.1.0. Interface conventions: [design/motion.md](design/motion.md), Aurora palette, cardSurface, PressableStyle and Motion. New transitions respect Reduce Motion; no AI polling or background model calls are introduced.

## Use

- Open the right inspector with the toolbar sparkle button or ⇧⌘R. It works with local drafts and opened remote text files without requiring an active Jupyter kernel.
- Open AI settings from the inspector, AI menu, or Settings → AI 審碼. Default provider is DeepSeek; endpoint and model remain editable. Enter the API Key in the secure field once and save.
- Defaults: 嚴謹審閱者, 耐心導師, 最小修改工程師. Create, copy, edit or delete presets (keep at least one); the selected persona and mode survive relaunch. No need to repeat the same persona prompt each time. Optional instructions are per-request and not persisted.
- 僅審碼: returns summary and severity/line-specific findings; any unexpected replacement code is discarded at the parser and cannot be applied at the workspace boundary.
- 審碼並修改: returns a suggested full-file replacement, with a changed-block preview and full original/proposed read-only views. It does not edit immediately. Press 套用至編輯器 to apply locally, then optionally save remotely using the existing conflict-aware flow.
- Restore the last AI application while its target still contains exactly the applied code. Newer edits are never overwritten by undo.
- Cancel requests, edit while waiting, or switch files; results retain their source snapshot. Applying checks ID, filename, remote identity, source text, mode, and busy/running state.

## DeepSeek protocol

Implementation follows the [official Chinese first-call guide](https://api-docs.deepseek.com/zh-cn/), [Chat Completions API](https://api-docs.deepseek.com/api/create-chat-completion/) and [JSON Output guide](https://api-docs.deepseek.com/guides/json_mode/), checked 2026-11-02.

- Default root `https://api.deepseek.com`, default model `deepseek-flash`. Change the model in settings if your account requires another model.
- `POST /chat/completions`, `Authorization: Bearer <saved key>`, JSON body. System message contains the selected persona and application contract; user message contains a JSON object with filename, source code and optional instructions.
- Non-streaming (`stream: false`), JSON object output, `max_tokens: 8192`. Official DeepSeek host uses `thinking: {type: disabled}` for predictable bounded review output. No paid automatic retries.
- Expected payload: `summary`, `findings` (`severity`, optional 1-based `line`, `title`, `detail`), optional `replacement_code`.
- Truncated output, empty or invalid JSON, non-stop completion and out-of-range findings are rejected. HTTP errors show the status without exposing response bodies, API Key or network internals.
- HTTP root URLs are rejected except localhost/loopback for local providers and tests. Credentials are scoped to normalized root URLs. Redirects are not followed, preventing forwarding Authorization to another destination.

## Local persistence and data boundaries

`~/Library/Application Support/LocalLab/AIReview/`

| File | Contents |
| --- | --- |
| settings.json | Endpoint, model, mode, persona list and selected persona UUID |
| api-keys.json | API keys indexed by SHA-256 of the normalized endpoint |

Directory permissions: 0700. Files: 0600, atomic writes inside the private directory. This follows the existing file-backed local credential convention and avoids repeated Keychain authorization; it is not additional at-rest encryption. API keys never enter UserDefaults, source, release resources, logs or model prompts. Changing a root URL does not reuse the previous root's key. Removing a key acts immediately; saving the remaining form commits interface/persona preferences. Forgetting a key does not revoke it at the provider.

Only the explicitly selected file's filename/code, persona and current request are sent. No directory traversal, hidden context, automatic remote execution, tool calls or multi-file changes are supported. Responses and code snapshots are memory-only until the user applies a proposal to the normal draft store. Closing/cancelling ignores late results. Source code comments are treated as data, though AI correctness still requires user judgement.

Limits: 128 KiB input code and replacement, 16 KiB per-request instruction and each persona, 20 personas, 100 findings, 2 MiB HTTP response. Preview shows at most 500 lines of one contiguous changed region with surrounding context; full before/after remains selectable. This bounds memory and avoids quadratic diff tables. Very large replacements may exceed model output tokens; truncated output is refused rather than partially applied.

## Live status bar

Time follows the local clock at minute boundaries. Battery/charging/AC changes use an IOKit power-source notification; network interface status uses NWPathMonitor, without probes or collecting SSIDs. A connected interface does not prove that the TUM server is reachable. Charging is labelled 充電中 with a bolt; AC attached while charging is paused is labelled 已接電. Missing battery readings are not fabricated.

The API capsule stays on one row. Per-request tokens and launch-total tokens use provider `usage.total_tokens` (prompt + completion), with cached input included once. The reported model name is used after a result; changing configuration shows the new model for the next request. Average consumption speed is total tokens divided by monotonic end-to-end request duration, including network time. It updates on completion, not as a live streaming generation rate.

The launch total is memory-only and resets when the App restarts. A malformed review with valid usage still counts the provider's reported tokens; cancelled/failed/missing-usage requests are unknown and are not estimated. `≥` marks the confirmed lower bound when any request has unknown consumption. Late cancelled results cannot be counted twice. This only covers requests made by this App instance, not the whole DeepSeek account or other apps. Narrow windows prioritize API information, then use a compact single row.

## Implementation

- `AI/AIReviewModels.swift`: typed mode, personas, config, normalized endpoint scope, snapshot, result, bounded diff and errors.
- `AI/AIReviewRepository.swift`: validated configuration and separate credential persistence.
- `AI/AIReviewClient.swift`: prompt/request contract, URLSession, TLS/redirect behavior and strict JSON parsing.
- `AI/AIReviewStore.swift`: explicit request state, cancellation generation, result and UI-facing state.
- `AI/AIReviewApplication.swift`: final workspace edit/undo boundary. Does not alter Jupyter service or remote baseline.
- `Views/AIReviewPane.swift`, `AISettingsView.swift`, `AIChangePreview.swift`: inspector, configuration and preview. A narrow read-only NSTextView bridge handles full code selection.

## Verification

`./script/test_ai.sh` compiles native assertions and starts one localhost Python standard-library fixture. It uses only `test-ai-only`, owns and terminates the fixture, and verifies actual URLSession request/response behavior. No real provider key is required or read. `./script/test.sh` checks existing workspace behavior. CI runs both suites plus a release compilation and metadata validation.

Native UI fixture: `./script/ui_smoke.sh` builds `.build/ui-smoke/Local Lab AI Test.app`. Run it only with loopback `LOCAL_LAB_UI_ENDPOINT` and an isolated `LOCAL_LAB_UI_ROOT`; it never restores the user's school connection or drafts. It is outside production Sources and is not shipped.

See [verification-1.1.0.md](verification-1.1.0.md) for recorded results and limits. Synthetic fixture output is not evidence that a paid live DeepSeek request was made. The user subsequently supplied and authorized a real key; a single explicit live toy-code request was verified (see the verification record). Personal credentials remain outside the repository. `script/live_ai_check.sh --live` is an opt-in paid check; CI never runs it.
