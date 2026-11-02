import SwiftUI
import AppKit

// MARK: - User-tunable appearance
//
// Everything the user can change from Settings › 外觀. Values are persisted in
// UserDefaults so the rest of the app can read them from plain colours and
// modifiers, and the Settings window stays the single source of truth.

enum AccentChoice: String, CaseIterable, Identifiable {
    case periwinkle, coral, sky, mint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .periwinkle: return "長春花"
        case .coral: return "珊瑚"
        case .sky: return "天藍"
        case .mint: return "薄荷"
        }
    }

    var color: Color {
        switch self {
        case .periwinkle: return Aurora.brand
        case .coral: return Aurora.coral
        case .sky: return Aurora.azure
        case .mint: return Aurora.mint
        }
    }

    /// Second stop of the accent gradient.
    var partner: Color {
        switch self {
        case .periwinkle: return Aurora.azure
        case .coral: return Aurora.cream
        case .sky: return Aurora.periwinkle
        case .mint: return Aurora.azure
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [color, partner], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum AuroraPace: String, CaseIterable, Identifiable {
    case still, slow, standard, brisk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .still: return "靜止"
        case .slow: return "緩慢"
        case .standard: return "標準"
        case .brisk: return "流動"
        }
    }

    /// Seconds for one full pass. `.still` never animates.
    var duration: Double {
        switch self {
        case .still: return 0
        case .slow: return 44
        case .standard: return 26
        case .brisk: return 15
        }
    }
}

enum PanelFinish: String, CaseIterable, Identifiable {
    case frosted, solid, clear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frosted: return "磨砂"
        case .solid: return "實心"
        case .clear: return "通透"
        }
    }
}

enum CornerDensity: String, CaseIterable, Identifiable {
    case compact, regular, grand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "緊湊"
        case .regular: return "標準"
        case .grand: return "圓潤"
        }
    }

    var cardRadius: CGFloat {
        switch self {
        case .compact: return 12
        case .regular: return 16
        case .grand: return 22
        }
    }

    var panelRadius: CGFloat {
        switch self {
        case .compact: return 13
        case .regular: return 18
        case .grand: return 24
        }
    }
}

enum MotionLevel: String, CaseIterable, Identifiable {
    case calm, standard, lively

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: return "含蓄"
        case .standard: return "標準"
        case .lively: return "活潑"
        }
    }

    var multiplier: Double {
        switch self {
        case .calm: return 0.55
        case .standard: return 1
        case .lively: return 1.45
        }
    }

    /// Read by `Motion` without going through the environment object.
    static var current: MotionLevel {
        MotionLevel(rawValue: UserDefaults.standard.string(forKey: AppearanceKeys.motion) ?? "") ?? .standard
    }
}

enum AppearanceKeys {
    static let accent = "accentChoice"
    static let pace = "auroraPace"
    static let intensity = "auroraIntensity"
    static let panel = "panelFinish"
    static let corners = "cornerDensity"
    static let motion = "motionLevel"
    /// Optional override for the accent colour, stored as an "RRGGBB" string.
    static let customAccent = "customAccent"
}

@MainActor
final class AppearanceStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var accent: AccentChoice {
        didSet { defaults.set(accent.rawValue, forKey: AppearanceKeys.accent) }
    }
    @Published var pace: AuroraPace {
        didSet { defaults.set(pace.rawValue, forKey: AppearanceKeys.pace) }
    }
    @Published var intensity: Double {
        didSet { defaults.set(intensity, forKey: AppearanceKeys.intensity) }
    }
    @Published var panel: PanelFinish {
        didSet { defaults.set(panel.rawValue, forKey: AppearanceKeys.panel) }
    }
    @Published var corners: CornerDensity {
        didSet { defaults.set(corners.rawValue, forKey: AppearanceKeys.corners) }
    }
    @Published var motion: MotionLevel {
        didSet { defaults.set(motion.rawValue, forKey: AppearanceKeys.motion) }
    }
    /// `RRGGBB` override; nil means "use the preset accent".
    @Published var customAccentHex: String? {
        didSet {
            if let customAccentHex { defaults.set(customAccentHex, forKey: AppearanceKeys.customAccent) }
            else { defaults.removeObject(forKey: AppearanceKeys.customAccent) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accent = AccentChoice(rawValue: defaults.string(forKey: AppearanceKeys.accent) ?? "") ?? .periwinkle
        pace = AuroraPace(rawValue: defaults.string(forKey: AppearanceKeys.pace) ?? "") ?? .standard
        intensity = min(max((defaults.object(forKey: AppearanceKeys.intensity) as? Double) ?? 1, 0.4), 1.8)
        panel = PanelFinish(rawValue: defaults.string(forKey: AppearanceKeys.panel) ?? "") ?? .frosted
        corners = CornerDensity(rawValue: defaults.string(forKey: AppearanceKeys.corners) ?? "") ?? .regular
        motion = MotionLevel(rawValue: defaults.string(forKey: AppearanceKeys.motion) ?? "") ?? .standard
        customAccentHex = defaults.string(forKey: AppearanceKeys.customAccent)
    }

    /// The colour actually used right now: the custom override or the preset.
    var customColor: Color? { customAccentHex.flatMap(Aurora.fromHex) }
    var effectiveAccent: Color { customColor ?? accent.color }

    func setCustomAccent(_ color: Color) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        let red = Int((srgb.redComponent * 255).rounded())
        let green = Int((srgb.greenComponent * 255).rounded())
        let blue = Int((srgb.blueComponent * 255).rounded())
        customAccentHex = String(format: "%02X%02X%02X", red, green, blue)
    }

    var cardRadius: CGFloat { corners.cardRadius }
    var panelRadius: CGFloat { corners.panelRadius }

    /// Content cards get a little more revealing when the panels are sheer.
    var cardOpacity: Double {
        switch panel {
        case .frosted: return 0.90
        case .solid: return 0.98
        case .clear: return 0.76
        }
    }

    func reset() {
        customAccentHex = nil
        accent = .periwinkle
        pace = .standard
        intensity = 1
        panel = .frosted
        corners = .regular
        motion = .standard
    }
}

// MARK: - Backdrop helpers

/// Full-bleed panel background that follows the chosen finish.
struct PanelBackdrop: View {
    var finish: PanelFinish
    var radius: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fillStyle)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(finish == .solid ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Aurora.panelTint))
            )
    }

    private var fillStyle: AnyShapeStyle {
        switch finish {
        case .frosted: return AnyShapeStyle(.regularMaterial)
        case .solid: return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        case .clear: return AnyShapeStyle(.ultraThinMaterial)
        }
    }
}
