//  Buttons.swift
//  Bobbly/UI — button styles and the hold-to-confirm control.

import SwiftUI

// MARK: - Button styles

struct BobblyButtonStyle: ButtonStyle {
    enum Kind {
        /// Main action on a screen. Pond teal pill.
        case primary
        /// Secondary action. Tinted pill.
        case secondary
        /// Text-only action.
        case quiet
        /// Destructive or emergency.
        case danger
        /// Main action placed on water (white pill, water-coloured text).
        case onWater(Theme.Water)
        /// Secondary action on water (translucent white).
        case onWaterSecondary
    }

    var kind: Kind = .primary
    var isFullWidth: Bool = true
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButtonBody(configuration: configuration, kind: kind, isFullWidth: isFullWidth, isCompact: isCompact)
    }

    private struct StyledButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let isFullWidth: Bool
        let isCompact: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(isCompact ? Theme.Typography.callout.weight(.semibold) : Theme.Typography.label)
                .multilineTextAlignment(.center)
                .padding(.horizontal, isCompact ? 14 : 20)
                .padding(.vertical, isCompact ? 8 : 14)
                .frame(maxWidth: isFullWidth ? .infinity : nil, minHeight: isCompact ? 36 : 52)
                .foregroundStyle(textColor)
                .background(fillColor, in: Capsule())
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Theme.Motion.press, value: configuration.isPressed)
        }

        private var textColor: Color {
            switch kind {
            case .primary: return Theme.Palette.onPond
            case .secondary: return Theme.Palette.pond
            case .quiet: return Theme.Palette.pond
            case .danger: return Theme.Palette.onSignal
            case .onWater(let tone): return tone.color
            case .onWaterSecondary: return .white
            }
        }

        private var fillColor: Color {
            switch kind {
            case .primary: return Theme.Palette.pond
            case .secondary: return Theme.Palette.pond.opacity(0.12)
            case .quiet: return .clear
            case .danger: return Theme.Palette.signal
            case .onWater: return .white
            case .onWaterSecondary: return Color.white.opacity(0.16)
            }
        }
    }
}

extension ButtonStyle where Self == BobblyButtonStyle {
    static var bobblyPrimary: BobblyButtonStyle { BobblyButtonStyle(kind: .primary) }
    static var bobblySecondary: BobblyButtonStyle { BobblyButtonStyle(kind: .secondary) }
    static var bobblyQuiet: BobblyButtonStyle { BobblyButtonStyle(kind: .quiet) }
    static var bobblyDanger: BobblyButtonStyle { BobblyButtonStyle(kind: .danger) }

    static func bobbly(_ kind: BobblyButtonStyle.Kind, fullWidth: Bool = true, compact: Bool = false) -> BobblyButtonStyle {
        BobblyButtonStyle(kind: kind, isFullWidth: fullWidth, isCompact: compact)
    }
}

// MARK: - Hold to confirm

/// A pill you press and hold. The ViewModel owns the timing; this view only
/// reports finger down / finger up and draws `progress` (0–1) as a fill that
/// sweeps left to right, inverting the label as it passes.
///
/// Finger-up is detected with `@GestureState`, which also resets when the
/// system cancels the gesture (e.g. a scroll takes over), so a hold can never
/// keep running after the finger is gone.
struct HoldToConfirmButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    /// Label colour where the fill has passed (must contrast with `tint`).
    let fillLabelColor: Color
    let holdDuration: TimeInterval
    /// 0–1 while this button is being held, else 0.
    let progress: Double
    let isHolding: Bool
    let isEnabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @GestureState private var isTouching = false

    init(title: String,
         systemImage: String,
         tint: Color = Theme.Palette.signal,
         fillLabelColor: Color = Theme.Palette.onSignal,
         holdDuration: TimeInterval,
         progress: Double,
         isHolding: Bool,
         isEnabled: Bool = true,
         onPress: @escaping () -> Void,
         onRelease: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.fillLabelColor = fillLabelColor
        self.holdDuration = holdDuration
        self.progress = progress
        self.isHolding = isHolding
        self.isEnabled = isEnabled
        self.onPress = onPress
        self.onRelease = onRelease
    }

    private var secondsLeft: Int {
        max(0, Int((holdDuration * (1 - progress)).rounded(.up)))
    }

    private var currentTitle: String {
        isHolding ? "Keep holding, \(secondsLeft)" : title
    }

    var body: some View {
        ZStack {
            Capsule().fill(tint.opacity(0.13))
            label(color: tint)
            GeometryReader { proxy in
                ZStack {
                    Rectangle().fill(tint)
                    label(color: fillLabelColor)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: proxy.size.width * CGFloat(min(1, max(0, progress))))
                }
            }
        }
        .frame(minHeight: 64)
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(tint.opacity(isHolding ? 0 : 0.35), lineWidth: 1.5)
        }
        .contentShape(Capsule())
        .scaleEffect(isTouching ? 0.98 : 1)
        .animation(Theme.Motion.press, value: isTouching)
        .animation(.linear(duration: 0.05), value: progress)
        .opacity(isEnabled ? 1 : 0.4)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isTouching) { _, state, _ in state = true },
            including: isEnabled ? .all : .none
        )
        .onChange(of: isTouching) { _, touching in
            if touching { onPress() } else { onRelease() }
        }
        .bobblyHaptic(.impact(weight: .light), trigger: isHolding ? secondsLeft : -1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isHolding ? "\(secondsLeft) seconds left" : "")
        .accessibilityHint("Starts a \(Int(holdDuration))-second countdown. It finishes unless you cancel.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if isEnabled { onPress() } }
        .accessibilityAction(named: "Cancel hold") { onRelease() }
    }

    private func label(color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
            Text(currentTitle)
                .font(Theme.Typography.label)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}
