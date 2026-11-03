# 1.1.3 verification — 2026-11-03

Follow-up after the immutable 1.1.2 release.

- Reproduced white-on-light selected pills in dark mode and replaced both selection recipes with the same adaptive accent fill.
- Native accessibility reports selected buttons for all three Markdown modes. Option-Command-2 opens the source editor; Option-Command-3 creates source and preview panes; Option-Command-1 restores the rendered heading/table/code/list view. Document content remains unchanged.
- A 1080-point window with sidebar and AI visible reproduced vertically wrapped header chips and preview clipping. Separate header controls, fixed chip sizing, smaller split minimum widths and compact CSS removed both defects in subsequent dark- and light-mode screenshots.
- Existing 7 native and 12 AI/status/HTTP test groups passed after the changes. These include transport errors, cancellation, usage accounting and guarded apply/undo. No AI transport change or additional paid request was made for this patch.
- In the installed app, actual local Python 3.10.12 execution and remote review both printed Hello from local API / Total: 20 and finished with 本機與伺服器通過.
- Actual server Terminal UI returned SERVER_UI_861, Python 3.10.12, a Chinese interactive reply and SERVER_EXIT_1. A 60-second sleep was interrupted after its start marker, returning ^C and a shell prompt without executing the finish printf. The command text itself remains in the terminal echo and is not confused with a finish result.
- Server commands only printed results or used an App-owned terminal; HISTFILE was unset. No existing server document was edited. Normal App exit was used for owned-resource cleanup; a cache-bypassing GET of the displayed owned kernel ID returned HTTP 404.

The optimized release build and strict signature validation passed. CI and installed version/signature are validated separately before delivery. No multi-hour soak or universal absence-of-bugs guarantee is claimed.
