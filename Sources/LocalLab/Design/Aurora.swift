import SwiftUI
import AppKit

// MARK: - Design language
//
// Inspired by the "Agog" cycling companion reference (Figma file
// sXro1JaLt8UsoVgSEDeaJ9): a soft aurora backdrop, frosted glass cards with
// large continuous radii, hairline white borders, coral/periwinkle accents and
// quiet spring motion. Everything here is additive: the editor, terminals,
// remote browser and their behaviour are untouched.

enum Aurora {

    // MARK: Palette

    /// Solid colours, resolved per appearance.
    static func color(light: UInt32, dark: UInt32, alpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: CGFloat(alpha)
            )
        })
    }

    static let sky = color(light: 0x90BEF1, dark: 0x1B2740)
    static let periwinkle = color(light: 0xA090F1, dark: 0x453B7A)
    static let lilac = color(light: 0xBAABCF, dark: 0x2B2542)
    static let blush = color(light: 0xF190A0, dark: 0x5A2A36)
    static let cream = color(light: 0xF2E68C, dark: 0x3A3520)

    /// Brand accent used for selection, focus and primary actions.
    static let brand = color(light: 0xA090F1, dark: 0xB4A6FF)
    /// Warm accent: running state, live recording, attention.
    static let coral = color(light: 0xF190A0, dark: 0xFFA3B1)
    /// Cool accent: links, remote/sync affordances.
    static let azure = color(light: 0x90BEF1, dark: 0x9CC8F7)
    /// Success / connected.
    static let mint = color(light: 0x3AE31C, dark: 0x63F04B)

    /// Wash laid over frosted panels so busy backgrounds never hurt legibility.
    static let panelTint = color(light: 0xFFFFFF, dark: 0x0F0F16, alpha: 0.50)

    static var ink: Color { .primary }
    static var inkSecondary: Color { .secondary }

    // MARK: Gradients

    /// Title / wordmark gradient: blush → periwinkle → sky.
    static var signature: LinearGradient {
        LinearGradient(colors: [coral, brand, azure], startPoint: .leading, endPoint: .trailing)
    }

    /// Wordmark gradient, matching the reference headlines (pink → blue).
    static var wordmark: LinearGradient {
        LinearGradient(colors: [coral, azure], startPoint: .leading, endPoint: .trailing)
    }

    /// Base wash for the aurora canvas.
    static var canvas: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: sky, location: 0),
                .init(color: lilac, location: 0.30),
                .init(color: periwinkle, location: 0.62),
                .init(color: sky.opacity(0.85), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Surfaces

    /// Frosted panel used for the sidebar, bottom panel and inspector cards.
    struct GlassPanel: ViewModifier {
        var radius: CGFloat = 18
        var borderOpacity: Double = 0.42
        func body(content: Content) -> some View {
            content.background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Aurora.panelTint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 0.8)
                    )
            )
            .shadow(color: Color.black.opacity(0.07), radius: 18, x: 0, y: 8)
        }
    }

    /// Opaque-ish card used for large content surfaces (editor, tables).
    struct CardSurface: ViewModifier {
        var radius: CGFloat = 18
        var opacity: Double = 0.94
        func body(content: Content) -> some View {
            content
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(opacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
        }
    }

    /// Pill chip, e.g. run state or sync notice.
    struct Chip: View {
        enum Kind { case neutral, brand, coral, mint }
        var text: String
        var systemImage: String?
        var kind: Kind = .neutral

        private var tint: Color {
            switch kind {
            case .neutral: return Color.secondary
            case .brand: return Aurora.brand
            case .coral: return Aurora.coral
            case .mint: return Aurora.mint
            }
        }

        var body: some View {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)) }
                Text(text)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.14)))
            .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 0.6))
        }
    }
}

// MARK: - Motion

enum Motion {
    /// Fast, precise feedback for taps, tabs and selection.
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.82)
    /// Softer transitions for panes, banners and sheets.
    static let gentle = Animation.spring(response: 0.48, dampingFraction: 0.88)
    /// Short cross-fades where a spring would feel heavy.
    static let quick = Animation.easeOut(duration: 0.16)
    /// Entry of the whole workspace.
    static let entrance = Animation.spring(response: 0.6, dampingFraction: 0.9)
}

// MARK: - Reusable effects

/// Press feedback: slight scale + opacity, disabled when Reduce Motion is on.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.965
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
    }
}

/// Gentle lift on hover, used by cards and list rows.
struct HoverLift: ViewModifier {
    var scale: CGFloat = 1.004
    var shadowRadius: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && !reduceMotion ? scale : 1)
            .shadow(color: Color.black.opacity(hovering ? 0.12 : 0), radius: hovering ? shadowRadius : 0, x: 0, y: 4)
            .animation(reduceMotion ? nil : Motion.snappy, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Status dot that breathes while the app is connected or connecting.
struct PulseDot: View {
    var active: Bool
    var tint: Color
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if active && !reduceMotion {
                Circle()
                    .fill(tint.opacity(0.35))
                    .frame(width: size * 2.1, height: size * 2.1)
                    .scaleEffect(pulsing ? 1.0 : 0.55)
                    .opacity(pulsing ? 0.0 : 0.9)
            }
            Circle()
                .fill(tint)
                .frame(width: size, height: size)
                .shadow(color: tint.opacity(active ? 0.55 : 0), radius: active ? 4 : 0)
        }
        .frame(width: size * 2.1, height: size * 2.1)
        .onAppear { start() }
        .onChange(of: active) { _, _ in start() }
        .accessibilityHidden(true)
    }

    private func start() {
        guard active, !reduceMotion else { pulsing = false; return }
        pulsing = false
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulsing = true }
    }
}

/// Animated selection pill that slides between options (tabs, segmented controls).
struct SlidingPill<ID: Hashable, Label: View>: View {
    var ids: [ID]
    var selection: ID
    var content: (ID) -> Label
    private let namespace: Namespace.ID

    init(ids: [ID], selection: ID, namespace: Namespace.ID, @ViewBuilder content: @escaping (ID) -> Label) {
        self.ids = ids
        self.selection = selection
        self.namespace = namespace
        self.content = content
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ids, id: \.self) { id in
                content(id)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background {
                        if id == selection {
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.72))
                                .overlay(Capsule(style: .continuous).strokeBorder(Aurora.brand.opacity(0.28), lineWidth: 0.8))
                                .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 2)
                                .matchedGeometryEffect(id: "pill", in: namespace)
                        }
                    }
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.045)))
        .animation(Motion.snappy, value: selection)
    }
}

/// Frosted empty-state block with a soft gradient glyph.
struct EmptyStateCard: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Aurora.signature.opacity(0.16))
                    .frame(width: 74, height: 74)
                    .blur(radius: 0.5)
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Aurora.signature)
            }
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Aurora.brand)
                    .buttonStyle(PressableStyle())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.36), lineWidth: 0.8))
        )
        .padding(20)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

extension View {
    /// Frosted panel background.
    func glassPanel(radius: CGFloat = 18, borderOpacity: Double = 0.42) -> some View {
        modifier(Aurora.GlassPanel(radius: radius, borderOpacity: borderOpacity))
    }

    /// Large opaque card surface with hairline border.
    func cardSurface(radius: CGFloat = 18, opacity: Double = 0.94) -> some View {
        modifier(Aurora.CardSurface(radius: radius, opacity: opacity))
    }

    /// Hover lift for interactive cards.
    func hoverLift(scale: CGFloat = 1.004, shadowRadius: CGFloat = 10) -> some View {
        modifier(HoverLift(scale: scale, shadowRadius: shadowRadius))
    }
}
