// RelationshipJourneyMapVisuals.swift
// MemoirAI — shared path, nodes, and decorative layers for RelationshipJourneyView.

import SwiftUI
import Vortex

// MARK: - Layout constants (shared with journey view)

enum RelationshipJourneyMapConstants {
    /// Shorter map now that each Love chapter has 4 prompts (was 10).
    static let scrollContentHeight: CGFloat = 820

    /// Compact S-curve for 4 nodes; bottom→top to preserve the prior scroll direction.
    static let waypoints: [(CGFloat, CGFloat)] = [
        (0.50, 0.86),
        (0.76, 0.62),
        (0.24, 0.38),
        (0.50, 0.14)
    ]
}

// MARK: - Path shape (Catmull-Rom style smooth curve)

struct RelationshipWindingPathShape: Shape {
    let waypoints: [(CGFloat, CGFloat)]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pts: [CGPoint] = waypoints.map { wp in
            CGPoint(x: wp.0 * rect.width, y: wp.1 * rect.height)
        }
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        for i in 0..<pts.count - 1 {
            let p0: CGPoint
            if i == 0 {
                p0 = CGPoint(x: 2 * pts[0].x - pts[1].x, y: 2 * pts[0].y - pts[1].y)
            } else {
                p0 = pts[i - 1]
            }
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3: CGPoint
            if i + 2 < pts.count {
                p3 = pts[i + 2]
            } else {
                p3 = CGPoint(x: 2 * pts[i + 1].x - pts[i].x, y: 2 * pts[i + 1].y - pts[i].y)
            }
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }
}

// MARK: - Vortex presets for journey map

extension VortexSystem {
    /// Gentle floating motes rising through the map (low birth rate).
    static func memoirJourneyAmbient() -> VortexSystem {
        let system = VortexSystem(tags: ["circle"])
        system.shape = .ellipse(radius: 0.52)
        system.birthRate = 22
        system.lifespan = 5.5
        system.speed = 0.1
        system.speedVariation = 0.06
        system.angle = .degrees(270)
        system.angleRange = .degrees(55)
        system.colors = .ramp(.white, Color(red: 1, green: 0.85, blue: 0.92).opacity(0.7), .clear)
        system.size = 0.038
        system.sizeVariation = 0.025
        system.dampingFactor = 0.15
        return system
    }
}

// MARK: - Noise + landscape depth

struct RelationshipNoiseGrainOverlay: View {
    let width: CGFloat
    let height: CGFloat
    let chapterNumber: Int

    var body: some View {
        Canvas { context, size in
            let step = 36
            for y in stride(from: 0, to: Int(size.height), by: step) {
                for x in stride(from: 0, to: Int(size.width), by: step) {
                    let seed = (x * 17 + y * 31 + chapterNumber * 97) % 1000
                    let o = 0.03 + CGFloat(seed % 9) / 120.0
                    let r = CGRect(x: x, y: y, width: 4, height: 4)
                    context.fill(Path(ellipseIn: r), with: .color(Color.white.opacity(o)))
                }
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .blendMode(.overlay)
        .opacity(0.45)
    }
}

struct RelationshipHillsSilhouetteLayer: View {
    let width: CGFloat
    let height: CGFloat
    let chapterNumber: Int

    var body: some View {
        Canvas { ctx, size in
            let baseY = size.height * 0.88
            var hill1 = Path()
            hill1.move(to: CGPoint(x: 0, y: size.height))
            hill1.addCurve(
                to: CGPoint(x: size.width, y: baseY + 40),
                control1: CGPoint(x: size.width * 0.25, y: baseY - 30),
                control2: CGPoint(x: size.width * 0.65, y: baseY + 80)
            )
            hill1.addLine(to: CGPoint(x: size.width, y: size.height))
            hill1.closeSubpath()
            ctx.fill(
                hill1,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.12 + CGFloat(chapterNumber % 3) * 0.02),
                        Color.white.opacity(0.02)
                    ]),
                    startPoint: CGPoint(x: 0, y: baseY),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            let topY = size.height * 0.06
            var cloud = Path()
            cloud.addEllipse(in: CGRect(x: size.width * 0.08, y: topY, width: size.width * 0.35, height: 42))
            cloud.addEllipse(in: CGRect(x: size.width * 0.55, y: topY + 8, width: size.width * 0.32, height: 36))
            ctx.fill(
                cloud,
                with: .color(Color.white.opacity(0.18))
            )
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

struct RelationshipAmbientGlowSpots: View {
    let width: CGFloat
    let height: CGFloat
    let accent: Color
    let coolAccent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.35), accent.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: width * 0.45
                    )
                )
                .frame(width: width * 0.9, height: width * 0.9)
                .position(x: width * 0.2, y: height * 0.35)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [coolAccent.opacity(0.28), coolAccent.opacity(0.06), .clear],
                        center: .center,
                        startRadius: 15,
                        endRadius: width * 0.4
                    )
                )
                .frame(width: width * 0.85, height: width * 0.85)
                .position(x: width * 0.82, y: height * 0.55)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

// MARK: - Path edge stones (dots offset from waypoints)

struct RelationshipPathEdgeStones: View {
    let width: CGFloat
    let height: CGFloat
    let waypoints: [(CGFloat, CGFloat)]

    var body: some View {
        Canvas { ctx, size in
            guard waypoints.count > 1 else { return }
            for i in 0..<(waypoints.count - 1) {
                let a = waypoints[i]
                let b = waypoints[i + 1]
                let mx = (a.0 + b.0) / 2
                let my = (a.1 + b.1) / 2
                let dx = b.0 - a.0
                let dy = b.1 - a.1
                let len = max(0.001, sqrt(dx * dx + dy * dy))
                let px = -dy / len * 0.028
                let py = dx / len * 0.028
                for side in [-1.0, 1.0] {
                    let sx = (mx + px * side) * size.width
                    let sy = (my + py * side) * size.height
                    let r = 3.5 + CGFloat(i % 3)
                    let rect = CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color(red: 0.72, green: 0.58, blue: 0.48).opacity(0.55))
                    )
                }
            }
            for (i, wp) in waypoints.enumerated() {
                let jitter = CGFloat((i * 7) % 5) - 2
                let sx = wp.0 * size.width + jitter
                let sy = wp.1 * size.height + CGFloat(i % 2) * 4
                let r: CGFloat = 2.5
                let rect = CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)
                ctx.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color(red: 0.55, green: 0.42, blue: 0.35).opacity(0.4))
                )
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

// MARK: - Rich map node

struct RelationshipMapNodeView: View {
    let stepNumber: Int
    let isCompleted: Bool
    let isSelected: Bool
    let isNextNode: Bool
    var mapAppeared: Bool
    let appearanceIndex: Int

    private let nodeDiameter: CGFloat = 72

    var body: some View {
        let scale = mapAppeared ? 1.0 : 0.2
        ZStack {
            if isNextNode && !isCompleted {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let pulse = 0.5 + 0.5 * sin(t * 2 * .pi * 0.78)
                    Circle()
                        .stroke(
                            Color.orange.opacity(0.35 + pulse * 0.45),
                            lineWidth: 3 + pulse * 4
                        )
                        .frame(width: 92 + pulse * 16, height: 92 + pulse * 16)
                }
            }

            Circle()
                .fill(glowFill)
                .frame(width: 100, height: 100)
                .blur(radius: 10)

            ZStack {
                Circle()
                    .fill(innerShadowGradient)
                    .frame(width: nodeDiameter, height: nodeDiameter)

                Circle()
                    .fill(nodeGradient)
                    .frame(width: nodeDiameter - 3, height: nodeDiameter - 3)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.08),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: nodeDiameter - 6, height: nodeDiameter * 0.45)
                    .offset(y: -nodeDiameter * 0.12)

                Circle()
                    .stroke(borderColor, lineWidth: isSelected ? 3.5 : 2.5)
                    .frame(width: nodeDiameter - 2, height: nodeDiameter - 2)
            }
            .shadow(color: shadowTint.opacity(0.55), radius: 10, x: 0, y: 5)
            .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 3)

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
            } else if isSelected {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text("\(stepNumber)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 1, x: 0, y: 1)
            }
        }
        .scaleEffect(scale)
        .opacity(mapAppeared ? 1 : 0)
        .animation(
            .spring(response: 0.52, dampingFraction: 0.72)
                .delay(Double(appearanceIndex) * 0.055),
            value: mapAppeared
        )
    }

    private var glowFill: RadialGradient {
        RadialGradient(
            colors: isCompleted
                ? [Color.green.opacity(0.45), Color.green.opacity(0.1), .clear]
                : [Color.orange.opacity(0.5), Color(red: 0.95, green: 0.45, blue: 0.3).opacity(0.2), .clear],
            center: .center,
            startRadius: 10,
            endRadius: 48
        )
    }

    private var innerShadowGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.black.opacity(0.12),
                Color.clear,
                Color.black.opacity(0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var nodeGradient: LinearGradient {
        if isCompleted {
            return LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.78, blue: 0.52),
                    Color(red: 0.22, green: 0.58, blue: 0.38),
                    Color(red: 0.16, green: 0.48, blue: 0.34)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.62, blue: 0.42),
                Color(red: 0.95, green: 0.45, blue: 0.32),
                Color(red: 0.78, green: 0.32, blue: 0.28)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        if isSelected { return Color.orange }
        if isCompleted { return Color(red: 0.2, green: 0.45, blue: 0.28) }
        return Color.white.opacity(0.75)
    }

    private var shadowTint: Color {
        isCompleted ? Color(red: 0.15, green: 0.4, blue: 0.25) : Color(red: 0.55, green: 0.22, blue: 0.12)
    }
}

// MARK: - Journey decorations (visible, animated)

struct RelationshipJourneyDecorationsView: View {
    let width: CGFloat
    let height: CGFloat
    let waypoints: [(CGFloat, CGFloat)]
    let chapterNumber: Int
    let accentPalette: [Color]
    let mapAppeared: Bool

    var body: some View {
        let symbols = ["heart.fill", "sparkles", "star.fill", "leaf.fill", "moon.stars.fill", "sun.max.fill"]
        return ZStack {
            ForEach(0..<landmarkSpecs.count, id: \.self) { i in
                let spec = landmarkSpecs[i]
                landmarkView(symbol: spec.symbol, color: accentPalette[i % accentPalette.count], x: spec.x, y: spec.y, phase: Double(i), floatAmp: spec.amp)
            }
            ForEach(0..<min(waypoints.count, 10), id: \.self) { i in
                let wp = waypoints[i]
                let baseX = wp.0 * width
                let baseY = wp.1 * height
                let side: CGFloat = i % 2 == 0 ? -1 : 1
                let dx = (52 + CGFloat(i % 4) * 12) * side
                let dy = CGFloat((i % 3) - 1) * 20
                let symbol = symbols[i % symbols.count]
                let fontSize: CGFloat = 22 + CGFloat(i % 5) * 4
                let tint = accentPalette[i % accentPalette.count]
                Image(systemName: symbol)
                    .font(.system(size: fontSize))
                    .foregroundStyle(tint.opacity(0.38 + pseudoUnit(i * 41 + chapterNumber, 12) * 0.22))
                    .rotationEffect(.degrees(mapAppeared ? Double(i % 3) * 4 - 4 : 0))
                    .offset(y: mapAppeared ? 0 : 8)
                    .opacity(mapAppeared ? 1 : 0)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.78).delay(Double(i) * 0.04),
                        value: mapAppeared
                    )
                    .position(x: baseX + dx, y: baseY + dy)
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private var landmarkSpecs: [(symbol: String, x: CGFloat, y: CGFloat, amp: CGFloat)] {
        [
            (symbol: "heart.circle.fill", x: 0.18, y: 0.42, amp: 5),
            (symbol: "star.circle.fill", x: 0.82, y: 0.38, amp: 6),
            (symbol: "sparkles", x: 0.5, y: 0.62, amp: 4)
        ]
    }

    @ViewBuilder
    private func landmarkView(symbol: String, color: Color, x: CGFloat, y: CGFloat, phase: Double, floatAmp: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let bob = sin(t * 1.1 + phase) * floatAmp
            ZStack {
                Image(systemName: symbol)
                    .font(.system(size: 52))
                    .foregroundStyle(color.opacity(0.22))
                    .blur(radius: 2)
                Image(systemName: symbol)
                    .font(.system(size: 44))
                    .foregroundStyle(color.opacity(0.48))
            }
            .offset(y: bob)
            .position(x: x * width, y: y * height)
            .scaleEffect(mapAppeared ? 1 : 0.6)
            .opacity(mapAppeared ? 1 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.75), value: mapAppeared)
        }
    }

    private func pseudoUnit(_ seed: Int, _ mod: Int) -> CGFloat {
        let v = abs((seed * 7919 + mod * 104729) % 10000)
        return CGFloat(v) / 10000.0
    }
}

// MARK: - Button style for map nodes

struct RelationshipJourneyNodeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: configuration.isPressed)
    }
}
