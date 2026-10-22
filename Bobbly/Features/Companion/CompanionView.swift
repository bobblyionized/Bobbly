//  CompanionView.swift
//  Bobbly/Features/Companion — Bobbly up close: tap to pet, mood, lives,
//  streak and how it all works. Contract: CompanionViewModel.

import SwiftUI

struct CompanionView: View {
    @State private var model: CompanionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: CompanionViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    hero
                    moodPanel
                    statsGrid
                    rulesSection
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .bobblyPage()
            .navigationTitle("Bobbly")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { model.onAppear() }
        .bobblyHaptic(.impact(weight: .light), trigger: model.petCount)
    }

    // MARK: Hero

    private var tone: Theme.Water {
        model.snapshot.tier == .exhausted ? .off : .calm
    }

    private var hero: some View {
        let size: CGFloat = 176
        let overlap = size * 0.2
        return PondScene(tone: tone, overlap: overlap, amplitude: 6) {
            VStack(spacing: Theme.Spacing.s) {
                SpeechBubble(text: model.speech.isEmpty ? model.snapshot.line : model.speech,
                             tail: .bottom, fill: Theme.Palette.sunken, font: Theme.Typography.voiceStrong)
                    .padding(.horizontal, Theme.Spacing.l)
                Button {
                    model.pet()
                } label: {
                    BobblyCharacter(mood: model.snapshot.tier, moodValue: model.snapshot.mood, size: size)
                        .phaseAnimator([CGFloat(1), 1.14, 0.95], trigger: model.petCount) { content, scale in
                            content.scaleEffect(scale, anchor: .bottom)
                        } animation: { _ in
                            Animation.spring(response: 0.22, dampingFraction: 0.55)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bobbly, \(model.snapshot.tier.moodPhrase)")
                .accessibilityHint("Pets Bobbly.")
            }
            .padding(.top, Theme.Spacing.l)
            .frame(maxWidth: .infinity)
        } water: {
            VStack(spacing: Theme.Spacing.xs) {
                Text(model.snapshot.tier.moodTitle)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Water.onWater)
                LivesView(lives: model.snapshot.lives, maxLives: model.snapshot.maxLives, font: .title3,
                          tint: .white, emptyTint: Theme.Water.onWaterSecondary)
                Text("Tap Bobbly to say hi.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Water.onWaterSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.l)
        }
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
    }

    // MARK: Mood

    private var moodPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Mood")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Text("\(model.snapshot.mood) of 100")
                        .font(Theme.Typography.numeralSmall)
                        .foregroundStyle(Theme.Palette.ink)
                        .contentTransition(.numericText())
                }
                ProgressTrack(progress: model.snapshot.moodFraction, tint: Theme.Palette.float, height: 10)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Lives refill and mood resets in \(Fmt.duration(model.timeUntilReset(at: context.date))). Always tomorrow.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statsGrid: some View {
        let columns: [GridItem] = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .top),
               GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .top)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.s) {
            StatTile(value: Fmt.minutes(Double(model.snapshot.focusMinutesToday)), label: "Focus today",
                     systemImage: "book.fill", tint: Theme.Palette.reed)
            StatTile(value: "\(model.snapshot.livesLostToday)", label: "Lives lost today",
                     systemImage: "heart.slash.fill", tint: Theme.Palette.heart)
            StatTile(value: Fmt.count(model.snapshot.currentStreak, "day"), label: "Current streak",
                     systemImage: "flame.fill", tint: Theme.Palette.float)
            StatTile(value: Fmt.count(model.snapshot.bestStreak, "day"), label: "Best streak",
                     systemImage: "trophy.fill", tint: Theme.Palette.amber)
        }
    }

    // MARK: Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionTitle("How Bobbly works")
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(model.rules, id: \.self) { rule in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Circle()
                            .fill(Theme.Palette.float)
                            .frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[VerticalAlignment.center] + 4 }
                            .accessibilityHidden(true)
                        Text(rule)
                            .font(.callout)
                            .foregroundStyle(Theme.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
    }
}
