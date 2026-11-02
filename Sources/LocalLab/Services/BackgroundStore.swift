import SwiftUI
import AppKit
import ImageIO

struct BackgroundConfiguration: Codable {
    var sourceFile: String
    var croppedFile: String
    var crop: [Double]
    var aspect: Double
    var transparency: Double
    var blur: Double
    var sidebarTransparency: Double? = nil
}
struct WorkspaceBackgroundKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var workspaceHasBackground: Bool { get { self[WorkspaceBackgroundKey.self] } set { self[WorkspaceBackgroundKey.self] = newValue } }
}
@MainActor
final class BackgroundStore: ObservableObject {
    @Published private(set) var configuration: BackgroundConfiguration?
    @Published private(set) var image: NSImage?
    let directory: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalLab/Background")) {
        self.directory = directory
        if let data = try? Data(contentsOf: directory.appendingPathComponent("settings.json")), let saved = try? JSONDecoder().decode(BackgroundConfiguration.self, from: data),
           saved.sourceFile == URL(fileURLWithPath: saved.sourceFile).lastPathComponent,
           saved.croppedFile == URL(fileURLWithPath: saved.croppedFile).lastPathComponent,
           saved.crop.count == 4, saved.transparency.isFinite, saved.blur.isFinite,
           let image = NSImage(contentsOf: directory.appendingPathComponent(saved.croppedFile)) {
            configuration = saved; self.image = image
        }
    }
    var source: NSImage? { configuration.flatMap { NSImage(contentsOf: directory.appendingPathComponent($0.sourceFile)) } }
    static func load(_ url: URL) throws -> NSImage {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 52_428_800, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 3072] as CFDictionary) else { throw LabError.message("无法读取图片（上限 50 MB）。") }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    func save(source: NSImage, crop: CGRect, aspect: Double, transparency: Double, blur: Double, sidebarTransparency: Double? = nil) throws {
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw LabError.message("图片格式错误。") }
        let rect = CGRect(x: crop.minX * Double(cg.width), y: crop.minY * Double(cg.height), width: crop.width * Double(cg.width), height: crop.height * Double(cg.height)).integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard rect.width >= 1, rect.height >= 1, let cropped = cg.cropping(to: rect) else { throw LabError.message("裁剪区域错误。") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let identifier = UUID().uuidString
        let next = BackgroundConfiguration(sourceFile: identifier + "-source.png", croppedFile: identifier + "-crop.png", crop: [crop.minX, crop.minY, crop.width, crop.height], aspect: aspect, transparency: min(1, max(0, transparency)), blur: min(40, max(0, blur)), sidebarTransparency: min(1, max(0, sidebarTransparency ?? transparency)))
        func png(_ image: CGImage) throws -> Data {
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw LabError.message("图片编码失败。") }; return data
        }
        let sourceURL = directory.appendingPathComponent(next.sourceFile), cropURL = directory.appendingPathComponent(next.croppedFile)
        do {
            try png(cg).write(to: sourceURL, options: .atomic)
            try png(cropped).write(to: cropURL, options: .atomic)
            try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("settings.json"), options: .atomic)
        } catch { try? FileManager.default.removeItem(at: sourceURL); try? FileManager.default.removeItem(at: cropURL); throw error }
        let previous = configuration
        configuration = next; image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        if let previous { removeImages(previous) }
    }
    func clear() throws {
        let settings = directory.appendingPathComponent("settings.json")
        if FileManager.default.fileExists(atPath: settings.path) { try FileManager.default.removeItem(at: settings) }
        if let configuration { removeImages(configuration) }
        configuration = nil; image = nil
    }
    private func removeImages(_ value: BackgroundConfiguration) {
        for file in [value.sourceFile, value.croppedFile] where file == URL(fileURLWithPath: file).lastPathComponent { try? FileManager.default.removeItem(at: directory.appendingPathComponent(file)) }
    }
}
struct WorkspaceBackground: View {
    @ObservedObject var store: BackgroundStore
    var body: some View {
        GeometryReader { geometry in
            if let image = store.image, let settings = store.configuration {
                Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height)
                    .blur(radius: settings.blur).clipped()
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

