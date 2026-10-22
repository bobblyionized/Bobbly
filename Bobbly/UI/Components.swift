//  Components.swift
//  Bobbly/UI — shared building blocks: panels, section titles, stat tiles,
//  chips, flow layout, rings, notices, empty states, countdowns.

import SwiftUI

// MARK: - Panel

/// A raised tonal surface. No drop shadow: tone alone separates it from the page.
struct Panel<Content: View>: View {
    var padding: CGFloat
    var radius: CGFloat
    var fill: Color
    let content: Content

    init(padding: CGFloat = Theme.Spacing.m,
         radius: CGFloat = Theme.Radius.panel,
         fill: Color = Theme.Palette.surface,
         @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Section title

struct SectionTitle<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.xs)
            accessory
        }
    }
}

extension SectionTitle where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - Stat tile

/// A labelled number. Value in rounded type, label in plain secondary text.
struct StatTile: View {
    let value: String
    let label: String
    var systemImage: String?
    var tint: Color = Theme.Palette.pond
    var detail: String?
    var fill: Color = Theme.Palette.surface

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(value)
                .font(Theme.Typography.numeral)
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chips

/// Single-choice chip (durations, ranges, presets).
struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? Theme.Palette.onPond : Theme.Palette.ink)
                .background(isSelected ? Theme.Palette.pond : Theme.Palette.sunken, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.standard, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Wraps children onto as many lines as needed (chips, suggestions).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let width = min(size.width, maxWidth)
            if x > 0 && x + width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let width = min(size.width, bounds.width)
            if x > bounds.minX && x + width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: size.height))
            x += width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Progress

/// Circular progress (study timer, cooldown).
struct RingProgress: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    var tint: Color = Theme.Palette.pond
    var track: Color = Theme.Palette.sunken

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// Thin horizontal progress (unlock time left, mood).
struct ProgressTrack: View {
    let progress: Double
    var tint: Color = Theme.Palette.pond
    var track: Color = Theme.Palette.sunken
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * CGFloat(min(1, max(0, progress)))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Countdown

/// "7:05" ticking down to `until`, refreshed once a second.
struct CountdownText: View {
    let until: Date
    var font: Font = Theme.Typography.countdown
    var color: Color = Theme.Palette.ink

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Fmt.clock(until.timeIntervalSince(context.date)))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel("\(Fmt.duration(until.timeIntervalSince(context.date))) left")
        }
    }
}

// MARK: - Notices

/// Inline error / confirmation / info line.
struct InlineNotice: View {
    enum Kind { case error, success, warning, info }

    let kind: Kind
    let text: String

    private var tint: Color {
        switch kind {
        case .error: return Theme.Palette.signal
        case .success: return Theme.Palette.reed
        case .warning: return Theme.Palette.amber
        case .info: return Theme.Palette.pond
        }
    }

    private var symbol: String {
        switch kind {
        case .error: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// ✅ / ❌ / optional / checking, with its explanation.
struct StepStatusBadge: View {
    let status: StepStatus
    let text: String

    private var tint: Color {
        switch status {
        case .complete: return Theme.Palette.reed
        case .incomplete: return Theme.Palette.signal
        case .optional, .checking: return Theme.Palette.inkSecondary
        }
    }

    private var symbol: String {
        switch status {
        case .complete: return "checkmark.circle.fill"
        case .incomplete: return "xmark.circle.fill"
        case .optional: return "circle.dashed"
        case .checking: return "circle.dotted"
        }
    }

    private var spokenStatus: String {
        switch status {
        case .complete: return "Done"
        case .incomplete: return "Not done"
        case .optional: return "Optional"
        case .checking: return "Checking"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if status == .checking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spokenStatus). \(text)")
    }
}

// MARK: - Empty state

/// Empty screens are an invitation to act: a resting Bobbly, what's missing,
/// and the action that fixes it.
struct EmptyStateView<Actions: View>: View {
    let title: String
    let message: String
    var mood: CompanionMood = .okay
    let actions: Actions

    init(title: String, message: String, mood: CompanionMood = .okay, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.mood = mood
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            BobblyCharacter(mood: mood, size: 84, isAnimated: false)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions
                .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .padding(.horizontal, Theme.Spacing.m)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: String, message: String, mood: CompanionMood = .okay) {
        self.init(title: title, message: message, mood: mood) { EmptyView() }
    }
}

// MARK: - Rows

/// Icon + title (+ detail) row used in custom lists.
struct IconRow<Trailing: View>: View {
    let systemImage: String
    var tint: Color = Theme.Palette.pond
    let title: String
    var detail: String?
    let trailing: Trailing

    init(systemImage: String, tint: Color = Theme.Palette.pond, title: String, detail: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            trailing
        }
        .contentShape(Rectangle())
    }
}

extension IconRow where Trailing == EmptyView {
    init(systemImage: String, tint: Color = Theme.Palette.pond, title: String, detail: String? = nil) {
        self.init(systemImage: systemImage, tint: tint, title: title, detail: detail) { EmptyView() }
    }
}

/// Numbered how-to steps. Only for content that really is a sequence.
struct NumberedSteps: View {
    let steps: [String]
    var tint: Color = Theme.Palette.pond

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .frame(width: 22, height: 22)
                        .background(tint.opacity(0.13), in: Circle())
                    Text(step)
                        .font(.callout)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
