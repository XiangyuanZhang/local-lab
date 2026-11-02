import SwiftUI

/// The aurora wash behind the whole workspace, derived from the reference
/// design's canvas: sky blue in one corner, cream in another and a coral /
/// periwinkle glow that slowly overlaps. It never intercepts clicks and it
/// stops moving when the window is inactive, when Reduce Motion is on, or when
/// the user turns "Aurora motion" off in Settings.
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @AppStorage("auroraMotion") private var motionEnabled = true
    @State private var drifting = false

    private var shouldMove: Bool {
        motionEnabled && !reduceMotion && activeState != .inactive
    }

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
                glow(color: Aurora.cream, diameter: unit * 0.72, strength: 0.30)
                    .position(x: w * (drifting ? 0.86 : 0.78), y: h * (drifting ? 0.10 : 0.18))

                // Coral bloom rising from the bottom edge.
                glow(color: Aurora.coral, diameter: unit * 0.92, strength: 0.42)
                    .position(x: w * (drifting ? 0.30 : 0.38), y: h * (drifting ? 0.96 : 0.86))

                // Periwinkle bloom on the right.
                glow(color: Aurora.periwinkle, diameter: unit * 1.05, strength: 0.52)
                    .position(x: w * (drifting ? 0.98 : 0.92), y: h * (drifting ? 0.58 : 0.66))

                // A cool sky highlight keeps the centre from muddying.
                glow(color: Aurora.sky, diameter: unit * 1.0, strength: 0.50)
                    .position(x: w * (drifting ? 0.42 : 0.52), y: h * (drifting ? 0.20 : 0.10))

                // Soft vignette for depth.
                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.10)],
                    center: .center,
                    startRadius: unit * 0.26,
                    endRadius: unit * 0.80
                )
            }
            .animation(shouldMove ? .easeInOut(duration: 26).repeatForever(autoreverses: true) : nil, value: drifting)
            .onAppear { drifting = shouldMove }
            .onChange(of: shouldMove) { _, canMove in
                if canMove { drifting.toggle() }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
