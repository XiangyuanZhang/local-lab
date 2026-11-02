import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: WorkspaceStore
    @EnvironmentObject private var appearance: AppearanceStore
    @AppStorage("autoConnect") private var autoConnect = true
    @AppStorage("localPythonExecutable") private var python = ""
    @AppStorage("localWorkspace") private var workspace = ""
    @AppStorage("editorFontSize") private var fontSize = 14.0

    var body: some View {
        Form {
            Section("外觀") {
                AppearancePreview()
                    .padding(.vertical, 4)
                accentRow
                Picker("極光節奏", selection: $appearance.pace) {
                    ForEach(AuroraPace.allCases) { pace in Text(pace.title).tag(pace) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("極光強度")
                        Spacer()
                        Text(String(format: "%.1f×", appearance.intensity))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $appearance.intensity, in: 0.4...1.8, step: 0.1)
                }
                Picker("面板質感", selection: $appearance.panel) {
                    ForEach(PanelFinish.allCases) { finish in Text(finish.title).tag(finish) }
                }
                .pickerStyle(.segmented)
                Picker("圓角", selection: $appearance.corners) {
                    ForEach(CornerDensity.allCases) { density in Text(density.title).tag(density) }
                }
                .pickerStyle(.segmented)
                Picker("動效節奏", selection: $appearance.motion) {
                    ForEach(MotionLevel.allCases) { level in Text(level.title).tag(level) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("含蓄：彈簧更短、位移更小；活潑：彈性更明顯。系統開啟「減少動態效果」時一律停用位移。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("恢復預設外觀") { withAnimation(Motion.snappy) { appearance.reset() } }
                }
            }
            Section("背景") {
                Button("更换背景…") { store.showBackgroundEditor = true }
                Text("未設定背景圖片時顯示極光背景；設定圖片後以圖片為底，可調整裁剪、比例、模糊與透明度。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("編輯器") {
                Stepper("字體大小：\(Int(fontSize)) pt", value: $fontSize, in: 11...24)
                Text("草稿自動保存於本機。遠端程式只有在按下「執行」後才會送出。").font(.caption).foregroundStyle(.secondary)
            }
            Section("本機執行") {
                Text("先使用與伺服器完全相同的 Python 版本在本機執行，成功後才送至伺服器覆核。")
                TextField("Python 執行檔（留空自動準備）", text: $python)
                TextField("本機工作目錄（留空使用 App 工作區）", text: $workspace)
                Text("Python：\(store.connection?.pythonVersion ?? "待連線核對")。套件需另行安裝；兩次執行各自使用自己的檔案與環境。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("連線") {
                Toggle("啟動時自動連線", isOn: $autoConnect)
                if store.hasBuiltInToken {
                    Text("這個版本內建 API token，啟動時直接連線，不經過鑰匙圈。要更換請修改 Resources/builtin-token.txt 後重新建置。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(store.hasSavedToken ? "Token 保存在本機檔案（Application Support/LocalLab/credential.txt，0600）。" : "目前沒有已保存的 token。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("移除已儲存 token") { store.forgetSavedToken() }.disabled(!store.hasSavedToken)
                }
                Text("結束 App 時會嘗試關閉專用核心。移除 token 不會撤銷伺服器端的 token。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(appearance.accent.color)
        .padding()
        .frame(width: 540, height: 720)
    }

    private var accentRow: some View {
        HStack(spacing: 12) {
            Text("強調色")
            ForEach(AccentChoice.allCases) { choice in
                Button {
                    withAnimation(Motion.snappy) { appearance.accent = choice }
                } label: {
                    Circle()
                        .fill(choice.gradient)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().strokeBorder(.white.opacity(0.65), lineWidth: 0.8)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(appearance.accent == choice ? Color.primary.opacity(0.7) : .clear, lineWidth: 2)
                                .padding(-3)
                        )
                        .shadow(color: choice.color.opacity(0.35), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .help(choice.title)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(appearance.accent == choice ? .isSelected : [])
            }
            Spacer()
            Text(appearance.accent.title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Live sample of the current appearance settings; it also animates so the
/// chosen motion level can be compared without leaving Settings.
struct AppearancePreview: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = 0
    @Namespace private var pill

    private let labels = ["預覽", "編輯", "並排"]

    var body: some View {
        ZStack {
            PanelBackdrop(finish: appearance.panel, radius: appearance.cardRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: appearance.cardRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                )
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(appearance.accent.color)
                    Text("預覽").font(.headline)
                    Spacer()
                    Aurora.Chip(text: "執行中", systemImage: "waveform", kind: .coral, animated: true)
                    StatusOrb(phase: .ready, tint: Aurora.mint, size: 7)
                }
                HStack(spacing: 6) {
                    SlidingPill(ids: [0, 1, 2], selection: tab, namespace: pill) { id in
                        Text(labels[id])
                            .font(.caption.weight(tab == id ? .semibold : .regular))
                            .foregroundStyle(tab == id ? Color.primary : Color.secondary)
                            .frame(minWidth: 34)
                            .contentShape(Capsule())
                            .onTapGesture { withAnimation(Motion.snappy) { tab = id } }
                    }
                    Spacer()
                    Aurora.Chip(text: "Python", kind: .brand)
                }
                HStack(spacing: 10) {
                    Button("執行程式") {}
                        .buttonStyle(.borderedProminent)
                        .tint(appearance.accent.color)
                    Button("儲存至遠端") {}
                        .buttonStyle(PressableStyle(scale: 0.96))
                        .foregroundStyle(appearance.accent.color)
                    Spacer()
                    Text(appearance.motion.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .frame(height: 170)
        .animation(Motion.gentle, value: tab)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                guard !Task.isCancelled else { break }
                withAnimation(Motion.snappy) { tab = (tab + 1) % labels.count }
            }
        }
    }
}
