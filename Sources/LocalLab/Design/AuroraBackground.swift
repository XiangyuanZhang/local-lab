import SwiftUI

/// The aurora wash behind the whole workspace, derived from the reference
/// design's canvas: sky blue in one corner, cream in another and a coral /
/// periwinkle glow that slowly overlaps.
///
/// Everything is tunable from Settings › 外觀: the pace (still, slow, standard,
/// brisk), the intensity and the accent colour that joins the blooms. It never
/// intercepts clicks, stops when the window is inactive, and stops entirely
/// when Reduce Motion is on.
struct AuroraBackground: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    private var shouldMove: Bool {
        appearance.pace != .still && !reduceMotion && activeState != .inactive
    }

    private var intensity: Double { appearance.intensity }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if shouldMove {
                    // 8 fps is plenty for very slow, heavily blurred blooms and
                    // keeps the window from redrawing 60 times a second.
                    TimelineView(.periodic(from: .now, by: 0.12)) { context in
                        canvas(size: proxy.size, phase: phase(at: context.date))
                    }
                } else {
                    canvas(size: proxy.size, phase: 0.5)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 0…1 along the drift; one there-and-back cycle per pace duration.
    private func phase(at date: Date) -> Double {
        let duration = max(1, appearance.pace.duration)
        let cycle = duration * 2
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        return 0.5 - 0.5 * cos(t * 2 * .pi)
    }

    private func canvas(size: CGSize, phase: Double) -> some View {
        let w = size.width
        let h = size.height
        let unit = max(w, h)
        func mix(_ from: Double, _ to: Double) -> Double { from + (to - from) * phase }

        return ZStack {
            // Base canvas: blue → lavender → coral → periwinkle.
            Aurora.canvas

            // Cream bloom in the top-right corner (the pale warmth from the
            // reference onboarding screen).
            glow(color: Aurora.cream, diameter: unit * 0.72, strength: 0.30 * intensity)
                .position(x: w * mix(0.78, 0.86), y: h * mix(0.18, 0.10))

            // Coral bloom rising from the bottom edge.
            glow(color: Aurora.coral, diameter: unit * 0.92, strength: 0.42 * intensity)
                .position(x: w * mix(0.38, 0.30), y: h * mix(0.86, 0.96))

            // Periwinkle bloom on the right.
            glow(color: Aurora.periwinkle, diameter: unit * 1.05, strength: 0.52 * intensity)
                .position(x: w * mix(0.92, 0.98), y: h * mix(0.66, 0.58))

            // A cool sky highlight keeps the centre from muddying.
            glow(color: Aurora.sky, diameter: unit * 1.0, strength: 0.50 * intensity)
                .position(x: w * mix(0.52, 0.42), y: h * mix(0.10, 0.20))

            // The chosen accent joins the wash so the whole window follows it.
            glow(color: appearance.accent.color, diameter: unit * 0.62, strength: 0.30 * intensity)
                .position(x: w * mix(0.60, 0.70), y: h * mix(0.62, 0.72))

            // Soft vignette for depth.
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.10)],
                center: .center,
                startRadius: unit * 0.26,
                endRadius: unit * 0.80
            )
        }
        .scaleEffect(1 + 0.02 * phase)
    }

    private func glow(color: Color, diameter: CGFloat, strength: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(strength), color.opacity(strength * 0.34), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .blendMode(.softLight)
    }
}

/// Wraps either the user's own background photo or the generated aurora, so
/// ContentView has one background to reason about.
struct WorkspaceBackdrop: View {
    @ObservedObject var store: BackgroundStore

    var body: some View {
        ZStack {
            if store.image != nil {
                WorkspaceBackground(store: store)
                    .transition(.opacity)
            } else {
                AuroraBackground()
                    .transition(.opacity)
            }
        }
        .animation(Motion.gentle, value: store.image != nil)
    }
}
