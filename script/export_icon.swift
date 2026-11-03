import SwiftUI
import AppKit

/// Static ICNS export for macOS 14+; preserve the full-bleed original separately.
/// The legacy bitmap needs its own continuous mask and optical margin, unlike .icon assets.
@main struct ExportIcon {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = root.appendingPathComponent("Resources/AppIcon-source.png")
        guard let image = NSImage(contentsOf: source) else { fatalError("Missing icon source") }
        let content = Image(nsImage: image).resizable().interpolation(.high)
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            .padding(100)
        let renderer = ImageRenderer(content: content); renderer.scale = 1; renderer.isOpaque = false
        guard let result = renderer.cgImage else { fatalError("Icon render failed") }
        let bitmap = NSBitmapImageRep(cgImage: result)
        precondition(bitmap.pixelsWide == 1024 && bitmap.pixelsHigh == 1024)
        precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0 && bitmap.colorAt(x: 50, y: 512)!.alphaComponent == 0)
        precondition(bitmap.colorAt(x: 512, y: 512)!.alphaComponent > 0.99)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG export failed") }
        try png.write(to: root.appendingPathComponent("Resources/AppIcon.png"))
        let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        func run(_ tool: String, _ args: [String]) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath: tool); process.arguments = args
            process.standardOutput = FileHandle.nullDevice; try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { fatalError("Icon conversion failed: " + tool) }
        }
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
                try run("/usr/bin/sips", ["-z", String(size * scale), String(size * scale), root.appendingPathComponent("Resources/AppIcon.png").path, "--out", iconset.appendingPathComponent(name).path])
            }
        }
        try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path])
        print("Exported 1024px icon with continuous corners and transparent optical margins.")
    }
}
