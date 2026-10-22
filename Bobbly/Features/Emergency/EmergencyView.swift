//  EmergencyView.swift
//  Bobbly/Features/Emergency — always-free emergency unblock and emergency
//  detach, each behind a 10-second hold. Contract: EmergencyViewModel.

import SwiftUI

struct EmergencyView: View {
    @State private var model: EmergencyViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: EmergencyViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    Text("Both options are free and never cost Bobbly a life. Hold a button for \(Int(model.holdDuration)) seconds to confirm, so nothing happens by accident.")
                        .font(.callout)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let error = model.errorMessage {
                        InlineNotice(kind: .error, text: error)
                    }

                    unblockPanel
                    detachPanel
                    otherWaysSection
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .bobblyPage()
            .navigationTitle("Emergency")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(model.holdingAction != nil)
                }
            }
        }
        .interactiveDismissDisabled(model.holdingAction != nil)
        .onAppear { model.onAppear() }
        .onDisappear {
            model.cancelHold()
        }
        .bobblyHaptic(trigger: model.confirmation) { _, new in
            new == nil ? nil : SensoryFeedback.success
        }
        .bobblyHaptic(trigger: model.detachPhase) { _, new in
            if case .finished = new { return .success }
            return nil
        }
    }

    // MARK: Unblock

    private var unblockPanel: some View {
        Panel(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                PanelHeader(systemImage: "lock.open.fill", tint: Theme.Palette.amber,
                            title: "Unblock everything",
                            detail: "Every app and website opens for the time you pick, study sessions included. Blocking comes back by itself.")

                if model.isDetached {
                    InlineNotice(kind: .info, text: "Bobbly is detached, so nothing is blocked right now.")
                } else if model.isEmergencyActive, let until = model.emergencyUntil {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                            CountdownText(until: until, font: Theme.Typography.numeral)
                            Text("until \(Fmt.time(until))")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Palette.inkSecondary)
                        }
                        if let confirmation = model.confirmation {
                            InlineNotice(kind: .success, text: confirmation)
                        }
                        Button("End now and block again") { model.endEmergencyNow() }
                            .buttonStyle(.bobblySecondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("For how long?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        FlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
                            ForEach(model.durationOptions, id: \.self) { minutes in
                                ChoiceChip(title: Fmt.option(minutes: minutes),
                                           isSelected: minutes == model.selectedMinutes) {
                                    model.selectedMinutes = minutes
                                }
                                .disabled(model.holdingAction != nil)
                            }
                        }
                    }

                    HoldToConfirmButton(
                        title: "Hold to unblock for \(Fmt.option(minutes: model.selectedMinutes))",
                        systemImage: "hand.tap.fill",
                        tint: Theme.Palette.amber,
                        fillLabelColor: Theme.Palette.onAmber,
                        holdDuration: model.holdDuration,
                        progress: model.holdingAction == .unblock ? model.holdProgress : 0,
                        isHolding: model.holdingAction == .unblock,
                        isEnabled: model.holdingAction != .detach,
                        onPress: { model.beginHold(.unblock) },
                        onRelease: { model.cancelHold() }
                    )
                }
            }
        }
    }

    // MARK: Detach

    private var detachPanel: some View {
        Panel(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                PanelHeader(systemImage: "power", tint: Theme.Palette.signal,
                            title: "Detach Bobbly",
                            detail: "Turns Bobbly off completely. Use it if blocking is stuck or you want Bobbly gone.")

                switch model.detachPhase {
                case .idle:
                    if model.isDetached {
                        detachedState
                    } else {
                        detachExplanation
                        HoldToConfirmButton(
                            title: "Hold to detach Bobbly",
                            systemImage: "power",
                            tint: Theme.Palette.signal,
                            fillLabelColor: Theme.Palette.onSignal,
                            holdDuration: model.holdDuration,
                            progress: model.holdingAction == .detach ? model.holdProgress : 0,
                            isHolding: model.holdingAction == .detach,
                            isEnabled: model.holdingAction != .unblock,
                            onPress: { model.beginHold(.detach) },
                            onRelease: { model.cancelHold() }
                        )
                    }

                case .working:
                    HStack(spacing: Theme.Spacing.s) {
                        ProgressView()
                        Text("Detaching Bobbly…")
                            .font(.callout)
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    .accessibilityElement(children: .combine)

                case .finished(let report):
                    finishedState(report)
                }
            }
        }
    }

    private var detachExplanation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("With \(model.engineKind == .familyControls ? "Screen Time" : "Shortcuts") blocking, detach:")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            ForEach(model.detachExplanation, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Palette.signal)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var detachedState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            InlineNotice(kind: .warning, text: "Bobbly is off. Nothing is blocked and nothing is tracked.")
            Button("Turn Bobbly back on") {
                Task { await model.reattach() }
            }
            .buttonStyle(.bobblyPrimary)
        }
    }

    private func finishedState(_ report: DetachReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            InlineNotice(kind: report.errors.isEmpty ? .success : .warning,
                         text: report.errors.isEmpty ? "Bobbly is detached." : "Bobbly is detached, but some steps had problems.")

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ResultLine(done: report.clearedShields, text: "Shields removed")
                ResultLine(done: report.stoppedMonitoring, text: "Schedules and timers stopped")
                if report.engine == .familyControls {
                    ResultLine(done: report.revokedAuthorization, text: "Screen Time access revoked")
                }
            }

            ForEach(report.errors, id: \.self) { error in
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.signal)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !report.manualSteps.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Finish up yourself")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.ink)
                    NumberedSteps(steps: report.manualSteps, tint: Theme.Palette.signal)
                }
            }

            Button("Turn Bobbly back on") {
                Task { await model.reattach() }
            }
            .buttonStyle(.bobblySecondary)
        }
    }

    // MARK: Other ways

    private var otherWaysSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionTitle("If the app won't open")
            Text("These reach the same emergency screen without opening Bobbly first.")
                .font(.callout)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(model.siriPhrases, id: \.self) { phrase in
                    Label(phrase, systemImage: "mic.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.Palette.ink)
                }
                Label {
                    Text(model.deepLink)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "link")
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.Palette.ink)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
    }
}

// MARK: - Pieces

private struct PanelHeader: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.13), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ResultLine: View {
    let done: Bool
    let text: String

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(Theme.Palette.ink)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(done ? Theme.Palette.reed : Theme.Palette.signal)
        }
        .font(.callout)
        .accessibilityLabel("\(text): \(done ? "done" : "failed")")
    }
}
