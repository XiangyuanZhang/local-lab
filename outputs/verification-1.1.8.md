# Local Lab 1.1.8 (build 12)

## Notebook interaction

Command/Control+Enter runs the selected cell; Shift+Enter runs and advances. Run all remains explicit. Markdown defaults to rendered content and can be edited with Edit or double-click, then rendered with its run shortcut. Code source, execution prompt and output are displayed together. Generated cell UI labels are English; user document content is preserved.

A persistent owned local Python worker retains variables without replaying earlier cells. Each requested code cell passes the local check before remote execution. Disconnect terminates the local worker; timeout and output limits are bounded. Existing input()/IPython magic limitations remain.

## AI scope

The default Notebook scope is the current/recent code cell. Only its source is sent. Full-document scope is explicit. Proposed code changes replace only that cell, preserving the surrounding Notebook; original snapshot checks and exact undo protect against stale modifications. No real AI API calls are made by tests.

## Validation

Native checks include current-cell-only execution despite an earlier intentional error, Markdown rendering without remote execution, recent-cell targeting after advance, actual Python variable persistence/rerun/error recovery, plus existing regressions. Mock Jupyter checks and AI isolation/apply/undo checks pass.

Installed App real-server check: an earlier code cell contains a deliberate TypeError and is not run. Command+Enter executes value=40 in a later cell; Command+Enter in the following cell evaluates value+2. Both local Python and the school kernel return 42; Out [2] is rendered inline. Markdown Command+Enter returns from source editing to rendered content. Tests use an owned local practice draft and the App-owned kernel, with no writes to existing school files.

## Icon

Approved source artwork is preserved. Static ICNS export adds transparent optical margins and system continuous corners. Startup refreshes the running Dock icon from the bundled resource. See docs/design/app-icon.md. No multi-hour idle stability test has been performed.
