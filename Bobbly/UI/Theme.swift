//  Theme.swift
//  Bobbly/UI — design tokens.
//
//  Visual direction: "Still water". Bobbly is a little float bobbing on a
//  pond. The app is the calm water (deep teal ink, misty surfaces), Bobbly is
//  the one bright thing on it (float orange), and the water's colour tells you
//  your protection state at a glance (teal = protected, amber = unlocked,
//  reed = studying, signal red = emergency, slate = Bobbly off).
//
//  Type: SF Pro Rounded is Bobbly's voice and the display face (titles, big
//  numbers, everything Bobbly says). Plain SF Pro is the user's and the
//  system's voice (body copy, controls, data labels).
//
//  Everything here is a token; views never hard-code colours or sizes.

import SwiftUI
import UIKit

enum Theme {

    // MARK: - Colour

    enum Palette {
        /// Page background (mist / night pond).
        static let page = Color(bobblyLight: 0xEDF2EF, dark: 0x0B1F27)
        /// Raised panels sitting on the page.
        static let surface = Color(bobblyLight: 0xF9FBFA, dark: 0x13303A)
        /// Wells, tracks, unselected chips, text fields.
        static let sunken = Color(bobblyLight: 0xE1E9E5, dark: 0x0F2830)
        /// Hairlines and dividers (only where they separate real content).
        static let hairline = Color(bobblyLight: 0xC9D7D2, dark: 0x24464F)

        /// Primary text.
        static let ink = Color(bobblyLight: 0x12303C, dark: 0xE6EFEC)
        /// Secondary text.
        static let inkSecondary = Color(bobblyLight: 0x47616C, dark: 0xA2B8B7)
        /// Tertiary text, axis labels, placeholders.
        static let inkTertiary = Color(bobblyLight: 0x748B93, dark: 0x6F8C90)

        /// Primary actions and selection (deep pond teal).
        static let pond = Color(bobblyLight: 0x1E6F6A, dark: 0x5BC2B5)
        /// Text/icons placed on `pond`.
        static let onPond = Color(bobblyLight: 0xFFFFFF, dark: 0x062421)
        /// Bobbly's colour. Used sparingly outside the character.
        static let float = Color(bobblyLight: 0xF0602C, dark: 0xFF8552)
        /// Emergency, destructive.
        static let signal = Color(bobblyLight: 0xC8243A, dark: 0xFF6372)
        /// Text/icons placed on `signal`.
        static let onSignal = Color(bobblyLight: 0xFFFFFF, dark: 0x2B0309)
        /// Time-limited / caution (running unlocks, warnings).
        static let amber = Color(bobblyLight: 0x95590A, dark: 0xF2B544)
        /// Text/icons placed on `amber`.
        static let onAmber = Color(bobblyLight: 0xFFFFFF, dark: 0x2A1A00)
        /// Study / success.
        static let reed = Color(bobblyLight: 0x3A7A4E, dark: 0x7DC08F)
        /// Lives.
        static let heart = Color(bobblyLight: 0xDD3F57, dark: 0xFF6B7E)

        /// Chart series, fixed order (validated for colour-vision deficiency
        /// on `surface` in both modes). Slot 1 is the single-series colour.
        static let series: [Color] = [
            Color(bobblyLight: 0x009483, dark: 0x14A394),
            Color(bobblyLight: 0xEB6834, dark: 0xD95926),
            Color(bobblyLight: 0x2A78D6, dark: 0x3987E5),
            Color(bobblyLight: 0xEDA100, dark: 0xC98500),
            Color(bobblyLight: 0xE87BA4, dark: 0xD55181),
            Color(bobblyLight: 0x008300, dark: 0x1A9A2A),
            Color(bobblyLight: 0x6250D6, dark: 0x9085E9),
            Color(bobblyLight: 0xE34948, dark: 0xE66767),
        ]
        /// Folded "Other" series in charts.
        static let seriesOther = Color(bobblyLight: 0x9AAAB0, dark: 0x5F7A80)
        /// Gridlines.
        static let grid = Color(bobblyLight: 0xDCE5E1, dark: 0x1E3E48)
    }

    /// The water under Bobbly. Deep enough for white text in both modes.
    enum Water {
        case calm
        case unlocked
        case study
        case emergency
        case off
        case setup

        var color: Color {
            switch self {
            case .calm: return Color(bobblyLight: 0x1E6F6A, dark: 0x1A5D59)
            case .unlocked: return Color(bobblyLight: 0x8A540A, dark: 0x7A4B0C)
            case .study: return Color(bobblyLight: 0x35704A, dark: 0x2D5F40)
            case .emergency: return Color(bobblyLight: 0xB0233A, dark: 0x972033)
            case .off: return Color(bobblyLight: 0x52646B, dark: 0x40525A)
            case .setup: return Color(bobblyLight: 0x24414D, dark: 0x1C3945)
            }
        }

        /// Text and icons on the water.
        static let onWater = Color.white
        static let onWaterSecondary = Color.white.opacity(0.78)
    }

    // MARK: - Type

    enum Typography {
        /// Screen greeting / big titles. Rounded, heavy.
        static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)
        /// Section-level titles and card headlines.
        static let title = Font.system(.title2, design: .rounded).weight(.bold)
        /// Smaller rounded heading (panel titles).
        static let heading = Font.system(.title3, design: .rounded).weight(.semibold)
        /// Plain UI heading (rows, buttons).
        static let label = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let footnote = Font.footnote
        static let caption = Font.caption

        /// Bobbly speaking (chat bubbles, speech bubbles).
        static let voice = Font.system(.body, design: .rounded)
        /// Bobbly saying something that matters (decisions).
        static let voiceStrong = Font.system(.body, design: .rounded).weight(.semibold)
        /// Stat values.
        static let numeral = Font.system(.title, design: .rounded).weight(.semibold)
        /// Smaller stat values.
        static let numeralSmall = Font.system(.title3, design: .rounded).weight(.semibold)
        /// Ticking countdowns (fixed-width digits so they don't jitter).
        static let countdown = Font.system(.title3, design: .rounded).weight(.semibold).monospacedDigit()
    }

    // MARK: - Space

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 40
        /// Horizontal page gutter.
        static let gutter: CGFloat = 20
    }

    /// Radii follow hierarchy: the bigger the container, the softer the corner.
    enum Radius {
        static let hero: CGFloat = 32
        static let panel: CGFloat = 22
        static let row: CGFloat = 14
        static let bubble: CGFloat = 20
        static let small: CGFloat = 8
    }

    // MARK: - Motion

    enum Motion {
        /// Button presses.
        static let press = Animation.snappy(duration: 0.18)
        /// State changes that answer an action (selection, reveal).
        static let standard = Animation.snappy(duration: 0.32)
        /// Larger reveals (result cards).
        static let reveal = Animation.spring(response: 0.5, dampingFraction: 0.82)
        /// Bobbly's idle bob, seconds per cycle.
        static let bobPeriod: Double = 3.4
    }
}

// MARK: - Colour helpers

extension UIColor {
    /// 0xRRGGBB.
    convenience init(bobblyHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    /// Light/dark pair that follows the trait collection.
    convenience init(bobblyLight light: UInt32, dark: UInt32) {
        self.init(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(bobblyHex: dark) : UIColor(bobblyHex: light)
        })
    }
}

extension Color {
    /// Light/dark pair from 0xRRGGBB values.
    init(bobblyLight light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor(bobblyLight: light, dark: dark))
    }

    /// A fixed colour (same in both modes) from 0xRRGGBB.
    init(bobblyHex hex: UInt32) {
        self.init(uiColor: UIColor(bobblyHex: hex))
    }
}

// MARK: - Scaled fonts

/// A fixed-size font that still follows Dynamic Type.
private struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let monospacedDigits: Bool

    init(size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight, design: Font.Design, monospacedDigits: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
        self.monospacedDigits = monospacedDigits
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight, design: design)
        return content.font(monospacedDigits ? font.monospacedDigit() : font)
    }
}

extension View {
    /// Large display numbers (timers, hero figures) that scale with Dynamic Type.
    func scaledFont(size: CGFloat,
                    relativeTo style: Font.TextStyle = .largeTitle,
                    weight: Font.Weight = .semibold,
                    design: Font.Design = .rounded,
                    monospacedDigits: Bool = false) -> some View {
        modifier(ScaledFontModifier(size: size, relativeTo: style, weight: weight, design: design, monospacedDigits: monospacedDigits))
    }
}

// MARK: - Haptics

/// Plays `feedback` when `trigger` changes, if the user has haptics on.
private struct BobblyHapticModifier<Trigger: Equatable>: ViewModifier {
    @Environment(AppEnvironment.self) private var env: AppEnvironment?
    let feedback: SensoryFeedback
    let trigger: Trigger

    func body(content: Content) -> some View {
        let enabled = env?.preferences.hapticsEnabled ?? true
        return content.sensoryFeedback(feedback, trigger: trigger) { _, _ in enabled }
    }
}

/// Picks the feedback from the old/new trigger values (nil = none).
private struct BobblyDynamicHapticModifier<Trigger: Equatable>: ViewModifier {
    @Environment(AppEnvironment.self) private var env: AppEnvironment?
    let trigger: Trigger
    let feedback: (Trigger, Trigger) -> SensoryFeedback?

    func body(content: Content) -> some View {
        let enabled = env?.preferences.hapticsEnabled ?? true
        let pick = feedback
        return content.sensoryFeedback(trigger: trigger) { old, new in
            enabled ? pick(old, new) : nil
        }
    }
}

extension View {
    /// Haptic feedback that respects Settings › Haptics.
    func bobblyHaptic<Trigger: Equatable>(_ feedback: SensoryFeedback, trigger: Trigger) -> some View {
        modifier(BobblyHapticModifier(feedback: feedback, trigger: trigger))
    }

    /// Haptic chosen from the change, e.g. success vs error. Respects Settings › Haptics.
    func bobblyHaptic<Trigger: Equatable>(trigger: Trigger,
                                          _ feedback: @escaping (_ old: Trigger, _ new: Trigger) -> SensoryFeedback?) -> some View {
        modifier(BobblyDynamicHapticModifier(trigger: trigger, feedback: feedback))
    }

    /// The standard page background, edge to edge.
    func bobblyPage() -> some View {
        background { Theme.Palette.page.ignoresSafeArea() }
    }
}
