import SwiftUI
import AppKit

// MARK: - Gemini Cosmic File Drop & Upload Canvas
// Fully converted to Google Antigravity / Gemini Star design system.
// Replaces the legacy Mochi character with the living Gemini Star,
// celestial cosmic gradients, animated stardust particles, and Antigravity styling.

struct UploadCanvasView: View {
    @ObservedObject var state: AppState
    @State private var fileIcon: NSImage? = nil

    private var engine: UploadSequenceEngine { .shared }

    var body: some View {
        TimelineView(.animation) { tl in
            let f = engine.frame(at: tl.date)
            let wallTime = tl.date.timeIntervalSinceReferenceDate

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    drawScene(ctx: ctx, f: f, wallTime: wallTime)
                }
                .frame(width: 640, height: 172)

                // Interactive choose buttons (overlayed over canvas at completion)
                if f.chooseAlpha > 0 {
                    chooseOverlay(f: f)
                        .frame(width: 640, height: 172)
                }
            }
        }
        .onChange(of: state.droppedFile?.url) { _, url in
            if let url { loadIcon(url: url) }
        }
        .onAppear {
            if let url = state.droppedFile?.url { loadIcon(url: url) }
        }
        .frame(width: 640, height: 172)
    }

    // MARK: - File Icon Helper

    private func loadIcon(url: URL) {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 64, height: 64)
        fileIcon = img
    }

    // MARK: - Choose Overlay (Interactive Gemini Action Buttons)

    @ViewBuilder
    private func chooseOverlay(f: USFrame) -> some View {
        ZStack(alignment: .topLeading) {
            // Primary Action: "Ask Gemini"
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    state.view = .prompt
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    UploadSequenceEngine.shared.deactivate()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Ask Gemini")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(width: 148, height: 28)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#2563EB"), Color(hex: "#4F46E5")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                .shadow(color: Color(hex: "#2563EB").opacity(0.4), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .position(x: 120 + 74, y: 114 + 14)

            // Secondary Action: "Done"
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    state.view = .overview
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    UploadSequenceEngine.shared.deactivate()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .bold))
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(Color(hex: "#E2E8F0"))
                .frame(width: 86, height: 28)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .position(x: 280 + 43, y: 114 + 14)
        }
        .opacity(f.chooseAlpha)
        .allowsHitTesting(f.chooseAlpha > 0.5)
    }

    // MARK: - Scene Drawing

    private func drawScene(ctx: GraphicsContext, f: USFrame, wallTime: Double = 0) {
        var c = ctx

        // 1. Island Container Background (Obsidian Base)
        c.fill(Path(CGRect(x: 0, y: 0, width: 640, height: 172)), with: .color(Color(hex: "#06070A")))

        // 2. Card Boundary & Dimensions
        let cardRect = CGRect(x: USC.CARD_X, y: USC.CARD_Y, width: USC.CARD_W, height: USC.CARD_H)
        let cardPath = roundedRect(cardRect, r: USC.CARD_R)

        var cardCtx = c
        cardCtx.clip(to: cardPath)

        // Card Dark Obsidian Glass Fill
        cardCtx.fill(cardPath, with: .color(Color(hex: "#0E1017").opacity(0.96)))

        // 3. Gemini Cosmic Radial Glow
        let isHovered = f.zoneOver || state.fileDragOver
        let glowCenter = CGPoint(x: USC.CARD_X + USC.CARD_W / 2, y: USC.CARD_Y + USC.CARD_H / 2)
        let glowRadius = USC.CARD_W * 0.65
        let cosmicGlow = Gradient(stops: [
            .init(color: Color(hex: "#38BDF8").opacity(isHovered ? 0.22 : 0.08), location: 0),
            .init(color: Color(hex: "#6366F1").opacity(isHovered ? 0.16 : 0.05), location: 0.45),
            .init(color: Color(hex: "#A855F7").opacity(isHovered ? 0.10 : 0.02), location: 0.75),
            .init(color: Color.clear, location: 1.0)
        ])
        cardCtx.fill(cardPath, with: .radialGradient(cosmicGlow, center: glowCenter, startRadius: 0, endRadius: glowRadius))

        // 4. Animated Gemini Gradient Border
        if f.zoneAlpha > 0 {
            var borderCtx = c
            borderCtx.opacity = f.zoneAlpha
            let dashPhase = CGFloat(wallTime * 28) // smooth march

            let borderGradient = Gradient(stops: [
                .init(color: Color(hex: "#38BDF8").opacity(isHovered ? 0.90 : 0.35), location: 0),
                .init(color: Color(hex: "#818CF8").opacity(isHovered ? 0.90 : 0.35), location: 0.35),
                .init(color: Color(hex: "#C084FC").opacity(isHovered ? 0.90 : 0.35), location: 0.70),
                .init(color: Color(hex: "#38BDF8").opacity(isHovered ? 0.90 : 0.35), location: 1.0)
            ])

            let insetRect = CGRect(x: USC.CARD_X + 0.75, y: USC.CARD_Y + 0.75, width: USC.CARD_W - 1.5, height: USC.CARD_H - 1.5)
            let inPath = roundedRect(insetRect, r: USC.CARD_R - 0.75)

            if isHovered {
                var glowCtx = borderCtx
                glowCtx.addFilter(.blur(radius: 5))
                glowCtx.stroke(
                    inPath,
                    with: .linearGradient(borderGradient, startPoint: CGPoint(x: USC.CARD_X, y: USC.CARD_Y), endPoint: CGPoint(x: USC.CARD_X + USC.CARD_W, y: USC.CARD_Y + USC.CARD_H)),
                    style: StrokeStyle(lineWidth: 2.0, dash: [8, 6], dashPhase: dashPhase)
                )
            }

            borderCtx.stroke(
                inPath,
                with: .linearGradient(borderGradient, startPoint: CGPoint(x: USC.CARD_X, y: USC.CARD_Y), endPoint: CGPoint(x: USC.CARD_X + USC.CARD_W, y: USC.CARD_Y + USC.CARD_H)),
                style: StrokeStyle(lineWidth: isHovered ? 1.5 : 1.0, dash: isHovered ? [8, 6] : [6, 5], dashPhase: dashPhase)
            )
        }

        // 5. Drop Zone Welcoming Content
        if f.zoneAlpha > 0 && f.textAlpha > 0 {
            drawDropText(ctx: &c, f: f)
        }

        // 6. Progress Bar (Uploading Phase)
        if f.barAlpha > 0 || f.barReveal > 0 {
            drawProgressBar(ctx: &c, f: f, wallTime: wallTime)
        }

        // 7. Choose View Text (Attached & Ready)
        if f.chooseAlpha > 0 {
            drawChooseView(ctx: &c, f: f)
        }

        // 8. Living Gemini Star Character
        drawGeminiStar(ctx: &c, f: f, wallTime: wallTime)

        // 9. File & Cosmic Absorption
        if f.fileVisible {
            drawFile(ctx: &c, f: f, wallTime: wallTime)
        }
    }

    // MARK: - Drop Zone Text + Context Chips

    private func drawDropText(ctx: inout GraphicsContext, f: USFrame) {
        var tCtx = ctx
        tCtx.opacity = f.textAlpha

        // Header with sparkle
        let header = Text("✦ Drop files to attach to Antigravity")
            .font(.system(size: 13.5, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "#F8FAFC"))
        tCtx.draw(header, at: CGPoint(x: USC.TEXT_X, y: USC.TEXT_Y - 8), anchor: .leading)

        // Subtitle
        let sub = Text("Context will be instantly analyzed by Gemini 3.8 Flash")
            .font(.system(size: 11.5))
            .foregroundColor(Color(hex: "#94A3B8"))
        tCtx.draw(sub, at: CGPoint(x: USC.TEXT_X, y: USC.TEXT_Y + 11), anchor: .leading)

        // Filetype pill badges
        let chips: [(String, String)] = [
            ("Code", "#38BDF8"),
            ("PDF", "#818CF8"),
            ("Docs", "#A855F7"),
            ("Images", "#EC4899"),
            ("Data", "#10B981")
        ]

        var cx = USC.TEXT_X
        let chipY = USC.TEXT_Y + 28
        for (label, colorHex) in chips {
            let chipText = Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: colorHex))

            let estW = Double(label.count) * 6.8 + 18.0
            let chipRect = CGRect(x: cx, y: chipY, width: estW, height: 18)

            tCtx.fill(roundedRect(chipRect, r: 9), with: .color(Color(hex: colorHex).opacity(0.12)))
            tCtx.stroke(roundedRect(chipRect, r: 9), with: .color(Color(hex: colorHex).opacity(0.28)), lineWidth: 0.8)
            tCtx.draw(chipText, at: CGPoint(x: cx + estW / 2, y: chipY + 9), anchor: .center)

            cx += estW + 6.0
        }
    }

    // MARK: - Progress Bar (Gemini Gradient with Stardust Glow)

    private func drawProgressBar(ctx: inout GraphicsContext, f: USFrame, wallTime: Double) {
        var pCtx = ctx
        pCtx.opacity = max(f.barAlpha, 0.001)

        let x0 = USC.BAR_X0 + 20
        let x1 = USC.BAR_X1
        let by = USC.BAR_Y
        let barLen = (x1 - x0) * f.barReveal

        // File Header Row
        let name = state.droppedFile?.name ?? "file"
        let label = Text("Attaching \(name)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "#F8FAFC"))
        pCtx.draw(label, at: CGPoint(x: x0, y: by - 26), anchor: .leading)

        // Percentage or Completed Checkmark
        if f.check > 0 {
            var ckCtx = pCtx
            ckCtx.concatenate(CGAffineTransform(translationX: CGFloat(x1 - 10), y: CGFloat(by - 26)))
            ckCtx.concatenate(CGAffineTransform(scaleX: CGFloat(f.check), y: CGFloat(f.check)))

            var circle = Path()
            circle.addEllipse(in: CGRect(x: -9, y: -9, width: 18, height: 18))
            ckCtx.fill(circle, with: .color(Color(hex: "#10B981")))

            var ck = Path()
            ck.move(to: CGPoint(x: -4, y: 0.2))
            ck.addLine(to: CGPoint(x: -1.2, y: 3.2))
            ck.addLine(to: CGPoint(x: 4.5, y: -2.8))
            ckCtx.stroke(ck, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        } else {
            let pct = Text("\(Int(f.progress * 100)) %")
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#38BDF8"))
            pCtx.draw(pct, at: CGPoint(x: x1, y: by - 26), anchor: .trailing)
        }

        // Track (Dark Glass)
        if barLen > 0 {
            pCtx.fill(roundedRect(CGRect(x: x0, y: by - 3, width: barLen, height: 6), r: 3), with: .color(Color.white.opacity(0.08)))
        }

        // Bar Fill (Vibrant Gemini Gradient)
        let fx = usLerp(x0, x1, f.progress)
        if fx > x0 + 1 {
            let fillGrad = Gradient(stops: [
                .init(color: Color(hex: "#2563EB"), location: 0),
                .init(color: Color(hex: "#38BDF8"), location: 0.5),
                .init(color: Color(hex: "#A855F7"), location: 1.0)
            ])

            pCtx.fill(roundedRect(CGRect(x: x0, y: by - 3, width: fx - x0, height: 6), r: 3),
                      with: .linearGradient(fillGrad, startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: fx, y: 0)))

            // Glowing Leading Tip
            if f.progress < 0.999 {
                var tipGlow = pCtx
                tipGlow.addFilter(.blur(radius: 4))
                let tipCircle = Path(ellipseIn: CGRect(x: fx - 8, y: by - 7, width: 14, height: 14))
                tipGlow.fill(tipCircle, with: .color(Color(hex: "#38BDF8").opacity(0.85)))
            }
        }
    }

    // MARK: - Choose View Text

    private func drawChooseView(ctx: inout GraphicsContext, f: USFrame) {
        var cCtx = ctx
        cCtx.opacity = f.chooseAlpha
        cCtx.concatenate(CGAffineTransform(translationX: 0, y: CGFloat((1 - f.chooseAlpha) * 4)))

        let name = state.droppedFile?.name ?? "file"

        // Badge: Attached to Context
        let badge = Text("● Attached to Context")
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundColor(Color(hex: "#10B981"))
        cCtx.draw(badge, at: CGPoint(x: 120, y: 72), anchor: .leading)

        let titleText = Text("\(name) is ready")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "#F8FAFC"))
        cCtx.draw(titleText, at: CGPoint(x: 120, y: 88), anchor: .leading)

        let subText = Text("Context loaded into Google Antigravity. Start asking questions.")
            .font(.system(size: 11.5))
            .foregroundColor(Color(hex: "#94A3B8"))
        cCtx.draw(subText, at: CGPoint(x: 120, y: 104), anchor: .leading)
    }

    // MARK: - Living Gemini Star Character (Replaces Mochi)

    private func drawGeminiStar(ctx: inout GraphicsContext, f: USFrame, wallTime: Double) {
        var c = ctx
        let cx = CGFloat(f.x)
        let cy = CGFloat(f.y + f.hop)

        c.concatenate(CGAffineTransform(translationX: cx, y: cy))
        c.concatenate(CGAffineTransform(rotationAngle: CGFloat(f.tilt)))
        c.concatenate(CGAffineTransform(scaleX: CGFloat(f.sx), y: CGFloat(f.sy)))

        let starR = max(14.0, (f.d / 2.0) * 0.95)

        // 1. Ambient Celestial Glow Aura
        var auraCtx = c
        let auraGrad = Gradient(stops: [
            .init(color: Color(hex: "#38BDF8").opacity(0.35), location: 0),
            .init(color: Color(hex: "#818CF8").opacity(0.12), location: 0.5),
            .init(color: Color.clear, location: 1.0)
        ])
        let auraCircle = Path(ellipseIn: CGRect(x: -starR * 1.5, y: -starR * 1.5, width: starR * 3.0, height: starR * 3.0))
        auraCtx.fill(auraCircle, with: .radialGradient(auraGrad, center: .zero, startRadius: 1, endRadius: starR * 1.5))

        // 2. Orbiting Sparkles & Celestial Ring
        let orbitRot = wallTime * 55.0
        for i in 0..<3 {
            let angle = Double(i) * 120.0 + orbitRot
            let rad = angle * .pi / 180.0
            let dist = starR * 1.25
            let px = cos(rad) * dist
            let py = sin(rad) * dist * 0.45 // tilted ellipse orbit
            var sp = Path()
            sp.addEllipse(in: CGRect(x: px - 2, y: py - 2, width: 4, height: 4))
            c.fill(sp, with: .color(Color.white.opacity(0.85)))
        }

        // 3. The 4-Pointed Star Body
        let starPath = geminiStarPath(cx: 0, cy: 0, r: starR)

        let starGradient = Gradient(stops: [
            .init(color: Color(hex: "#38BDF8"), location: 0),
            .init(color: Color(hex: "#3B82F6"), location: 0.45),
            .init(color: Color(hex: "#8B5CF6"), location: 1.0)
        ])

        c.fill(starPath, with: .linearGradient(starGradient, startPoint: CGPoint(x: -starR, y: -starR), endPoint: CGPoint(x: starR, y: starR)))

        // Inner Specular Glass Rim
        c.stroke(
            starPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.75), location: 0),
                    .init(color: Color.white.opacity(0.2), location: 0.4),
                    .init(color: Color.clear, location: 0.8)
                ]),
                startPoint: CGPoint(x: -starR, y: -starR),
                endPoint: CGPoint(x: starR, y: starR)
            ),
            lineWidth: 1.4
        )

        // 4. Cheeks (Cute Blush)
        let blushY = starR * 0.22
        let blushSpacing = starR * 0.40
        for side in [-1.0, 1.0] {
            var cheek = Path()
            cheek.addEllipse(in: CGRect(x: side * blushSpacing - starR * 0.12, y: blushY, width: starR * 0.24, height: starR * 0.13))
            c.fill(cheek, with: .color(Color(hex: "#F472B6").opacity(0.80)))
        }

        // 5. Expressive Eyes
        let eyeY = starR * 0.05
        let eyeSpacing = starR * 0.25
        let eyeW = starR * 0.18
        let eyeH = starR * 0.28
        let lookX = f.lookX * (starR * 0.15)
        let lookY = f.lookY * (starR * 0.10)

        // Happy smile eyes when file is absorbed or complete
        let isHappy = f.suck > 0.6 || f.check > 0 || f.chooseAlpha > 0.5
        for side in [-1.0, 1.0] {
            let ex = side * eyeSpacing + lookX
            let ey = eyeY + lookY

            if isHappy {
                // Curved happy eye arc (^ ^)
                var arc = Path()
                arc.addArc(center: CGPoint(x: ex, y: ey + eyeH * 0.4), radius: eyeW * 0.8, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                c.stroke(arc, with: .color(Color(hex: "#090B10")), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            } else {
                // Sentient pill eye
                var eye = Path()
                eye.addRoundedRect(in: CGRect(x: ex - eyeW / 2, y: ey - eyeH / 2, width: eyeW, height: eyeH), cornerSize: CGSize(width: eyeW / 2, height: eyeW / 2))
                c.fill(eye, with: .color(Color(hex: "#090B10")))

                // Catchlight sparkle in eye
                var catchlight = Path()
                catchlight.addEllipse(in: CGRect(x: ex - eyeW * 0.28, y: ey - eyeH * 0.32, width: eyeW * 0.45, height: eyeW * 0.45))
                c.fill(catchlight, with: .color(.white))
            }
        }
    }

    // MARK: - File & Cosmic Absorption (Smooth Stardust Glide, No Mouth)

    private func drawFile(ctx: inout GraphicsContext, f: USFrame, wallTime: Double) {
        let cx = f.cursorX
        let cy = f.cursorY + 14

        // Idle floating file before drop
        if f.suck <= 0 {
            var fc = ctx
            fc.opacity = 0.95
            drawModernDoc(ctx: &fc, cx: cx, cy: cy, scale: 1.0, rot: 0)
            return
        }

        // Absorbing file: glides directly into Gemini Star
        let p = usEIn(f.suck)
        let q = usEOut(f.suck)

        // Target coordinates = Star center
        let targetX = f.x
        let targetY = f.y

        let curX = usLerp(cx, targetX, q)
        let curY = usLerp(cy, targetY, usEInOut(f.suck))
        let curScale = usLerp(1.0, 0.12, p)
        let curRot = sin(f.suck * .pi * 2.5) * 0.25 * (1.0 - p)
        let curOpacity = max(0, 1.0 - p * 1.1)

        if curOpacity > 0.01 {
            var fc = ctx
            fc.opacity = curOpacity
            drawModernDoc(ctx: &fc, cx: curX, cy: curY, scale: curScale, rot: curRot)
        }

        // Cosmic Stardust Particles Inflow
        for i in 0..<6 {
            let a = Double(i) / 6.0 * .pi * 2.0 + wallTime * 3.0
            let r0 = 36.0 * (1.0 - f.suck)
            let sx0 = curX + cos(a) * r0
            let sy0 = curY + sin(a) * r0
            let px = usLerp(sx0, targetX, p)
            let py = usLerp(sy0, targetY, p)
            let rad = 2.4 * (1.0 - p * 0.5)

            var part = Path()
            part.addEllipse(in: CGRect(x: px - rad, y: py - rad, width: rad * 2, height: rad * 2))

            let pColor = (i % 2 == 0) ? Color(hex: "#38BDF8") : Color(hex: "#C084FC")
            ctx.fill(part, with: .color(pColor.opacity(1.0 - p * 0.8)))
        }
    }

    // MARK: - Modern Document Card Component

    private func drawModernDoc(ctx: inout GraphicsContext, cx: Double, cy: Double, scale: Double, rot: Double) {
        var dCtx = ctx
        dCtx.concatenate(CGAffineTransform(translationX: CGFloat(cx), y: CGFloat(cy)))
        dCtx.concatenate(CGAffineTransform(rotationAngle: CGFloat(rot)))
        dCtx.concatenate(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))

        let w = 38.0
        let h = 48.0
        let x = -w / 2.0
        let y = -h / 2.0
        let fold = 10.0

        // Soft drop shadow
        var sCtx = dCtx
        sCtx.addFilter(.shadow(color: Color.black.opacity(0.45), radius: 8, x: 0, y: 4))

        // Body Shape with folded corner
        var body = Path()
        body.move(to: CGPoint(x: x + 3, y: y))
        body.addLine(to: CGPoint(x: x + w - fold, y: y))
        body.addLine(to: CGPoint(x: x + w, y: y + fold))
        body.addLine(to: CGPoint(x: x + w, y: y + h - 3))
        body.addQuadCurve(to: CGPoint(x: x + w - 3, y: y + h), control: CGPoint(x: x + w, y: y + h))
        body.addLine(to: CGPoint(x: x + 3, y: y + h))
        body.addQuadCurve(to: CGPoint(x: x, y: y + h - 3), control: CGPoint(x: x, y: y + h))
        body.addLine(to: CGPoint(x: x, y: y + 3))
        body.addQuadCurve(to: CGPoint(x: x + 3, y: y), control: CGPoint(x: x, y: y))
        body.closeSubpath()

        // Pure white/frosted glass card
        sCtx.fill(body, with: .color(Color(hex: "#F8FAFC")))

        // Folded flap
        var flap = Path()
        flap.move(to: CGPoint(x: x + w - fold, y: y))
        flap.addLine(to: CGPoint(x: x + w - fold, y: y + fold))
        flap.addLine(to: CGPoint(x: x + w, y: y + fold))
        flap.closeSubpath()
        dCtx.fill(flap, with: .color(Color(hex: "#E2E8F0")))

        // Document extension badge
        let ext = (state.droppedFile?.name.split(separator: ".").last?.uppercased() ?? "FILE").prefix(4)
        let badgeRect = CGRect(x: x + 5, y: y + h - 16, width: w - 10, height: 11)
        dCtx.fill(roundedRect(badgeRect, r: 2.5), with: .color(Color(hex: "#2563EB")))

        let extText = Text(String(ext))
            .font(.system(size: 7.5, weight: .bold, design: .rounded))
            .foregroundColor(.white)
        dCtx.draw(extText, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY), anchor: .center)

        // Document preview lines
        for i in 0..<3 {
            let lineY = y + 14.0 + Double(i) * 5.0
            let lineW = (i == 2) ? (w - 18.0) : (w - 12.0)
            dCtx.fill(roundedRect(CGRect(x: x + 6, y: lineY, width: lineW, height: 2), r: 1), with: .color(Color(hex: "#CBD5E1")))
        }
    }
}

// MARK: - 4-Point Gemini Star Geometry Path

func geminiStarPath(cx: Double, cy: Double, r: Double) -> Path {
    var p = Path()
    let w = r * 2.0
    let h = r * 2.0
    let top = cy - r
    let bottom = cy + r
    let left = cx - r
    let right = cx + r

    // Top tip
    p.move(to: CGPoint(x: cx, y: top))
    // Top to Right (concave arc towards center)
    p.addQuadCurve(to: CGPoint(x: right, y: cy), control: CGPoint(x: cx + w * 0.12, y: cy - h * 0.12))
    // Right to Bottom
    p.addQuadCurve(to: CGPoint(x: cx, y: bottom), control: CGPoint(x: cx + w * 0.12, y: cy + h * 0.12))
    // Bottom to Left
    p.addQuadCurve(to: CGPoint(x: left, y: cy), control: CGPoint(x: cx - w * 0.12, y: cy + h * 0.12))
    // Left to Top
    p.addQuadCurve(to: CGPoint(x: cx, y: top), control: CGPoint(x: cx - w * 0.12, y: cy - h * 0.12))
    p.closeSubpath()

    return p
}

// MARK: - Rounded Rect Helper

func roundedRect(_ rect: CGRect, r rr: Double) -> Path {
    let r = max(0, min(rr, Double(rect.width) / 2, Double(rect.height) / 2))
    var p = Path()
    p.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
    return p
}
