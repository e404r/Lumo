import SwiftUI

/// Living Google Gemini AI Star Companion ("Lumo Star")
/// A sentient 4-pointed celestial star with expressive, blinking eyes,
/// blush cheeks, breathing physics, and state-reactive emotions.
struct GeminiCoreView: View {
    @ObservedObject var state: AppState
    let diameter: CGFloat

    // Animation states
    @State private var floatY: CGFloat = 0.0
    @State private var breatheScale: CGFloat = 1.0
    @State private var lookOffsetX: CGFloat = 0.0
    @State private var lookOffsetY: CGFloat = 0.0
    @State private var sparkleRotation: Double = 0.0
    @State private var haloPulse: CGFloat = 1.0
    @State private var isBlinking = false

    // Star hand-waving interaction state
    @State private var isWaving = false
    @State private var waveAngle: Double = 0.0
    @State private var armWaveOffset: CGFloat = 0.0
    @State private var isHappyGreeting = false

    // Thinking dynamic color shift
    @State private var thinkingHue: Double = 0.0

    private var botState: BotState {
        state.effectiveState
    }

    private var starGradientColors: [Color] {
        switch botState {
        case .working:
            return [Color(hex: "#38BDF8"), Color(hex: "#2563EB"), Color(hex: "#4F46E5")]
        case .thinking:
            return [Color(hex: "#A855F7"), Color(hex: "#6366F1"), Color(hex: "#EC4899")]
        case .searching:
            return [Color(hex: "#22D3EE"), Color(hex: "#3B82F6"), Color(hex: "#8B5CF6")]
        case .approval:
            return [Color(hex: "#FBBF24"), Color(hex: "#F59E0B"), Color(hex: "#EF4444")]
        case .finished:
            return [Color(hex: "#34D399"), Color(hex: "#10B981"), Color(hex: "#06B6D4")]
        case .error:
            return [Color(hex: "#F87171"), Color(hex: "#EF4444"), Color(hex: "#991B1B")]
        default:
            return [Color(hex: "#38BDF8"), Color(hex: "#3B82F6"), Color(hex: "#8B5CF6")]
        }
    }

    var body: some View {
        ZStack {
            // 1. Ambient Glow Aura (Soft celestial shimmer)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            starGradientColors[0].opacity(0.22),
                            starGradientColors[1].opacity(0.06),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: diameter * 0.65
                    )
                )
                .frame(width: diameter * 1.25, height: diameter * 1.25)
                .scaleEffect(haloPulse * (botState == .thinking ? 1.1 : 1.0))
                .hueRotation(.degrees(botState == .thinking ? thinkingHue : 0))

            // 2. Celestial Orbital Rings & Floating Sparkles
            ZStack {
                // Orbiting micro sparkles
                ForEach(0..<4, id: \.self) { i in
                    let angle = Double(i) * 90.0 + sparkleRotation
                    let rad = angle * .pi / 180.0
                    let dist = diameter * 0.50
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 3.5, height: 3.5)
                        .shadow(color: starGradientColors[0], radius: 3)
                        .offset(x: cos(rad) * dist, y: sin(rad) * dist)
                }

                // Tilted 3D Orbit Ring
                Ellipse()
                    .stroke(
                        LinearGradient(
                            colors: [starGradientColors[0].opacity(0.65), Color.clear, starGradientColors[2].opacity(0.65)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.2
                    )
                    .frame(width: diameter * 1.08, height: diameter * 0.40)
                    .rotation3DEffect(.degrees(62), axis: (x: 1, y: 0.2, z: 0))
                    .rotationEffect(.degrees(sparkleRotation * 0.6))
            }

            // 3. The 4-Pointed Star Character Body
            ZStack {
                // Star Body with Rich Cyberpunk Gradient
                GeminiSparkleShape()
                    .fill(
                        LinearGradient(
                            colors: starGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: diameter * 0.90, height: diameter * 0.90)
                    .shadow(color: starGradientColors[0].opacity(0.55), radius: 10, x: 0, y: 3)

                // Specular Glass Inner Rim
                GeminiSparkleShape()
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.75), location: 0),
                                .init(color: Color.white.opacity(0.2), location: 0.4),
                                .init(color: Color.clear, location: 0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: diameter * 0.89, height: diameter * 0.89)

                // 4. Character Face (Eyes & Blushes)
                VStack(spacing: 3) {
                    // Eyes Row
                    HStack(spacing: diameter * 0.17) {
                        EyeView(
                            botState: botState,
                            isBlinking: isBlinking,
                            isSighing: state.isSighing,
                            isHappyGreeting: isHappyGreeting || state.isStarWaving,
                            lookX: lookOffsetX,
                            lookY: lookOffsetY,
                            eyeSize: diameter * 0.13
                        )
                        EyeView(
                            botState: botState,
                            isBlinking: isBlinking,
                            isSighing: state.isSighing,
                            isHappyGreeting: isHappyGreeting || state.isStarWaving,
                            lookX: lookOffsetX,
                            lookY: lookOffsetY,
                            eyeSize: diameter * 0.13
                        )
                    }

                    // Soft Glowing Cheeks Blush Row
                    HStack(spacing: diameter * 0.28) {
                        Circle()
                            .fill(Color(hex: "#F472B6").opacity((isHappyGreeting || state.isStarWaving || botState == .finished) ? 0.95 : (state.isSighing ? 0.7 : 0.45)))
                            .frame(width: diameter * 0.09, height: diameter * 0.055)
                        Circle()
                            .fill(Color(hex: "#F472B6").opacity((isHappyGreeting || state.isStarWaving || botState == .finished) ? 0.95 : (state.isSighing ? 0.7 : 0.45)))
                            .frame(width: diameter * 0.09, height: diameter * 0.055)
                    }
                }
                .offset(y: diameter * 0.02)

                // 5. Cute Sigh Exhale Puff (Long Thinking)
                if state.isSighing {
                    HStack(spacing: 3) {
                        Text("~ sigh")
                            .font(.system(size: max(8, diameter * 0.15), weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#F1F5F9"))
                        Text("💨")
                            .font(.system(size: max(7, diameter * 0.14)))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#090B10").opacity(0.85))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                    .offset(y: -diameter * 0.65)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .scaleEffect(breatheScale)
            .rotationEffect(.degrees(waveAngle))
            .offset(y: floatY + (state.isSighing ? 4.0 : 0.0))
            .hueRotation(.degrees(botState == .thinking ? thinkingHue : 0))
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            startLivingAnimations()
            if botState == .thinking {
                withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
                    thinkingHue = 360
                }
            }
        }
        .onChange(of: botState) { _, newState in
            if newState == .thinking {
                withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
                    thinkingHue = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    thinkingHue = 0
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .starWaveRequested)) { _ in
            triggerWave()
        }
        .onChange(of: state.isStarWaving) { _, waving in
            if waving && !isWaving {
                triggerWave()
            }
        }
    }

    func triggerWave() {
        guard !isWaving else { return }
        isWaving = true
        isHappyGreeting = true
        SoundEngine.shared.play("wink")

        // Playful tilt and wave:
        // Lean slightly left, then wave right point like an arm!
        withAnimation(.spring(response: 0.10, dampingFraction: 0.5)) {
            waveAngle = -16
            armWaveOffset = 8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            withAnimation(.spring(response: 0.10, dampingFraction: 0.5)) {
                waveAngle = 14
                armWaveOffset = -6
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.10, dampingFraction: 0.5)) {
                waveAngle = -12
                armWaveOffset = 8
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) {
            withAnimation(.spring(response: 0.12, dampingFraction: 0.5)) {
                waveAngle = 10
                armWaveOffset = -4
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.65)) {
                waveAngle = 0
                armWaveOffset = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.2)) {
                isWaving = false
                isHappyGreeting = false
                state.isStarWaving = false
            }
        }
    }

    private func startLivingAnimations() {
        // Floating / Bobbing
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            floatY = -3.5
        }
        // Breathing
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            breatheScale = 1.05
            haloPulse = 1.15
        }
        // Continuous sparkle orbit
        withAnimation(.linear(duration: 11.0).repeatForever(autoreverses: false)) {
            sparkleRotation = 360
        }

        // Natural Random Blinking & Eye Glances
        Timer.scheduledTimer(withTimeInterval: 3.2, repeats: true) { _ in
            Task { @MainActor in
                triggerBlink()
                // Random curious glance
                if Double.random(in: 0...1) > 0.35 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        lookOffsetX = CGFloat.random(in: -2.0...2.0)
                        lookOffsetY = CGFloat.random(in: -1.2...1.2)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            lookOffsetX = 0
                            lookOffsetY = 0
                        }
                    }
                }
            }
        }
    }

    private func triggerBlink() {
        guard !isBlinking else { return }
        withAnimation(.easeIn(duration: 0.09)) {
            isBlinking = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.11)) {
                isBlinking = false
            }
        }
    }
}

// MARK: - Expressive Eye Component

struct EyeView: View {
    let botState: BotState
    let isBlinking: Bool
    var isSighing: Bool = false
    var isHappyGreeting: Bool = false
    let lookX: CGFloat
    let lookY: CGFloat
    let eyeSize: CGFloat

    var body: some View {
        Group {
            if isBlinking || isSighing {
                // Weary sigh or closed eyelid line
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: "#090B12"))
                    .frame(width: eyeSize * 1.05, height: 2.2)
                    .rotationEffect(.degrees(isSighing ? 6 : 0))
            } else if isHappyGreeting || botState == .finished {
                // Happy smiling crescent: ^
                HappyEyeArc()
                    .stroke(Color(hex: "#090B12"), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: eyeSize * 1.1, height: eyeSize * 0.65)
            } else {
                switch botState {

                case .approval:
                    // Pleading sparkly eye
                    ZStack {
                        Capsule()
                            .fill(Color(hex: "#0A0D16"))
                            .frame(width: eyeSize * 1.15, height: eyeSize * 1.35)
                        Circle()
                            .fill(Color.white)
                            .frame(width: eyeSize * 0.48, height: eyeSize * 0.48)
                            .offset(x: -eyeSize * 0.16 + lookX * 0.3, y: -eyeSize * 0.22 + lookY * 0.3)
                        Circle()
                            .fill(Color(hex: "#FCD34D"))
                            .frame(width: eyeSize * 0.26, height: eyeSize * 0.26)
                            .offset(x: eyeSize * 0.18 + lookX * 0.3, y: eyeSize * 0.25 + lookY * 0.3)
                    }

                case .error:
                    // > < eyes
                    Text("✕")
                        .font(.system(size: eyeSize * 1.0, weight: .bold))
                        .foregroundColor(Color(hex: "#090B12"))

                default:
                    // Cute glossy anime / Pixar eye
                    ZStack {
                        Capsule()
                            .fill(Color(hex: "#080A10"))
                            .frame(width: eyeSize, height: eyeSize * 1.35)

                        // Main bright specular catchlight
                        Circle()
                            .fill(Color.white)
                            .frame(width: eyeSize * 0.44, height: eyeSize * 0.44)
                            .offset(x: -eyeSize * 0.14 + lookX * 0.35, y: -eyeSize * 0.22 + lookY * 0.35)

                        // Secondary tiny sparkle catchlight
                        Circle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: eyeSize * 0.22, height: eyeSize * 0.22)
                            .offset(x: eyeSize * 0.16 + lookX * 0.35, y: eyeSize * 0.22 + lookY * 0.35)
                    }
                }
            }
        }
        .frame(width: eyeSize, height: eyeSize * 1.4)
    }
}

/// Happy crescent eye arc for smiling ^ ^
struct HappyEyeArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        return path
    }
}

/// 4-pointed Gemini Sparkle Shape with smooth concave curves
struct GeminiSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY

        // Top point
        path.move(to: CGPoint(x: cx, y: 0))
        // Top to Right (concave curve towards center)
        path.addQuadCurve(to: CGPoint(x: w, y: cy), control: CGPoint(x: cx + w * 0.12, y: cy - h * 0.12))
        // Right to Bottom
        path.addQuadCurve(to: CGPoint(x: cx, y: h), control: CGPoint(x: cx + w * 0.12, y: cy + h * 0.12))
        // Bottom to Left
        path.addQuadCurve(to: CGPoint(x: 0, y: cy), control: CGPoint(x: cx - w * 0.12, y: cy + h * 0.12))
        // Left to Top
        path.addQuadCurve(to: CGPoint(x: cx, y: 0), control: CGPoint(x: cx - w * 0.12, y: cy - h * 0.12))
        path.closeSubpath()

        return path
    }
}
