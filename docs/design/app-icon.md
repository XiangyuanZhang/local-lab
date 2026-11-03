# Local Lab app icon

Approved artwork: `Resources/AppIcon-source.png`. It remains square and full-bleed. Do not add another mask to this source.

The app currently ships a static ICNS for macOS 14 and later. Unlike an Icon Composer `.icon` asset compiled with Xcode, a standalone ICNS needs its own final silhouette and transparent optical margin. The export uses a centered 824 × 824 plate on a 1024 canvas, 100px margins and the system SwiftUI continuous-corner shape. All 1x/2x sizes are included. This is the legacy export geometry, not a claim that the latest layered source should be pre-masked.

Run from the repository root:

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/swift-cache script/export_icon.swift -o .build/ExportIcon
.build/ExportIcon
```

The exporter checks transparent edges and opaque artwork center, writes AppIcon.png and generates AppIcon.icns. Production startup explicitly assigns the bundled ICNS to the running Dock tile, avoiding stale icon artwork after an in-place update.

References: [Apple App Icons](https://developer.apple.com/design/human-interface-guidelines/app-icons/), [Apple Design Resources](https://developer.apple.com/design/resources/), [Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).
