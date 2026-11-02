import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct BackgroundEditor: View {
    @ObservedObject var store: BackgroundStore
    @Environment(\.dismiss) private var dismiss
    @State private var source: NSImage?
    @State private var importing = false
    @State private var zoom = 1.0
    @State private var offset = CGSize.zero
    @State private var dragOrigin: CGSize?
    @State private var aspect = 1.6
    @State private var transparency = 0.75
    @State private var sidebarTransparency = 0.75
    @State private var blur = 0.0
    @State private var error: String?
    private var viewport: CGSize { let width = min(560.0, 320 * aspect); return CGSize(width: width, height: width / aspect) }
    private var sourceSize: CGSize { source?.size ?? CGSize(width: 1, height: 1) }
    private var scale: Double { max(viewport.width / sourceSize.width, viewport.height / sourceSize.height) * zoom }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("背景设置").font(.title2.weight(.semibold))
                Spacer()
                Button("选择图片…") { importing = true }
            }
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if let source {
                    Image(nsImage: source).resizable().frame(width: sourceSize.width * scale, height: sourceSize.height * scale)
                        .offset(offset).blur(radius: blur)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            if dragOrigin == nil { dragOrigin = offset }
                            offset = clamp(CGSize(width: (dragOrigin?.width ?? 0) + value.translation.width, height: (dragOrigin?.height ?? 0) + value.translation.height))
                        }.onEnded { _ in dragOrigin = nil })
                } else { Text("选择图片后，拖动图片调整裁剪区域").foregroundStyle(.secondary) }
            }.frame(width: viewport.width, height: viewport.height).clipped()
                .overlay {
                    HStack(spacing: 0) {
                        Aurora.scrim.opacity(1 - sidebarTransparency).frame(width: viewport.width * 0.2)
                        Aurora.scrim.opacity(1 - transparency)
                    }.allowsHitTesting(false)
                }.overlay(Rectangle().stroke(.secondary, lineWidth: 1))
                .frame(maxWidth: .infinity).accessibilityLabel("背景裁剪预览")
            HStack {
                Picker("裁剪比例", selection: Binding(get: { aspect }, set: { aspect = $0; zoom = 1; offset = .zero })) {
                    Text("16:10").tag(1.6); Text("16:9").tag(16.0 / 9.0); Text("4:3").tag(4.0 / 3.0); Text("1:1").tag(1.0)
                }.frame(width: 210)
                Text("拖动图片可平移裁剪位置").font(.caption).foregroundStyle(.secondary)
            }
            HStack { Text("裁剪缩放").frame(width: 100, alignment: .leading); Slider(value: $zoom, in: 1...4); Text(String(format: "%.1f×", zoom)).monospacedDigit().frame(width: 55) }
            HStack { Text("主操作区透明度").frame(width: 115, alignment: .leading); Slider(value: $transparency, in: 0...1); Text("\(Int(transparency * 100))%").monospacedDigit().frame(width: 55) }
            HStack { Text("侧边栏透明度").frame(width: 115, alignment: .leading); Slider(value: $sidebarTransparency, in: 0...1); Text("\(Int(sidebarTransparency * 100))%").monospacedDigit().frame(width: 55) }
            HStack { Text("高斯模糊").frame(width: 100, alignment: .leading); Slider(value: $blur, in: 0...40); Text("\(Int(blur)) pt").monospacedDigit().frame(width: 55) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("恢复默认") { do { try store.clear(); dismiss() } catch { self.error = error.localizedDescription } }.disabled(store.image == nil)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("确认设置背景") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(source == nil)
            }
        }.padding(24).frame(width: 620)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            do {
                source = try BackgroundStore.load(result.get()); zoom = 1; offset = .zero; error = nil
            } catch { self.error = error.localizedDescription }
        }
        .onAppear { restore() }
        .onChange(of: zoom) { _, _ in offset = clamp(offset) }
    }
    private func clamp(_ value: CGSize) -> CGSize {
        let x = max(0, (sourceSize.width * scale - viewport.width) / 2), y = max(0, (sourceSize.height * scale - viewport.height) / 2)
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
    private func restore() {
        guard let settings = store.configuration, let image = store.source else { return }
        source = image; transparency = settings.transparency; sidebarTransparency = settings.sidebarTransparency ?? settings.transparency; blur = settings.blur
        aspect = settings.aspect
        let base = max(viewport.width / image.size.width, viewport.height / image.size.height)
        zoom = min(4, max(1, viewport.width / (image.size.width * settings.crop[2]) / base))
        offset = clamp(CGSize(width: (0.5 - settings.crop[0] - settings.crop[2] / 2) * image.size.width * scale, height: (0.5 - settings.crop[1] - settings.crop[3] / 2) * image.size.height * scale))
    }
    private func save() {
        guard let source else { return }
        let crop = CGRect(x: (sourceSize.width - viewport.width / scale) / 2 / sourceSize.width - offset.width / scale / sourceSize.width,
                          y: (sourceSize.height - viewport.height / scale) / 2 / sourceSize.height - offset.height / scale / sourceSize.height,
                          width: viewport.width / scale / sourceSize.width, height: viewport.height / scale / sourceSize.height)
        do { try store.save(source: source, crop: crop, aspect: aspect, transparency: transparency, blur: blur, sidebarTransparency: sidebarTransparency); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
