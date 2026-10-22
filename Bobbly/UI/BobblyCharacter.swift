//  BobblyCharacter.swift
//  Bobbly/UI — Bobbly, drawn entirely with SwiftUI shapes (no image assets).
//
//  Bobbly is a little fishing float: a soft dome with a pale belly and a
//  sprout-like stem on top. The face follows `CompanionMood`; `mood` (0–100)
//  nudges the mouth within a tier. Idle motion is a slow bob plus blinking,
//  and both stop when Reduce Motion is on.
//
//  Use the same component everywhere: Home, Chat, Gate, Companion, Tutorial.

import SwiftUI

struct BobblyCharacter: View {
    var mood: CompanionMood
    /// 0–100; subtle variation inside a tier.
    var moodValue: Int = 60
    var size: CGFloat = 120
    /// Idle bob + blink. Turn off for tiny avatars and lists.
    var isAnimated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(mood: CompanionMood, moodValue: Int = 60, size: CGFloat = 120, isAnimated: Bool = true) {
        self.mood = mood
        self.moodValue = moodValue
        self.size = size
        self.isAnimated = isAnimated
    }

    var body: some View {
        let animate = isAnimated && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animate)) { context in
            let t = animate ? context.date.timeIntervalSinceReferenceDate : 0
            let pose = BobblyPose(time: t, mood: mood, animated: animate)
            BobblyFigure(mood: mood, moodValue: moodValue, size: size, eyeOpenness: pose.eyeOpenness, stemSway: pose.stemSway)
                .offset(y: pose.lift * size)
                .rotationEffect(.degrees(pose.tilt), anchor: .bottom)
                .scaleEffect(x: 1 + pose.breathe, y: 1 - pose.breathe, anchor: .bottom)
        }
        .frame(width: size, height: size)
        .animation(Theme.Motion.reveal, value: mood)
        .animation(Theme.Motion.reveal, value: moodValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bobbly")
        .accessibilityValue(mood.moodPhrase)
    }
}

// MARK: - Pose (pure function of time)

private struct BobblyPose {
    var lift: CGFloat = 0
    var tilt: Double = 0
    var breathe: CGFloat = 0
    var eyeOpenness: CGFloat = 1
    var stemSway: Double = 0

    init(time t: TimeInterval, mood: CompanionMood, animated: Bool) {
        guard animated else { return }
        let cycle = 2 * Double.pi / Theme.Motion.bobPeriod
        switch mood {
        case .exhausted:
            // Asleep: no bobbing, slow breathing.
            breathe = CGFloat(sin(t * 2 * .pi / 4.2)) * 0.018
            eyeOpenness = 1
        case .sad:
            lift = CGFloat(sin(t * cycle * 0.7)) * 0.012
            tilt = sin(t * cycle * 0.7 + 0.9) * 1.2
            stemSway = sin(t * cycle * 0.7) * 3
            eyeOpenness = Self.blink(t, period: 5.8)
        default:
            let energy: Double = mood == .thriving ? 1.3 : (mood == .happy ? 1.0 : 0.8)
            lift = CGFloat(sin(t * cycle * energy)) * 0.024
            tilt = sin(t * cycle * energy + 0.8) * 2.4
            stemSway = sin(t * cycle * energy + 0.4) * 6
            eyeOpenness = Self.blink(t, period: 4.6)
        }
    }

    /// Eyes close briefly once per `period` seconds.
    private static func blink(_ t: TimeInterval, period: Double) -> CGFloat {
        let duration = 0.16
        let phase = t.truncatingRemainder(dividingBy: period)
        guard phase < duration else { return 1 }
        return CGFloat(1 - sin(phase / duration * .pi) * 0.9)
    }
}

// MARK: - Figure

/// The static drawing. Coordinates are fractions of `size`.
private struct BobblyFigure: View {
    let mood: CompanionMood
    let moodValue: Int
    let size: CGFloat
    let eyeOpenness: CGFloat
    let stemSway: Double

    private var colors: BobblyColors { BobblyColors(mood) }
    private var s: CGFloat { size }

    var body: some View {
        ZStack {
            stem
            bodyAndBelly
            cheeks
            eyes
            mouth
            if mood == .exhausted { sleepyZs }
        }
        .frame(width: s, height: s)
    }

    // Stem with a little ball on top; droops when Bobbly is low.
    private var stem: some View {
        VStack(spacing: -s * 0.012) {
            Circle()
                .fill(colors.ball)
                .frame(width: s * 0.1, height: s * 0.1)
                .shadow(color: mood == .thriving ? colors.ball.opacity(0.9) : .clear, radius: s * 0.045)
            Capsule()
                .fill(BobblyColors.feature)
                .frame(width: s * 0.04, height: s * 0.13)
        }
        .frame(width: s * 0.1, height: s * 0.218)
        .rotationEffect(.degrees(colors.stemDroop + stemSway), anchor: .bottom)
        .position(x: s * 0.5, y: s * 0.27 - s * 0.109)
    }

    private var bodyAndBelly: some View {
        ZStack {
            BobblyBodyShape().fill(colors.body)
            Ellipse()
                .fill(colors.belly)
                .frame(width: s * 0.9, height: s * 0.44)
                .position(x: s * 0.5, y: s * 0.95)
            // Soft gloss, top left.
            Ellipse()
                .fill(Color.white.opacity(0.32))
                .frame(width: s * 0.17, height: s * 0.09)
                .rotationEffect(.degrees(-32))
                .position(x: s * 0.28, y: s * 0.39)
        }
        .frame(width: s, height: s)
        .clipShape(BobblyBodyShape())
    }

    @ViewBuilder private var cheeks: some View {
        let opacity: Double = {
            switch mood {
            case .thriving: return 0.6
            case .happy: return 0.45
            case .okay: return 0.2
            case .sad, .exhausted: return 0
            }
        }()
        let positions: [CGFloat] = [0.27, 0.73]
        if opacity > 0 {
            ForEach(positions, id: \.self) { x in
                Ellipse()
                    .fill(BobblyColors.cheek.opacity(opacity))
                    .frame(width: s * 0.1, height: s * 0.055)
                    .position(x: s * x, y: s * 0.665)
            }
        }
    }

    @ViewBuilder private var eyes: some View {
        let eyeY = s * 0.555
        let w = s * 0.085
        let h = s * 0.12
        let positions: [CGFloat] = [0.38, 0.62]
        ForEach(positions, id: \.self) { x in
            let isLeft = x < 0.5
            switch mood {
            case .thriving:
                ArcEye(upward: true)
                    .stroke(BobblyColors.feature, style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
                    .frame(width: s * 0.1, height: s * 0.05)
                    .position(x: s * x, y: eyeY)
            case .exhausted:
                ArcEye(upward: false)
                    .stroke(BobblyColors.feature, style: StrokeStyle(lineWidth: s * 0.026, lineCap: .round))
                    .frame(width: s * 0.1, height: s * 0.035)
                    .position(x: s * x, y: eyeY + s * 0.01)
            case .happy, .okay, .sad:
                ZStack {
                    Ellipse()
                        .fill(BobblyColors.feature)
                        .frame(width: w, height: max(s * 0.012, h * eyeOpenness * (mood == .okay ? 0.9 : 1)))
                    if eyeOpenness > 0.6 {
                        Circle()
                            .fill(Color.white)
                            .frame(width: s * 0.03, height: s * 0.03)
                            .offset(x: s * 0.014, y: -h * 0.2)
                    }
                    if mood == .sad {
                        // Heavy lid: the body colour slants across the top of the eye.
                        Rectangle()
                            .fill(colors.body)
                            .frame(width: w * 1.8, height: h * 0.6)
                            .rotationEffect(.degrees(isLeft ? -16 : 16))
                            .offset(y: -h * 0.52)
                    }
                }
                .frame(width: w * 1.8, height: h * 1.6)
                .position(x: s * x, y: eyeY)

                if mood == .sad {
                    Capsule()
                        .fill(BobblyColors.feature)
                        .frame(width: s * 0.09, height: s * 0.02)
                        .rotationEffect(.degrees(isLeft ? -16 : 16))
                        .position(x: s * x, y: eyeY - s * 0.105)
                }
            }
        }
    }

    private var mouth: some View {
        let shape = MouthGeometry(mood: mood, moodValue: moodValue)
        let width = s * 0.17
        let height = s * 0.1
        let lineWidth = s * 0.026
        return ZStack {
            if shape.open > 0.01 {
                ZStack {
                    Rectangle().fill(BobblyColors.feature)
                    Ellipse()
                        .fill(BobblyColors.tongue)
                        .frame(width: width * 0.55, height: height * 0.7)
                        .offset(y: height * 0.62)
                }
                .mask { MouthOpening(curve: shape.curve, open: shape.open) }
            }
            MouthLine(curve: shape.curve, lineWidth: lineWidth)
                .stroke(BobblyColors.feature, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .frame(width: width, height: height)
        .position(x: s * 0.5, y: s * 0.69)
    }

    private var sleepyZs: some View {
        ZStack {
            Text("z")
                .font(.system(size: s * 0.12, weight: .bold, design: .rounded))
                .position(x: s * 0.8, y: s * 0.24)
            Text("z")
                .font(.system(size: s * 0.085, weight: .bold, design: .rounded))
                .position(x: s * 0.9, y: s * 0.13)
        }
        .foregroundStyle(Theme.Palette.inkTertiary)
        .accessibilityHidden(true)
    }
}

// MARK: - Colours

private struct BobblyColors {
    let body: Color
    let belly: Color
    let ball: Color
    /// Degrees the stem leans (positive = droops to the right).
    let stemDroop: Double

    /// Eyes, mouth and stem. Fixed in both modes: Bobbly is a lit object.
    static let feature = Color(bobblyHex: 0x1F2A30)
    static let cheek = Color(bobblyHex: 0xFF7F96)
    static let tongue = Color(bobblyHex: 0xE8576A)

    init(_ mood: CompanionMood) {
        switch mood {
        case .thriving:
            body = Color(bobblyHex: 0xFF6A35); belly = Color(bobblyHex: 0xFFE2D1); ball = Color(bobblyHex: 0xFFC23D); stemDroop = -8
        case .happy:
            body = Color(bobblyHex: 0xFF7C4A); belly = Color(bobblyHex: 0xFFE6D9); ball = Color(bobblyHex: 0xFFB547); stemDroop = -3
        case .okay:
            body = Color(bobblyHex: 0xEE9466); belly = Color(bobblyHex: 0xFBE6DA); ball = Color(bobblyHex: 0xE8A86F); stemDroop = 10
        case .sad:
            body = Color(bobblyHex: 0xC4917F); belly = Color(bobblyHex: 0xF0E0D9); ball = Color(bobblyHex: 0xB3A29A); stemDroop = 30
        case .exhausted:
            body = Color(bobblyHex: 0xA49A95); belly = Color(bobblyHex: 0xE3DDDA); ball = Color(bobblyHex: 0x958C88); stemDroop = 62
        }
    }
}

/// Mouth curve (−1 frown … 1 smile) and opening (0 closed … 1 wide).
private struct MouthGeometry {
    let curve: CGFloat
    let open: CGFloat

    init(mood: CompanionMood, moodValue: Int) {
        let m = CGFloat(min(100, max(0, moodValue)))
        switch mood {
        case .thriving:
            curve = 1; open = 0.45 + min(0.35, (m - 85) / 15 * 0.35)
        case .happy:
            curve = 0.55 + max(0, min(0.3, (m - 60) / 25 * 0.3)); open = 0
        case .okay:
            curve = 0.1 + max(0, min(0.25, (m - 35) / 25 * 0.25)); open = 0
        case .sad:
            curve = -0.5 + max(0, min(0.25, m / 35 * 0.25)); open = 0
        case .exhausted:
            curve = -0.12; open = 0
        }
    }
}

// MARK: - Shapes

/// Bobbly's dome. Drawn inside the full square: x 0.10–0.90, y 0.27–0.97.
struct BobblyBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x0 = rect.minX + rect.width * 0.10
        let y0 = rect.minY + rect.height * 0.27
        let w = rect.width * 0.80
        let h = rect.height * 0.70
        func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: x0 + u * w, y: y0 + v * h) }

        var path = Path()
        path.move(to: p(0.5, 1))
        path.addCurve(to: p(0, 0.6), control1: p(0.16, 1), control2: p(0, 0.86))
        path.addCurve(to: p(0.5, 0), control1: p(0, 0.26), control2: p(0.22, 0))
        path.addCurve(to: p(1, 0.6), control1: p(0.78, 0), control2: p(1, 0.26))
        path.addCurve(to: p(0.5, 1), control1: p(1, 0.86), control2: p(0.84, 1))
        path.closeSubpath()
        return path
    }
}

/// ∩ (happy, closed) or ∪ (asleep) eye.
private struct ArcEye: Shape {
    var upward: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if upward {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                              control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                              control: CGPoint(x: rect.midX, y: rect.maxY + rect.height))
        }
        return path
    }
}

/// The mouth's outline (stroked). Animates between moods.
private struct MouthLine: Shape {
    var curve: CGFloat
    var lineWidth: CGFloat

    var animatableData: CGFloat {
        get { curve }
        set { curve = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let cornerY = rect.midY - curve * rect.height * 0.15
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: cornerY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - inset, y: cornerY),
                          control: CGPoint(x: rect.midX, y: rect.midY + curve * rect.height * 0.9))
        return path
    }
}

/// The open part of a big smile (filled, used as a mask).
private struct MouthOpening: Shape {
    var curve: CGFloat
    var open: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(curve, open) }
        set { curve = newValue.first; open = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let cornerY = rect.midY - curve * rect.height * 0.15
        let depth = curve * rect.height * 0.9
        let left = CGPoint(x: rect.minX, y: cornerY)
        let right = CGPoint(x: rect.maxX, y: cornerY)
        var path = Path()
        path.move(to: left)
        path.addQuadCurve(to: right, control: CGPoint(x: rect.midX, y: rect.midY + depth * 0.2))
        path.addQuadCurve(to: left, control: CGPoint(x: rect.midX, y: rect.midY + depth * (1 + open * 1.4)))
        path.closeSubpath()
        return path
    }
}

// MARK: - Mood copy

extension CompanionMood {
    /// "Thriving", "Happy", …
    var moodTitle: String {
        switch self {
        case .thriving: return "Thriving"
        case .happy: return "Happy"
        case .okay: return "Okay"
        case .sad: return "Droopy"
        case .exhausted: return "Resting"
        }
    }

    /// For VoiceOver: "Bobbly, happy".
    var moodPhrase: String {
        switch self {
        case .thriving: return "thriving"
        case .happy: return "happy"
        case .okay: return "doing okay"
        case .sad: return "a bit sad"
        case .exhausted: return "out of lives and resting until tomorrow"
        }
    }
}

#Preview("Moods") {
    HStack(spacing: 8) {
        ForEach(CompanionMood.allCases, id: \.self) { mood in
            BobblyCharacter(mood: mood, moodValue: 70, size: 64)
        }
    }
    .padding()
    .bobblyPage()
}
