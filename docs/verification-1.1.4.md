# 1.1.4 — remote Notebook preview

## Defect and change

RemoteSync.openRemote explicitly launched Notebook entries through NSWorkspace, and the Contents client accepted only plain text files. Notebook entries now use the same in-app draft/selection route, fetch JSON format from the Contents API, and display a passive Notebook preview.

Markdown and code cells, saved stream/error/plain-text outputs and bounded PNG images are rendered locally. Notebook code and HTML output are not executed. Notebook previews are read-only, and saveRemoteFile rejects text-style Notebook writes. Limits: nbformat 4, 8 MB, 2000 cells; unsupported documents stay inside the App with an explanatory message.

## Validation

- Native parser checks: Markdown/code/output preservation, code-fence escaping, ANSI cleanup, unsupported format rejection and active HTML-output exclusion.
- Local Jupyter integration: Notebook JSON read, read-only write rejection, unchanged server content, and selection remaining in WorkspaceStore rather than invoking an external browser. Existing text-file CRUD, sidebar selection, conflicts and deletion/local-copy checks passed. A stale local sidebar-cache case exposed by this test was also fixed.
- Isolated native UI: selected remote Notebook.ipynb remains in the App; its heading, Chinese Markdown, print(42) cell and saved output 42 are present in the rendered accessibility tree and screenshot. Run is disabled.
- Existing AI/status/HTTP suite passed. No paid model request was needed.
- Actual school-server test could not proceed during this run: lecture.cs.tum.de:9000 timed out (curl HTTP 000). This is not recorded as a live-server pass. The opt-in NotebookLiveCheck harness only targets its own UUID test folder when connectivity is available.

The current app icon is unchanged. A replacement icon is preview-only until the user confirms it.
