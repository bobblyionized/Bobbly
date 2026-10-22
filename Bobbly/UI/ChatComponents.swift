//  ChatComponents.swift
//  Bobbly/UI — chat bubbles, typing indicator and quick-reply chips.
//  Bobbly speaks in rounded type on a light bubble; the user speaks in plain
//  type on pond teal; system notices are small centred lines.

import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    /// Show Bobbly's mini avatar (last bubble of a run of Bobbly messages).
    var showsAvatar: Bool = false
    var avatarMood: CompanionMood = .happy

    var body: some View {
        switch message.sender {
        case .system:
            systemNotice
        case .bobbly:
            HStack(alignment: .bottom, spacing: Theme.Spacing.xs) {
                Group {
                    if showsAvatar {
                        BobblyCharacter(mood: avatarMood, size: 30, isAnimated: false)
                            .accessibilityHidden(true)
                    } else {
                        Color.clear.frame(width: 30, height: 30)
                    }
                }
                bobblyBubble
                Spacer(minLength: 40)
            }
        case .user:
            HStack {
                Spacer(minLength: 64)
                Text(message.text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.onPond)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.Palette.pond,
                                in: UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.bubble,
                                                           bottomLeadingRadius: Theme.Radius.bubble,
                                                           bottomTrailingRadius: 6,
                                                           topTrailingRadius: Theme.Radius.bubble,
                                                           style: .continuous))
                    .accessibilityLabel("You: \(message.text)")
            }
        }
    }

    private var systemNotice: some View {
        Text(message.text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.Palette.inkSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.Palette.sunken, in: Capsule())
            .frame(maxWidth: .infinity)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.bubble,
                               bottomLeadingRadius: 6,
                               bottomTrailingRadius: Theme.Radius.bubble,
                               topTrailingRadius: Theme.Radius.bubble,
                               style: .continuous)
    }

    @ViewBuilder private var bobblyBubble: some View {
        switch message.style {
        case .normal:
            Text(message.text)
                .font(Theme.Typography.voice)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.Palette.surface, in: bubbleShape)
                .accessibilityLabel("Bobbly: \(message.text)")

        case .decision:
            Text(message.text)
                .font(Theme.Typography.voiceStrong)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.Palette.float.opacity(0.16), in: bubbleShape)
                .accessibilityLabel("Bobbly decided: \(message.text)")

        case .warning:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Theme.Palette.amber)
                Text(message.text)
                    .font(Theme.Typography.voice)
                    .foregroundStyle(Theme.Palette.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.Palette.amber.opacity(0.14), in: bubbleShape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bobbly warns: \(message.text)")

        case .commitment:
            VStack(alignment: .leading, spacing: 6) {
                Text("Type this to unlock anyway")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                Text("\u{201C}\(message.text)\u{201D}")
                    .font(Theme.Typography.voiceStrong)
                    .foregroundStyle(Theme.Palette.ink)
                    .textSelection(.disabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.Palette.surface, in: bubbleShape)
            .overlay {
                bubbleShape.stroke(Theme.Palette.pond.opacity(0.6),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("To unlock anyway, type: \(message.text)")
        }
    }
}

/// Three dots rising and falling like ripples while Bobbly "types".
struct TypingIndicator: View {
    var mood: CompanionMood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(mood: CompanionMood = .happy) {
        self.mood = mood
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xs) {
            BobblyCharacter(mood: mood, size: 30, isAnimated: false)
                .accessibilityHidden(true)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Theme.Palette.inkTertiary)
                            .frame(width: 8, height: 8)
                            .offset(y: reduceMotion ? 0 : CGFloat(sin(t * 7 - Double(index) * 0.7)) * -3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.Palette.surface,
                            in: UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.bubble,
                                                       bottomLeadingRadius: 6,
                                                       bottomTrailingRadius: Theme.Radius.bubble,
                                                       topTrailingRadius: Theme.Radius.bubble,
                                                       style: .continuous))
            }
            Spacer(minLength: 40)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bobbly is typing")
    }
}

/// A quick reply under Bobbly's last message. Tint encodes what the reply does.
struct QuickReplyChip: View {
    let reply: QuickReply
    let action: () -> Void

    private var tint: Color {
        switch reply.kind {
        case .giveUp: return Theme.Palette.reed
        case .openEmergency: return Theme.Palette.signal
        case .unlockAnyway, .waitCooldown: return Theme.Palette.amber
        case .app, .reason, .startOver: return Theme.Palette.pond
        }
    }

    private var symbol: String? {
        switch reply.kind {
        case .giveUp: return "leaf"
        case .openEmergency: return "exclamationmark.octagon"
        case .waitCooldown: return "timer"
        case .startOver: return "arrow.counterclockwise"
        case .app: return "app"
        case .reason, .unlockAnyway: return nil
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(reply.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(tint.opacity(0.1), in: Capsule())
            .overlay { Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
