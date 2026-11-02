# 1.1.2 verification — 2026-11-02

UI was checked in isolated signed app bundles using the production views: dark/light modes, native fullscreen entry/exit, title and status separation with long Unicode names, single-layer sidebar toggle, retained code after sidebar/AI reveal, 1080×550 content sizing and system half-screen layout, wrapped long code, Markdown headings/table/code, native settings sheets, and local terminal output. Terminal horizontal position stayed at zero after fullscreen exit with a 200-character line. The native hover bar contains no duplicate workspace actions and uses unifiedCompact; final native hover sizing is controlled by macOS.

Local native checks: 7 groups passed. AI/status and real loopback HTTP integration checks: 12 groups passed after allowing loopback socket access. Release build and strict signature verification passed.

The actual school-server API check passed all steps on retry: authentication, fresh owned kernel, new UUID directory, create/read/modify files, execute stdout/stderr, PNG display_data, Markdown fixture, terminal WebSocket stdout/stderr/interactive input, deletion/readback of test files and directory, and owned terminal/kernel cleanup. Existing server files and kernels were never edited or deleted. The first run had a test-only missing os import and left its private matplotlib cache; this was corrected, and the remaining dedicated test directory was separately cleaned. UI flag in this API harness is pre-set because UI rendering was tested separately; it is not evidence that the temporary remote files were opened in the production UI.

One real DeepSeek toy-code review passed: model deepseek-flash, 379 prompt + 249 completion = 628 tokens, roughly 2.25 seconds. Saved credentials were reused and were not logged or packaged.

No multi-hour soak, multi-display coverage, or exhaustive OS accessibility-setting matrix is claimed. These limits do not justify a universal “no possible UI bug” claim.
