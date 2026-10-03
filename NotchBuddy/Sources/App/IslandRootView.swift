import SwiftUI

/// Top-level SwiftUI view rendered inside the 720×320 transparent panel.
/// The island is drawn at the top-center; everything else is transparent and click-through.
/// Note: drag-drop is handled at the AppKit level in IslandWindowController (FileDropNSView),
/// not in SwiftUI, to avoid interfering with SwiftUI hit-testing.
struct IslandRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            IslandContainer(state: state)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Island container

struct IslandContainer: View {
    @ObservedObject var state: AppState
    @State private var islandWidth:  CGFloat = IslandConst.notchWidth
    @State private var islandHeight: CGFloat = IslandConst.notchHeight
    @State private var cornerRadius: CGFloat = IslandConst.roundedCorner
    // topRadius > 0 → convex expanded corners; < 0 → concave ear cutouts
    @State private var islandTopRadius: CGFloat = 0
    @State private var greetNotif: Bool = false

    private let openSpring = Animation.spring(response: 0.5, dampingFraction: 0.72)
    private let closeEase  = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)

    private var chatPromptHeight: CGFloat {
        let base: CGFloat = 260
        let perMsg: CGFloat = 40
        return min(340, base + CGFloat(state.chatHistory.count) * perMsg)
    }

    /// Pixels the content must be pushed down to clear the concave ear transparent area.
    /// = 0 in expanded mode (no ears), = earRadius in compact/notch mode.
    private var earOffset: CGFloat { max(0, -islandTopRadius) }

    var body: some View {
        // Canvas active during drag-over (.upload), post-drop animation (.uploading),
        // AND choose overlay (.choose) — canvas handles the full sequence through user action.
        // Engine deactivates when user clicks a canvas choose button or navigates away.
        let uploadActive = state.mode == .expanded
            && UploadSequenceEngine.shared.isActive
            && (state.view == .upload || state.view == .uploading || state.view == .choose)

        let greetingActive = state.mode == .expanded && state.view == .greeting

        return ZStack(alignment: .topLeading) {
            // Apple Cyberpunk / Dark Glass Island foundation
            IslandShape(width: islandWidth, height: islandHeight,
                        cornerRadius: cornerRadius, topRadius: islandTopRadius)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#0C0E15"), Color(hex: "#06070A")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    IslandShape(width: islandWidth, height: islandHeight,
                                cornerRadius: cornerRadius, topRadius: islandTopRadius)
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.18), location: 0),
                                    .init(color: Color(hex: "#38BDF8").opacity(0.15), location: 0.3),
                                    .init(color: Color(hex: "#818CF8").opacity(0.10), location: 0.7),
                                    .init(color: Color.white.opacity(0.04), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color(hex: "#2563EB").opacity(state.mode == .expanded ? 0.22 : 0.05), radius: 24, x: 0, y: 8)

            // Content
            if state.mode == .expanded {
                if uploadActive {
                    ZStack(alignment: .topLeading) {
                        UploadCanvasView(state: state)
                            .frame(width: islandWidth, height: islandHeight)
                            .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                                  cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        // Header overlaid: canvas CARD_Y=42 aligns exactly with header bottom,
                        // matching normal view proportions (8pt top + 34pt header + card + 10pt bottom).
                        IslandHeader(state: state)
                            .frame(width: islandWidth, height: 28)
                            .offset(y: 10)
                    }
                    .transition(.opacity)
                } else {
                    IslandContentView(state: state)
                        .frame(width: islandWidth, height: islandHeight - earOffset, alignment: .top)
                        .offset(y: earOffset)
                        .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                              cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
                }
            }

            // Single BotPlacement — always alive in the view tree
            BotPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                .opacity(uploadActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: uploadActive)

            CountdownBar(state: state, islandW: islandWidth)

            Group {
                if state.mode == .compact {
                    CompactMiniGrid(state: state)
                        .position(x: 24, y: islandHeight / 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: state.mode == .compact)
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            if state.mode != .expanded {
                SoundEngine.shared.play("open")
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                    NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
                }
            }
        }
        .onChange(of: state.mode) { oldMode, newMode in
            let shrinking = modeOrder(newMode) < modeOrder(oldMode)
            let anim = shrinking ? closeEase : openSpring
            let (w, h) = islandSize(mode: newMode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            let cr  = newMode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            let tr: CGFloat = 0
            withAnimation(anim) {
                islandWidth      = w
                islandHeight     = (newMode == .expanded && state.view == .prompt) ? chatPromptHeight : h
                cornerRadius     = cr
                islandTopRadius  = tr
            }
        }
        .onChange(of: state.view) { _, newView in
            guard state.mode == .expanded else { return }
            // Deactivate engine if user navigates outside the upload flow
            let uploadViews: Set<IslandView> = [.upload, .uploading, .choose]
            if UploadSequenceEngine.shared.isActive && !uploadViews.contains(newView) {
                UploadSequenceEngine.shared.deactivate()
            }
            let (w, h) = islandSize(mode: .expanded, view: newView,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            withAnimation(openSpring) {
                islandWidth  = w
                islandHeight = newView == .prompt ? chatPromptHeight : h
            }
        }
        .onChange(of: state.chatHistory.count) { _, _ in
            guard state.mode == .expanded, state.view == .prompt else { return }
            withAnimation(openSpring) { islandHeight = chatPromptHeight }
        }
        .onAppear {
            let (w, h) = islandSize(mode: state.mode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            islandWidth      = w
            islandHeight     = state.view == .prompt ? chatPromptHeight : h
            cornerRadius     = state.mode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            islandTopRadius  = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            greetNotif.toggle()
        }
    }

    private func modeOrder(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }
}

// MARK: - Island shape
//
// topRadius > 0  → convex rounded top corners (expanded mode)
// topRadius < 0  → concave ear cutouts, |topRadius| = ear radius (compact/notch mode)
// topRadius = 0  → sharp top corners (transient during animation)

struct IslandShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat   // bottom corners
    var topRadius: CGFloat      // see above

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>, CGFloat> {
        get { .init(.init(.init(width, height), cornerRadius), topRadius) }
        set {
            width        = newValue.first.first.first
            height       = newValue.first.first.second
            cornerRadius = newValue.first.second
            topRadius    = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let cr = max(0, cornerRadius)
        var p  = Path()

        if topRadius >= 0 {
            // ── Convex rounded top corners (expanded) ──────────────────────────
            let tr = min(topRadius, min(width / 2, height / 2))
            p.move(to: CGPoint(x: tr, y: 0))
            p.addLine(to: CGPoint(x: width - tr, y: 0))
            // Top-right convex corner
            p.addArc(center: CGPoint(x: width - tr, y: tr), radius: tr,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge
            p.addLine(to: CGPoint(x: 0, y: tr))
            // Top-left convex corner
            p.addArc(center: CGPoint(x: tr, y: tr), radius: tr,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // ── Concave ear cutouts (compact / notch) ─────────────────────────
            let er = -topRadius   // positive ear radius
            p.move(to: CGPoint(x: 0, y: 0))
            // Top-left ear
            p.addArc(center: CGPoint(x: 0, y: er), radius: er,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Top edge
            p.addLine(to: CGPoint(x: width - er, y: er))
            // Top-right ear
            p.addArc(center: CGPoint(x: width, y: er), radius: er,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge back to top-left corner
            p.addLine(to: CGPoint(x: 0, y: 0))
        }

        p.closeSubpath()
        return p
    }
}

// MARK: - Bot placement helper (Gemini 3D Glowing Core with Thinking Patrol Orbit)

struct BotPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    @State private var thinkingStartTime: Date? = nil
    @State private var lastSighTime: Date = .distantPast

    private var isThinking: Bool {
        state.effectiveState == .thinking || state.stateOverride == .thinking
    }

    var body: some View {
        TimelineView(.animation(paused: !isThinking)) { timeline in
            let (targetX, targetY, diameter, opacity) = computePosition()

            ZStack {
                // When thinking: Stardust particles glowing behind the star
                if isThinking {
                    ThinkingStardustTrail(centerX: targetX, centerY: targetY, diameter: diameter)
                }

                GeminiCoreView(state: state, diameter: diameter)
                    .opacity(state.isDraggingBot ? 0 : opacity)
                    .position(x: targetX, y: targetY)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: state.isPeekingUp)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: isThinking)
                    .allowsHitTesting(false)
            }
            .onChange(of: isThinking) { _, thinking in
                if thinking {
                    thinkingStartTime = Date()
                } else {
                    thinkingStartTime = nil
                    state.isSighing = false
                }
            }
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                checkSigh()
            }
        }
    }

    private func checkSigh() {
        guard isThinking, let start = thinkingStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        // If thinking takes longer than 8.5 seconds and hasn't sighed in the last 12 seconds
        if elapsed >= 8.5 && Date().timeIntervalSince(lastSighTime) >= 12.0 {
            lastSighTime = Date()
            state.isSighing = true
            SoundEngine.shared.play("yawn")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if self.isThinking {
                    self.state.isSighing = false
                }
            }
        }
    }

    private func computePosition() -> (CGFloat, CGFloat, CGFloat, Double) {
        return botPosition(
            mode: state.mode, view: state.view,
            islandW: islandW, islandH: islandH,
            uploadProgress: state.uploadProgress, notchH: state.notchHeight,
            isPeekingUp: state.isPeekingUp
        )
    }
}

struct ThinkingStardustTrail: View {
    let centerX: CGFloat
    let centerY: CGFloat
    let diameter: CGFloat

    var body: some View {
        ZStack {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "#C084FC").opacity(0.35 / Double(i)), Color.clear],
                            center: .center,
                            startRadius: 1,
                            endRadius: diameter * 0.75
                        )
                    )
                    .frame(width: diameter * 1.5, height: diameter * 1.5)
                    .position(x: centerX, y: centerY)
                    .scaleEffect(1.0 + CGFloat(i) * 0.15)
            }
        }
    }
}

func botPosition(mode: IslandMode, view: IslandView, islandW: CGFloat, islandH: CGFloat, uploadProgress: Double, notchH: CGFloat = IslandConst.notchHeight, isPeekingUp: Bool = false) -> (CGFloat, CGFloat, CGFloat, Double) {
    switch mode {
    case .hidden:
        return (islandW - 20, 16, 6, 0)
    case .compact:
        let cx = islandW - 20
        let cy: CGFloat = isPeekingUp ? 18 : 14
        return (cx, cy, 22, 1)
    case .expanded:
        let layout = IslandConst.viewLayouts[view]!
        let diameter = layout.botDiameter
        if view == .uploading {
            let cx = 36 + CGFloat(uploadProgress) * 526
            return (cx, layout.botY ?? 110, diameter, 1)
        }
        let cx = layout.botX
        let cy: CGFloat
        if let fixedY = layout.botY {
            cy = fixedY
        } else {
            let cardTop: CGFloat = 10 + 28 + 8
            let cardH: CGFloat = 104
            cy = cardTop + cardH / 2
        }
        return (cx, cy, diameter, 1)
    }
}

// MARK: - Countdown bar

struct CountdownBar: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    @State private var barWidth: CGFloat = 0
    @State private var timer: Timer? = nil

    var body: some View {
        GeometryReader { _ in
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: barWidth, height: 2)
                .cornerRadius(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateBar()
        }
    }

    private func updateBar() {
        guard state.mode == .expanded && !state.isPinned else {
            barWidth = 0
            return
        }
        let autoClose = state.autoCloseInterval
        let window = min(10.0, autoClose * 0.6)
        let elapsed = Date.now.timeIntervalSince(state.lastActivity)
        let remaining = autoClose - elapsed
        if remaining <= 0 {
            barWidth = 0
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
            return
        }
        if remaining < window {
            barWidth = max(0, CGFloat(remaining / window) * 160)
        } else {
            barWidth = 0
        }
    }
}

// MARK: - Island content (header + views, only in expanded mode)

struct IslandContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 8) {
            IslandHeader(state: state)
                .frame(height: 28)
                .opacity((state.view == .confused || state.view == .greeting) ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: state.view)

            ZStack(alignment: .top) {
                ForEach(IslandView.allCases, id: \.self) { v in
                    let active = state.view == v
                    let isTall = active && (v == .prompt || v == .mail)
                    let anim: Animation = active
                        ? .spring(response: 0.4, dampingFraction: 0.8).delay(0.16)
                        : .easeIn(duration: 0.16)
                    IslandViewContent(view: v, state: state)
                        .frame(maxWidth: .infinity)
                        .frame(height: isTall ? nil : 104)
                        .frame(maxHeight: isTall ? .infinity : nil)
                        .opacity(active ? 1 : 0)
                        .scaleEffect(active ? 1 : 0.97)
                        .allowsHitTesting(active)
                        .animation(anim, value: state.view)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 10)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .foregroundColor(Color(hex: "#F5F6F8"))
    }
}

// MARK: - Island header (tabs + icons)

struct IslandHeader: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Left: tab capsules
            HStack(spacing: 6) {
                TabButton(icon: "house.fill", view: .overview, state: state)
                TabButton(icon: "bubble.left.and.bubble.right.fill", view: .prompt, state: state, preAction: {
                    #if !APPSTORE
                    if state.promptContext == nil {
                        state.promptContext = WindowContextCapture.captureActive(from: state.lastExternalApp)
                    }
                    #endif
                })
            }
            .padding(.leading, 14)

            Spacer()

            // Right: action icons
            HStack(spacing: 10) {
                Button(action: {
                    state.lastActivity = .now
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        state.view = .settings
                    }
                }) {
                    Image(systemName: state.view == .settings ? "gearshape.fill" : "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(state.view == .settings ? Color(hex: "#38BDF8") : Color(hex: "#8E939C"))
                        .frame(width: 26, height: 26)
                        .background(state.view == .settings ? Color(hex: "#38BDF8").opacity(0.15) : Color.white.opacity(0.04))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(state.view == .settings ? Color(hex: "#38BDF8").opacity(0.3) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: {
                    state.lastActivity = .now
                    state.soundEnabled.toggle()
                }) {
                    Image(systemName: state.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(state.soundEnabled ? Color(hex: "#818CF8") : Color(hex: "#6B7280"))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 16)
        }
        .frame(maxHeight: .infinity)
    }

}

struct TabButton: View {
    let icon: String
    let view: IslandView
    @ObservedObject var state: AppState
    var preAction: (() -> Void)? = nil
    @State private var isHovered = false

    private var isOn: Bool {
        if view == .overview { return state.view == .overview || state.view == .empty }
        return state.view == view
    }

    var body: some View {
        Button(action: {
            preAction?()
            state.lastActivity = .now
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.view = view
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isOn ? Color.white : (isHovered ? Color(hex: "#E2E8F0") : Color(hex: "#8E939C")))
                .frame(width: 32, height: 24)
                .background(
                    ZStack {
                        if isOn {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#2563EB").opacity(0.4), Color(hex: "#4F46E5").opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Capsule()
                                .stroke(Color(hex: "#38BDF8").opacity(0.45), lineWidth: 1)
                        } else if isHovered {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        }
                    }
                )
                .clipShape(Capsule())
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact mini mochi grid (2×2 to the right of the notch)

struct CompactMiniGrid: View {
    @ObservedObject var state: AppState

    private var others: [AgentTask] {
        Array(state.tasks.filter { $0.id != state.focusId }.prefix(4))
    }

    var body: some View {
        if others.isEmpty {
            EmptyView()
        } else {
            let cols = [GridItem(.fixed(12), spacing: 4), GridItem(.fixed(12), spacing: 4)]
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(others) { task in
                    Circle()
                        .fill(Color(hex: task.color))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 28, height: 28)
        }
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8)  & 0xFF) / 255
        let b = Double( val        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
