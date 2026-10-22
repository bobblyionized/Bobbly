//  HomeView.swift
//  Bobbly/Features/Home — Bobbly floating on the waterline (the water's
//  colour is your protection state), running unlocks, today's numbers and
//  quick actions. Contract: HomeViewModel.

import SwiftUI
import DeviceActivity

struct HomeView: View {
    @Bindable var model: HomeViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: HomeViewModel) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    hero
                    if !model.activeUnlocks.isEmpty {
                        unlocksSection
                    }
                    todaySection
                    actionsSection
                    footer
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .bobblyPage()
            .refreshable { model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { model.onAppear() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.greeting)
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
    }

    // MARK: Hero

    private var hero: some View {
        let bobblySize: CGFloat = 112
        let overlap = bobblySize * 0.2
        return PondScene(tone: waterTone, overlap: overlap) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Button {
                    model.openCompanion()
                } label: {
                    BobblyCharacter(mood: model.companion.tier, moodValue: model.companion.mood, size: bobblySize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bobbly, \(model.companion.tier.moodPhrase)")
                .accessibilityHint("Opens Bobbly's page.")

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    LivesView(lives: model.companion.lives, maxLives: model.companion.maxLives)
                    SpeechBubble(text: model.companion.line)
                }
                .padding(.bottom, overlap)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.m)
        } water: {
            statusContent
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.l)
        }
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .animation(Theme.Motion.reveal, value: model.protection)
    }

    private var waterTone: Theme.Water {
        switch model.protection {
        case .setupNeeded: return .setup
        case .protecting: return .calm
        case .unlocked: return .unlocked
        case .studying: return .study
        case .emergency: return .emergency
        case .detached: return .off
        }
    }

    @ViewBuilder private var statusContent: some View {
        switch model.protection {
        case .setupNeeded:
            if model.needsAppRepick {
                WaterStatus(systemImage: "arrow.triangle.2.circlepath",
                            title: "Pick your apps again",
                            detail: "Screen Time access was turned off, so your app picks were cleared. Choose them again to turn blocking back on.") {
                    Button("Pick your apps again") { model.perform(.editBlockedApps) }
                        .buttonStyle(.bobbly(.onWater(.setup)))
                }
            } else {
                WaterStatus(systemImage: "wand.and.stars",
                            title: "Let's set up blocking",
                            detail: "Pick the apps that pull you in. Bobbly takes it from there.") {
                    Button("Set up Bobbly") { model.openSetup() }
                        .buttonStyle(.bobbly(.onWater(.setup)))
                }
            }

        case .protecting(let count):
            WaterStatus(systemImage: "lock.fill",
                        title: "Bobbly's on watch",
                        detail: "Blocking \(blockedSummary(total: count)). Talk to Bobbly when you need one back.") {
                Button("Talk to Bobbly") { model.perform(.talkToBobbly) }
                    .buttonStyle(.bobbly(.onWater(.calm)))
            }

        case .unlocked(let appName, let until):
            WaterStatus(systemImage: "lock.open.fill",
                        title: "\(appName) is open",
                        detail: "It locks again at \(Fmt.time(until)).") {
                HStack(spacing: Theme.Spacing.xs) {
                    CountdownText(until: until, font: Theme.Typography.countdown, color: Theme.Water.onWater)
                    Text("left")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Water.onWaterSecondary)
                }
            }

        case .studying(let name, let until):
            WaterStatus(systemImage: "book.fill",
                        title: "Studying with \(name)",
                        detail: until == nil ? "Runs until you stop it." : "Only your \(name) apps are open.") {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if let until {
                        HStack(spacing: Theme.Spacing.xs) {
                            CountdownText(until: until, font: Theme.Typography.countdown, color: Theme.Water.onWater)
                            Text("left")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Water.onWaterSecondary)
                        }
                    }
                    Button("Open study session") { model.perform(.startStudy) }
                        .buttonStyle(.bobbly(.onWaterSecondary))
                }
            }

        case .emergency(let until):
            WaterStatus(systemImage: "exclamationmark.octagon.fill",
                        title: "Everything is unblocked",
                        detail: "Emergency unblock ends at \(Fmt.time(until)). It never costs a life.") {
                Button("Manage emergency") { model.perform(.emergency) }
                    .buttonStyle(.bobbly(.onWater(.emergency)))
            }

        case .detached:
            WaterStatus(systemImage: "power",
                        title: "Bobbly is off",
                        detail: "Nothing is blocked. You can turn Bobbly back on from the Emergency screen.") {
                Button("Turn Bobbly back on") { model.perform(.emergency) }
                    .buttonStyle(.bobbly(.onWater(.off)))
            }
        }
    }

    /// "3 apps and 1 category", from the separate block-list counts.
    private func blockedSummary(total: Int) -> String {
        var parts: [String] = []
        if model.blockedAppCount > 0 { parts.append(Fmt.count(model.blockedAppCount, "app")) }
        if model.blockedCategoryCount > 0 { parts.append(Fmt.count(model.blockedCategoryCount, "category", "categories")) }
        if model.blockedWebsiteCount > 0 { parts.append(Fmt.count(model.blockedWebsiteCount, "website")) }
        return parts.isEmpty ? Fmt.count(total, "item") : parts.formatted(.list(type: .and))
    }

    // MARK: Unlocks

    private var unlocksSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionTitle("Unlocked right now")
            VStack(spacing: 0) {
                ForEach(model.activeUnlocks) { unlock in
                    UnlockRow(unlock: unlock) { model.relock(unlock) }
                        .padding(.vertical, Theme.Spacing.s)
                    if unlock.id != model.activeUnlocks.last?.id {
                        Divider().overlay(Theme.Palette.hairline)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
    }

    // MARK: Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionTitle("Today")
            if model.showsTodayReport {
                DeviceActivityReport(model.todayReportContext, filter: model.todayReportFilter)
                    .frame(height: 236)
                    .frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: tileColumns, alignment: .leading, spacing: Theme.Spacing.s) {
                StatTile(value: "\(model.interruptionsToday)",
                         label: "Blocked attempts",
                         systemImage: "hand.raised.fill",
                         tint: Theme.Palette.pond)
                StatTile(value: "\(model.unlocksToday)",
                         label: model.unlocksToday == 1 ? "Unlock" : "Unlocks",
                         systemImage: "lock.open.fill",
                         tint: Theme.Palette.amber,
                         detail: model.freeUnlocksLeft > 0 ? "\(model.freeUnlocksLeft) free left" : "The next one costs a life")
                if let minutes = model.screenMinutesToday {
                    StatTile(value: Fmt.minutes(minutes),
                             label: "In tracked apps",
                             systemImage: "hourglass",
                             tint: Theme.Palette.float)
                }
            }
        }
    }

    private var tileColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.s, alignment: .top)]
    }

    // MARK: Actions

    private var buoyActions: [HomeQuickAction] {
        model.quickActions.filter { $0 != .emergency }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(buoyActions) { action in
                        Button { model.perform(action) } label: {
                            IconRow(systemImage: action.systemImage, title: action.title)
                                .padding(Theme.Spacing.s)
                                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    ForEach(buoyActions) { action in
                        Button { model.perform(action) } label: {
                            BuoyLabel(title: action.title, systemImage: action.systemImage)
                        }
                        .buttonStyle(BuoyButtonStyle())
                    }
                }
            }

            if model.quickActions.contains(.emergency) {
                Button { model.perform(.emergency) } label: {
                    IconRow(systemImage: HomeQuickAction.emergency.systemImage,
                            tint: Theme.Palette.signal,
                            title: "Emergency",
                            detail: "Unblock everything, or turn Bobbly off. Always free.") {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                    .padding(Theme.Spacing.s)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        Label(model.engineLabel, systemImage: model.engineKind == .familyControls ? "hourglass" : "square.stack.3d.up")
            .font(.footnote)
            .foregroundStyle(Theme.Palette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Blocking engine: \(model.engineLabel)")
    }
}

// MARK: - Pieces

/// Icon, title, detail and an action, set in white on the water.
private struct WaterStatus<Action: View>: View {
    let systemImage: String
    let title: String
    let detail: String
    let action: Action

    init(systemImage: String, title: String, detail: String, @ViewBuilder action: () -> Action) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.Typography.title)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.Water.onWater)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(detail)
                .font(.callout)
                .foregroundStyle(Theme.Water.onWaterSecondary)
                .fixedSize(horizontal: false, vertical: true)

            action
                .padding(.top, Theme.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One running unlock with its countdown and "Lock again".
private struct UnlockRow: View {
    let unlock: ActiveUnlock
    let onRelock: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = unlock.remaining(at: context.date)
            let total = max(1, unlock.expiresAt.timeIntervalSince(unlock.grantedAt))
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    AppSubjectLabel(subject: unlock.subject, fallbackName: unlock.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(Fmt.clock(remaining))
                        .font(Theme.Typography.countdown)
                        .foregroundStyle(Theme.Palette.ink)
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityLabel("\(Fmt.duration(remaining)) left")
                }
                ProgressTrack(progress: remaining / total, tint: Theme.Palette.amber)
                HStack {
                    Text("Locks at \(Fmt.time(unlock.expiresAt))")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                    Spacer(minLength: Theme.Spacing.xs)
                    Button("Lock again", action: onRelock)
                        .buttonStyle(.bobbly(.secondary, fullWidth: false, compact: true))
                }
            }
        }
    }
}

/// Round quick-action button with its name underneath.
private struct BuoyLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Palette.pond)
                .frame(width: 58, height: 58)
                .background(Theme.Palette.surface, in: Circle())
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct BuoyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    HomeView(model: env.home)
        .environment(env)
}
