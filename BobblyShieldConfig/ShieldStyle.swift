//  ShieldStyle.swift
//  BobblyShieldConfig — how the shield looks (UI-owned). Turns `ShieldContent`
//  into a `ShieldConfiguration`: the app's "still water" palette as dynamic
//  UIColors, and Bobbly floating in a round pond, drawn per mood with
//  UIGraphicsImageRenderer.
//
//  Pure and cheap: no I/O, one small image per call. The shield extension is
//  short-lived and memory-limited, so nothing here is cached or retained.
//  The colours mirror Bobbly/UI/Theme.swift (extensions can't see that file).

import ManagedSettings
import ManagedSettingsUI
import UIKit

enum ShieldStyle {
    static func configuration(for content: ShieldContent) -> ShieldConfiguration {
        let isStudy: Bool
        if case .studySession = content.kind { isStudy = true } else { isStudy = false }

        let accent = isStudy ? ShieldPalette.reed : ShieldPalette.pond
        let onAccent = isStudy ? ShieldPalette.onReed : ShieldPalette.onPond
        // After "Talk to Bobbly" was pressed the button only points at the
        // notification, so it steps back visually.
        let primaryBackground = content.notificationRecentlySent ? ShieldPalette.muted : accent
        let primaryText = content.notificationRecentlySent ? ShieldPalette.onMuted : onAccent

        let water = isStudy ? ShieldPalette.studyWater : ShieldPalette.calmWater

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: ShieldPalette.page,
            icon: BobblyIcon.image(mood: content.mood, water: water),
            title: ShieldConfiguration.Label(text: content.title, color: ShieldPalette.ink),
            subtitle: ShieldConfiguration.Label(text: content.subtitle, color: ShieldPalette.inkSecondary),
            primaryButtonLabel: ShieldConfiguration.Label(text: content.primaryButton, color: primaryText),
            primaryButtonBackgroundColor: primaryBackground,
            secondaryButtonLabel: content.secondaryButton.map {
                ShieldConfiguration.Label(text: $0, color: accent)
            }
        )
    }
}

// MARK: - Palette (dynamic, light/dark)

private enum ShieldPalette {
    static let page = dynamic(light: 0xEDF2EF, dark: 0x0B1F27, alpha: 0.94)
    static let ink = dynamic(light: 0x12303C, dark: 0xE6EFEC)
    static let inkSecondary = dynamic(light: 0x47616C, dark: 0xA2B8B7)
    static let pond = dynamic(light: 0x1E6F6A, dark: 0x5BC2B5)
    static let onPond = dynamic(light: 0xFFFFFF, dark: 0x062421)
    static let reed = dynamic(light: 0x3A7A4E, dark: 0x7DC08F)
    static let onReed = dynamic(light: 0xFFFFFF, dark: 0x0A2412)
    static let muted = dynamic(light: 0xC9D7D2, dark: 0x24464F)
    static let onMuted = dynamic(light: 0x12303C, dark: 0xE6EFEC)

    /// Water in the icon (fixed: the icon is a bitmap).
    static let calmWater = rgb(0x1E6F6A)
    static let studyWater = rgb(0x35704A)

    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? ShieldPalette.rgb(dark, alpha: alpha)
                : ShieldPalette.rgb(light, alpha: alpha)
        }
    }
}

// MARK: - Bobbly icon

/// Bobbly floating in a round pond. Same geometry as the app's
/// `BobblyCharacter` (fractions of the side length).
private enum BobblyIcon {
    static let side: CGFloat = 120

    static func image(mood: ShieldMood, water: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            draw(mood: mood, water: water, in: context.cgContext)
        }
    }

    private static func draw(mood: ShieldMood, water: UIColor, in cg: CGContext) {
        let s = side
        let colors = Colors(mood)
        let feature = ShieldPalette.rgb(0x1F2A30)

        // Round pond: everything is clipped to a circle.
        UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: s, height: s)).addClip()

        // Stem with a ball, leaning by mood.
        cg.saveGState()
        cg.translateBy(x: s * 0.5, y: s * 0.27)
        cg.rotate(by: colors.stemDroop * .pi / 180)
        feature.setFill()
        UIBezierPath(roundedRect: CGRect(x: -s * 0.02, y: -s * 0.13, width: s * 0.04, height: s * 0.14),
                     cornerRadius: s * 0.02).fill()
        colors.ball.setFill()
        UIBezierPath(ovalIn: CGRect(x: -s * 0.05, y: -s * 0.215, width: s * 0.1, height: s * 0.1)).fill()
        cg.restoreGState()

        // Body, belly and gloss.
        let body = bodyPath(side: s)
        colors.body.setFill()
        body.fill()
        cg.saveGState()
        body.addClip()
        colors.belly.setFill()
        UIBezierPath(ovalIn: CGRect(x: s * 0.05, y: s * 0.73, width: s * 0.9, height: s * 0.44)).fill()
        cg.translateBy(x: s * 0.28, y: s * 0.39)
        cg.rotate(by: -32 * .pi / 180)
        UIColor.white.withAlphaComponent(0.32).setFill()
        UIBezierPath(ovalIn: CGRect(x: -s * 0.085, y: -s * 0.045, width: s * 0.17, height: s * 0.09)).fill()
        cg.restoreGState()

        // Cheeks.
        if colors.cheekAlpha > 0 {
            ShieldPalette.rgb(0xFF7F96, alpha: colors.cheekAlpha).setFill()
            for x in [0.27, 0.73] as [CGFloat] {
                UIBezierPath(ovalIn: CGRect(x: s * (x - 0.05), y: s * (0.665 - 0.0275), width: s * 0.1, height: s * 0.055)).fill()
            }
        }

        drawEyes(mood: mood, colors: colors, feature: feature, side: s, in: cg)
        drawMouth(mood: mood, feature: feature, side: s)

        if mood == .exhausted {
            drawZ(size: s * 0.12, at: CGPoint(x: s * 0.76, y: s * 0.17))
            drawZ(size: s * 0.085, at: CGPoint(x: s * 0.86, y: s * 0.07))
        }

        // Water over Bobbly's base, with a light crest.
        let wave = wavePath(side: s, baseline: s * 0.84, amplitude: s * 0.022, wavelength: s * 0.6, closed: true)
        water.setFill()
        wave.fill()
        let crest = wavePath(side: s, baseline: s * 0.84, amplitude: s * 0.022, wavelength: s * 0.6, closed: false)
        UIColor.white.withAlphaComponent(0.35).setStroke()
        crest.lineWidth = s * 0.012
        crest.lineCapStyle = .round
        crest.stroke()
    }

    // MARK: Parts

    private static func bodyPath(side s: CGFloat) -> UIBezierPath {
        let x0 = s * 0.10, y0 = s * 0.27, w = s * 0.80, h = s * 0.70
        func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: x0 + u * w, y: y0 + v * h) }
        let path = UIBezierPath()
        path.move(to: p(0.5, 1))
        path.addCurve(to: p(0, 0.6), controlPoint1: p(0.16, 1), controlPoint2: p(0, 0.86))
        path.addCurve(to: p(0.5, 0), controlPoint1: p(0, 0.26), controlPoint2: p(0.22, 0))
        path.addCurve(to: p(1, 0.6), controlPoint1: p(0.78, 0), controlPoint2: p(1, 0.26))
        path.addCurve(to: p(0.5, 1), controlPoint1: p(1, 0.86), controlPoint2: p(0.84, 1))
        path.close()
        return path
    }

    private static func drawEyes(mood: ShieldMood, colors: Colors, feature: UIColor, side s: CGFloat, in cg: CGContext) {
        let eyeY = s * 0.555
        let w = s * 0.085
        let h = s * 0.12
        for x in [0.38, 0.62] as [CGFloat] {
            let cx = s * x
            let isLeft = x < 0.5
            switch mood {
            case .thriving:
                let arc = UIBezierPath()
                arc.move(to: CGPoint(x: cx - s * 0.05, y: eyeY + s * 0.025))
                arc.addQuadCurve(to: CGPoint(x: cx + s * 0.05, y: eyeY + s * 0.025),
                                 controlPoint: CGPoint(x: cx, y: eyeY - s * 0.075))
                arc.lineWidth = s * 0.03
                arc.lineCapStyle = .round
                feature.setStroke()
                arc.stroke()

            case .exhausted:
                let arc = UIBezierPath()
                arc.move(to: CGPoint(x: cx - s * 0.05, y: eyeY - s * 0.0075))
                arc.addQuadCurve(to: CGPoint(x: cx + s * 0.05, y: eyeY - s * 0.0075),
                                 controlPoint: CGPoint(x: cx, y: eyeY + s * 0.0625))
                arc.lineWidth = s * 0.026
                arc.lineCapStyle = .round
                feature.setStroke()
                arc.stroke()

            case .happy, .okay, .sad:
                let eyeH = mood == .okay ? h * 0.9 : h
                feature.setFill()
                UIBezierPath(ovalIn: CGRect(x: cx - w / 2, y: eyeY - eyeH / 2, width: w, height: eyeH)).fill()
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: cx + s * 0.014 - s * 0.015, y: eyeY - h * 0.2 - s * 0.015,
                                            width: s * 0.03, height: s * 0.03)).fill()
                if mood == .sad {
                    let angle: CGFloat = (isLeft ? -16 : 16) * .pi / 180
                    // Heavy lid in the body colour.
                    cg.saveGState()
                    cg.translateBy(x: cx, y: eyeY - h * 0.52)
                    cg.rotate(by: angle)
                    colors.body.setFill()
                    UIBezierPath(rect: CGRect(x: -w * 0.9, y: -h * 0.3, width: w * 1.8, height: h * 0.6)).fill()
                    cg.restoreGState()
                    // Brow.
                    cg.saveGState()
                    cg.translateBy(x: cx, y: eyeY - s * 0.105)
                    cg.rotate(by: angle)
                    feature.setFill()
                    UIBezierPath(roundedRect: CGRect(x: -s * 0.045, y: -s * 0.01, width: s * 0.09, height: s * 0.02),
                                 cornerRadius: s * 0.01).fill()
                    cg.restoreGState()
                }
            }
        }
    }

    private static func drawMouth(mood: ShieldMood, feature: UIColor, side s: CGFloat) {
        let (curve, open) = mouthShape(mood)
        let rect = CGRect(x: s * 0.5 - s * 0.085, y: s * 0.69 - s * 0.05, width: s * 0.17, height: s * 0.1)
        let lineWidth = s * 0.026
        let cornerY = rect.midY - curve * rect.height * 0.15

        if open > 0.01 {
            let depth = curve * rect.height * 0.9
            let fill = UIBezierPath()
            fill.move(to: CGPoint(x: rect.minX, y: cornerY))
            fill.addQuadCurve(to: CGPoint(x: rect.maxX, y: cornerY),
                              controlPoint: CGPoint(x: rect.midX, y: rect.midY + depth * 0.2))
            fill.addQuadCurve(to: CGPoint(x: rect.minX, y: cornerY),
                              controlPoint: CGPoint(x: rect.midX, y: rect.midY + depth * (1 + open * 1.4)))
            fill.close()
            feature.setFill()
            fill.fill()
        }

        let line = UIBezierPath()
        line.move(to: CGPoint(x: rect.minX + lineWidth / 2, y: cornerY))
        line.addQuadCurve(to: CGPoint(x: rect.maxX - lineWidth / 2, y: cornerY),
                          controlPoint: CGPoint(x: rect.midX, y: rect.midY + curve * rect.height * 0.9))
        line.lineWidth = lineWidth
        line.lineCapStyle = .round
        feature.setStroke()
        line.stroke()
    }

    private static func mouthShape(_ mood: ShieldMood) -> (curve: CGFloat, open: CGFloat) {
        switch mood {
        case .thriving: return (1, 0.6)
        case .happy: return (0.65, 0)
        case .okay: return (0.2, 0)
        case .sad: return (-0.4, 0)
        case .exhausted: return (-0.12, 0)
        }
    }

    private static func drawZ(size: CGFloat, at point: CGPoint) {
        var font = UIFont.systemFont(ofSize: size, weight: .bold)
        if let rounded = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: rounded, size: size)
        }
        let text = NSAttributedString(string: "z", attributes: [
            .font: font,
            .foregroundColor: ShieldPalette.rgb(0x748B93),
        ])
        text.draw(at: point)
    }

    private static func wavePath(side s: CGFloat, baseline: CGFloat, amplitude: CGFloat,
                                 wavelength: CGFloat, closed: Bool) -> UIBezierPath {
        let path = UIBezierPath()
        func y(_ x: CGFloat) -> CGFloat {
            baseline + sin(x / wavelength * 2 * .pi + 0.6) * amplitude
        }
        path.move(to: CGPoint(x: 0, y: y(0)))
        var x: CGFloat = 2
        while x < s {
            path.addLine(to: CGPoint(x: x, y: y(x)))
            x += 2
        }
        path.addLine(to: CGPoint(x: s, y: y(s)))
        if closed {
            path.addLine(to: CGPoint(x: s, y: s))
            path.addLine(to: CGPoint(x: 0, y: s))
            path.close()
        }
        return path
    }

    // MARK: Colours per mood (mirror of the app's BobblyCharacter)

    private struct Colors {
        let body: UIColor
        let belly: UIColor
        let ball: UIColor
        let cheekAlpha: CGFloat
        let stemDroop: CGFloat

        init(_ mood: ShieldMood) {
            switch mood {
            case .thriving:
                body = ShieldPalette.rgb(0xFF6A35); belly = ShieldPalette.rgb(0xFFE2D1); ball = ShieldPalette.rgb(0xFFC23D)
                cheekAlpha = 0.6; stemDroop = -8
            case .happy:
                body = ShieldPalette.rgb(0xFF7C4A); belly = ShieldPalette.rgb(0xFFE6D9); ball = ShieldPalette.rgb(0xFFB547)
                cheekAlpha = 0.45; stemDroop = -3
            case .okay:
                body = ShieldPalette.rgb(0xEE9466); belly = ShieldPalette.rgb(0xFBE6DA); ball = ShieldPalette.rgb(0xE8A86F)
                cheekAlpha = 0.2; stemDroop = 10
            case .sad:
                body = ShieldPalette.rgb(0xC4917F); belly = ShieldPalette.rgb(0xF0E0D9); ball = ShieldPalette.rgb(0xB3A29A)
                cheekAlpha = 0; stemDroop = 30
            case .exhausted:
                body = ShieldPalette.rgb(0xA49A95); belly = ShieldPalette.rgb(0xE3DDDA); ball = ShieldPalette.rgb(0x958C88)
                cheekAlpha = 0; stemDroop = 62
            }
        }
    }
}
