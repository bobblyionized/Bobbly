//  Pond.swift
//  Bobbly/UI — the waterline motif. Bobbly floats on a wavy waterline; the
//  water's tone is the protection state. Used by Home (hero card), Gate
//  (full screen), Companion and the tutorial illustrations.

import SwiftUI

// MARK: - Wave shape

/// A sine wave across the top of `rect`. Closed = filled water body below
/// the wave; open = only the crest line (for a highlight stroke).
struct WaveShape: Shape {
    var phase: Double
    var amplitude: CGFloat
    var wavelength: CGFloat
    var closed: Bool = true

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let baseline = rect.minY + amplitude
        let length = Double(max(wavelength, 1))

        func y(at x: CGFloat) -> CGFloat {
            let progress = Double(x - rect.minX) / length
            return baseline + CGFloat(sin(progress * 2 * Double.pi + phase)) * amplitude
        }

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: y(at: rect.minX)))
        var x = rect.minX + 3
        while x < rect.maxX {
            path.addLine(to: CGPoint(x: x, y: y(at: x)))
            x += 3
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: y(at: rect.maxX)))
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Water

/// Two layered waves and a light crest line. Animates slowly unless Reduce
/// Motion is on. Fills its frame; the wave crest sits at the top edge.
struct WaterSurface: View {
    var tone: Theme.Water
    var amplitude: CGFloat = 5
    var isAnimated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animate = isAnimated && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !animate)) { context in
            let t = animate ? context.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                WaveShape(phase: t * 0.8 + 1.7, amplitude: amplitude * 0.8, wavelength: 230)
                    .fill(tone.color.opacity(0.4))
                    .offset(y: -amplitude * 1.1)
                WaveShape(phase: t * 1.2, amplitude: amplitude, wavelength: 170)
                    .fill(tone.color)
                WaveShape(phase: t * 1.2, amplitude: amplitude, wavelength: 170, closed: false)
                    .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .animation(Theme.Motion.reveal, value: tone)
        .accessibilityHidden(true)
    }
}

/// Air above, water below. The air content's bottom `overlap` points dip
/// under the water (that's where Bobbly floats); the water content is padded
/// so it never collides with him.
struct PondScene<Air: View, Water: View>: View {
    let tone: Theme.Water
    let overlap: CGFloat
    var amplitude: CGFloat = 5
    let air: Air
    let water: Water

    init(tone: Theme.Water, overlap: CGFloat, amplitude: CGFloat = 5,
         @ViewBuilder air: () -> Air, @ViewBuilder water: () -> Water) {
        self.tone = tone
        self.overlap = overlap
        self.amplitude = amplitude
        self.air = air()
        self.water = water()
    }

    var body: some View {
        VStack(spacing: 0) {
            air
                .padding(.bottom, -overlap)
            water
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, overlap)
                .background(alignment: .top) {
                    WaterSurface(tone: tone, amplitude: amplitude)
                }
        }
    }
}

/// Full-screen backdrop for pond screens: page colour above, water below,
/// so overscroll and the home-indicator area never show a seam.
struct PondBackdrop: View {
    let tone: Theme.Water

    var body: some View {
        VStack(spacing: 0) {
            Theme.Palette.page
            tone.color
        }
        .ignoresSafeArea()
        .animation(Theme.Motion.reveal, value: tone)
        .accessibilityHidden(true)
    }
}

// MARK: - Speech bubble

/// What Bobbly says, outside the chat. Rounded type = Bobbly's voice.
struct SpeechBubble: View {
    enum Tail { case leading, bottom }

    let text: String
    var tail: Tail = .leading
    var fill: Color = Theme.Palette.sunken
    var font: Font = Theme.Typography.voice

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Theme.Palette.ink)
            .multilineTextAlignment(tail == .bottom ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(alignment: tail == .leading ? .leading : .bottom) {
                ZStack(alignment: tail == .leading ? .leading : .bottom) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(fill)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(fill)
                        .frame(width: 13, height: 13)
                        .rotationEffect(.degrees(45))
                        .offset(x: tail == .leading ? -5 : 0, y: tail == .bottom ? 5 : 0)
                }
            }
            .contentTransition(.opacity)
            .animation(Theme.Motion.standard, value: text)
            .accessibilityLabel("Bobbly says: \(text)")
    }
}

// MARK: - Lives

/// Bobbly's hearts for today.
struct LivesView: View {
    let lives: Int
    let maxLives: Int
    var font: Font = .footnote
    var tint: Color = Theme.Palette.heart
    var emptyTint: Color = Theme.Palette.inkTertiary

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(maxLives, 0), id: \.self) { index in
                Image(systemName: index < lives ? "heart.fill" : "heart")
                    .foregroundStyle(index < lives ? tint : emptyTint)
            }
        }
        .font(font)
        .symbolEffect(.bounce, value: lives)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lives) of \(maxLives) lives left today")
    }
}

#Preview("Pond") {
    PondScene(tone: .calm, overlap: 26) {
        HStack(alignment: .bottom) {
            BobblyCharacter(mood: .happy, size: 110)
            SpeechBubble(text: "Feeling good, friend.")
                .padding(.bottom, 50)
            Spacer()
        }
        .padding(.horizontal)
    } water: {
        Text("Protecting 6 apps")
            .font(Theme.Typography.title)
            .foregroundStyle(.white)
            .padding()
    }
    .background(Theme.Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
    .padding()
    .bobblyPage()
}
