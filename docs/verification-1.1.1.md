# 1.1.1 verification

2026-11-02, macOS / Apple Silicon. Patch after immutable v1.1.0.

- Reproduced the installed 1.1.0 failure in native full-screen mode: an opaque top strip and hidden status capsules.
- Native UI fixture with the same local background image: full-screen entry showed continuous photo behind the titlebar and visible system/API status capsules; the native sidebar toolbar action worked. The system View menu reported `Exit Full Screen`, confirming actual full-screen mode rather than window zoom. Exit through that menu restored the normal window and full-screen button, preserving code and selection.
- Window bridge runs only on attachment and window lifecycle/resize events. It sets transparent titlebar/separator properties, never rewrites style masks while full screen, removes observers on detachment/deallocation, and updates SwiftUI only when the measured inset changes. No timer, global window mutation or view-hierarchy traversal is added.
- Main-region dimming moved from a rectangular full-column layer into rounded editor/results/AI cards. Existing photo transparency is used once per card; the sidebar retains its independent setting. Card gaps and titlebar show the continuous window background.
- UI fixture compilation and source-format checks passed. Final optimized build, CI and release checksum/signature validation are required before publication; their evidence is attached to the patch PR and release manifest.

No new paid DeepSeek request or long-duration stability test was needed for this presentation patch. AI transport and guarded edit behavior are unchanged; the release workflow still runs both native suites.
