//  GateView.swift
//  Bobbly/Features/Gate — the full-screen block opened by bobbly://gate.
//  Bobbly floats at the waterline; below it, what's blocked and the two
//  choices: talk to Bobbly or go back. Contract: GateViewModel.

import SwiftUI

struct GateView: View {
    @State private var model: GateViewModel
    @Environment(\.openURL) private var openURL
    @State private var didAppear = false

    init(model: GateViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            PondBackdrop(tone: tone)
            GeometryReader { proxy in
                ScrollView {
                    scene(bobblySize: min(188, proxy.size.width * 0.48))
                        .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear {
            model.onAppear()
            didAppear = true
        }
        .bobblyHaptic(.impact(weight: .medium), trigger: didAppear)
    }

    private func scene(bobblySize: CGFloat) -> some View {
        let overlap = bobblySize * 0.2
        return PondScene(tone: tone, overlap: overlap, amplitude: 7) {
            VStack(spacing: Theme.Spacing.m) {
                Spacer(minLength: Theme.Spacing.xl)
                LivesView(lives: model.companion.lives, maxLives: model.companion.maxLives, font: .subheadline)
                SpeechBubble(text: bobblyLine, tail: .bottom, fill: Theme.Palette.surface,
                             font: Theme.Typography.voiceStrong)
                    .padding(.horizontal, Theme.Spacing.xl)
                BobblyCharacter(mood: model.companion.tier, moodValue: model.companion.mood, size: bobblySize)
            }
            .frame(maxWidth: .infinity)
        } water: {
            waterContent
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var waterContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(model.headline)
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.Water.onWater)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(model.message)
                    .font(.body)
                    .foregroundStyle(Theme.Water.onWaterSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.isAllowedNow {
                if let until = model.unlockedUntil {
                    HStack(spacing: Theme.Spacing.xs) {
                        CountdownText(until: until, color: Theme.Water.onWater)
                        Text("left")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Water.onWaterSecondary)
                    }
                }
                if let url = model.reopenURL {
                    Button("Open \(model.appName)") { openURL(url) }
                        .buttonStyle(.bobbly(.onWater(tone)))
                }
                Button("Close") { model.goBack() }
                    .buttonStyle(.bobbly(.onWaterSecondary))
            } else {
                Button {
                    model.talkToBobbly()
                } label: {
                    Label("Talk to Bobbly", systemImage: "bubble.left.fill")
                }
                .buttonStyle(.bobbly(.onWater(tone)))

                Button("Go back") { model.goBack() }
                    .buttonStyle(.bobbly(.onWaterSecondary))

                Text(model.unlocksToday == 0
                     ? "Going back keeps Bobbly happy."
                     : "\(Fmt.count(model.unlocksToday, "unlock")) so far today.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Water.onWaterSecondary)
                    .frame(maxWidth: .infinity)
            }

            Button {
                model.openEmergency()
            } label: {
                Label("Emergency", systemImage: "exclamationmark.octagon")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Water.onWaterSecondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.xs)
            .accessibilityHint("Unblock everything or turn Bobbly off.")
        }
    }

    private var tone: Theme.Water {
        switch model.decision {
        case .blocked(.studySession): return .study
        case .blocked(.blockedApp): return .calm
        case .allowed(.unlocked): return .unlocked
        case .allowed(.emergency): return .emergency
        case .allowed(.detached): return .off
        case .allowed(.whitelisted), .allowed(.notBlocked): return .calm
        }
    }

    private var bobblyLine: String {
        switch model.decision {
        case .blocked(.studySession): return "We're studying, remember?"
        case .blocked(.blockedApp): return "Wait! Let's talk before you scroll."
        case .allowed(.unlocked): return "Your time's still running."
        case .allowed: return "You're free to go."
        }
    }
}
