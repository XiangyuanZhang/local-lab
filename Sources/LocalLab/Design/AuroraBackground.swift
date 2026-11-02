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
    @State private var drifting = false

    private var shouldMove: Bool {
        appearance.pace != .still && !reduceMotion && activeState != .inactive
    }

    private var intensity: Double { appearance.intensity }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let unit = max(w, h)

            ZStack {
                // Base canvas: blue → lavender → coral → periwinkle.
                Aurora.canvas

                // Cream bloom in the top-right corner (the pale warmth from the
                // reference onboarding screen).
                glow(color: Aurora.cream, diameter: unit * 0.72, strength: 0.30 * intensity)
                    .position(x: w * (drifting ? 0.86 : 0.78), y: h * (drifting ? 0.10 : 0.18))

                // Coral bloom rising from the bottom edge.
                glow(color: Aurora.coral, diameter: unit * 0.92, strength: 0.42 * intensity)
                    .position(x: w * (drifting ? 0.30 : 0.38), y: h * (drifting ? 0.96 : 0.86))

                // Periwinkle bloom on the right.
                glow(color: Aurora.periwinkle, diameter: unit * 1.05, strength: 0.52 * intensity)
                    .position(x: w * (drifting ? 0.98 : 0.92), y: h * (drifting ? 0.58 : 0.66))

                // A cool sky highlight keeps the centre from muddying.
                glow(color: Aurora.sky, diameter: unit * 1.0, strength: 0.50 * intensity)
                    .position(x: w * (drifting ? 0.42 : 0.52), y: h * (drifting ? 0.20 : 0.10))

                // The chosen accent joins the wash so the whole window follows it.
                glow(color: appearance.accent.color, diameter: unit * 0.62, strength: 0.30 * intensity)
                    .position(x: w * (drifting ? 0.70 : 0.60), y: h * (drifting ? 0.72 : 0.62))

                // Soft vignette for depth.
                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.10)],
                    center: .center,
                    startRadius: unit * 0.26,
                    endRadius: unit * 0.80
                )
            }
            .scaleEffect(drifting ? 1.02 : 1.0)
            .animation(driftAnimation, value: drifting)
            .onAppear { drifting = shouldMove }
            .onChange(of: shouldMove) { _, canMove in
                if canMove { drifting.toggle() }
            }
            .onChange(of: appearance.pace) { _, _ in
                guard shouldMove else { return }
                drifting.toggle()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var driftAnimation: Animation? {
        guard shouldMove else { return nil }
        return .easeInOut(duration: appearance.pace.duration).repeatForever(autoreverses: true)
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
