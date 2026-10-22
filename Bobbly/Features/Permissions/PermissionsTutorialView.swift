//  PermissionsTutorialView.swift
//  Bobbly/Features/Permissions — paged setup, one step per page, each with a
//  live done / not-done status and a button that jumps to the right place.
//  Contract: PermissionsTutorialViewModel.

import SwiftUI

struct PermissionsTutorialView: View {
    @State private var model: PermissionsTutorialViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    init(model: PermissionsTutorialViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xs)

            if model.steps.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                TabView(selection: $model.currentIndex) {
                    ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                        StepPage(step: step, totalSteps: model.steps.count, model: model)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            bottomBar
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.vertical, Theme.Spacing.s)
        }
        .bobblyPage()
        .task { await model.onAppear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshStatuses() } }
        }
        .sheet(isPresented: $model.isBlockedAppsPresented, onDismiss: refresh) {
            BlockedAppsView(model: env.makeBlockedAppsViewModel())
                .tint(Theme.Palette.pond)
        }
        .sheet(isPresented: $model.isWhitelistEditorPresented, onDismiss: refresh) {
            WhitelistEditorView(model: env.study, whitelistID: nil)
                .tint(Theme.Palette.pond)
        }
        .sheet(isPresented: $model.isEmergencyPresented) {
            EmergencyView(model: env.makeEmergencyViewModel())
                .tint(Theme.Palette.pond)
        }
        .bobblyHaptic(trigger: model.completedCount) { old, new in
            new > old ? SensoryFeedback.success : nil
        }
    }

    private func refresh() {
        Task { await model.refreshStatuses() }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Set up Bobbly")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close") { model.finish() }
                    .font(.body.weight(.semibold))
                    .tint(Theme.Palette.pond)
            }
            HStack(spacing: 4) {
                ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                    Capsule()
                        .fill(segmentColor(step))
                        .frame(height: index == model.currentIndex ? 8 : 5)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle().inset(by: -8))
                        .onTapGesture {
                            withAnimation(Theme.Motion.standard) { model.goTo(step.id) }
                        }
                }
            }
            .frame(height: 8)
            .animation(Theme.Motion.standard, value: model.currentIndex)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(model.currentIndex + 1) of \(model.steps.count). \(model.completedCount) done.")
        }
    }

    private func segmentColor(_ step: TutorialStep) -> Color {
        switch step.status {
        case .complete: return Theme.Palette.reed
        case .incomplete: return Theme.Palette.signal.opacity(0.55)
        case .optional, .checking: return Theme.Palette.hairline
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            if !model.isFirstStep {
                Button("Back") {
                    withAnimation(Theme.Motion.standard) { model.back() }
                }
                .buttonStyle(.bobbly(.secondary, fullWidth: false))
            }
            Spacer(minLength: 0)
            Button(model.isLastStep ? "Done" : "Next") {
                if model.isLastStep {
                    model.finish()
                } else {
                    withAnimation(Theme.Motion.standard) { model.next() }
                }
            }
            .buttonStyle(.bobbly(.primary, fullWidth: false))
            .disabled(model.steps.isEmpty)
        }
    }
}

// MARK: - Page

private struct StepPage: View {
    let step: TutorialStep
    let totalSteps: Int
    let model: PermissionsTutorialViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                illustration

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(step.title)
                        .font(Theme.Typography.display)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(step.body)
                        .font(.body)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                StepStatusBadge(status: step.status, text: step.statusText)

                if !step.instructions.isEmpty {
                    NumberedSteps(steps: step.instructions)
                        .padding(Theme.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Palette.surface,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                }

                actions

                if step.id == .shortcutsFallback {
                    ShortcutsCatalogSection(model: model)
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private var illustration: some View {
        PondScene(tone: step.status == .complete ? .study : .setup, overlap: 18, amplitude: 4) {
            Group {
                if step.id == .trustDeveloper {
                    BobblyCharacter(mood: .happy, size: 96)
                } else {
                    Image(systemName: step.systemImage)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Theme.Palette.pond)
                        .frame(width: 92, height: 92)
                        .background(Theme.Palette.sunken, in: Circle())
                        .padding(.bottom, 4)
                }
            }
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.l)
        } water: {
            Text("Step \(step.number) of \(totalSteps)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Water.onWaterSecondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, Theme.Spacing.s)
        }
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
    }

    @ViewBuilder private var actions: some View {
        if step.primary != nil || step.secondary != nil {
            VStack(spacing: Theme.Spacing.s) {
                if let primary = step.primary {
                    Button {
                        Task { await model.perform(primary.action) }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            if model.isWorking {
                                ProgressView()
                                    .tint(Theme.Palette.onPond)
                            }
                            Label(primary.title, systemImage: primary.systemImage)
                        }
                    }
                    .buttonStyle(.bobblyPrimary)
                    .disabled(model.isWorking)
                }
                if let secondary = step.secondary {
                    Button {
                        Task { await model.perform(secondary.action) }
                    } label: {
                        Label(secondary.title, systemImage: secondary.systemImage)
                    }
                    .buttonStyle(.bobblySecondary)
                    .disabled(model.isWorking)
                }
            }
        }
    }
}

// MARK: - Shortcuts fallback catalog

private struct ShortcutsCatalogSection: View {
    @Bindable var model: PermissionsTutorialViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionTitle("Your apps")
            Text(model.automationRunCount > 0
                 ? "Bobbly has seen \(Fmt.count(model.automationRunCount, "automation run")). They're working."
                 : "Track an app, then follow its steps to create its two automations.")
                .font(.callout)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .accessibilityHidden(true)
                TextField("Find an app", text: $model.catalogQuery)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Theme.Palette.surface, in: Capsule())

            VStack(spacing: 0) {
                ForEach(model.catalog) { app in
                    CatalogRow(app: app,
                               isTracked: model.isTracked(app),
                               isExpanded: model.expandedCatalogAppID == app.id,
                               steps: model.expandedCatalogAppID == app.id ? model.automationSteps(for: app) : [],
                               onToggleTracked: { model.toggleTracked(app) },
                               onToggleExpanded: {
                                   withAnimation(Theme.Motion.standard) {
                                       model.expandedCatalogAppID = model.expandedCatalogAppID == app.id ? nil : app.id
                                   }
                               })
                    if app.id != model.catalog.last?.id {
                        Divider().overlay(Theme.Palette.hairline)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
    }
}

private struct CatalogRow: View {
    let app: CatalogApp
    let isTracked: Bool
    let isExpanded: Bool
    let steps: [String]
    let onToggleTracked: () -> Void
    let onToggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                AppGlyph(systemImage: app.symbol)
                Text(app.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: Theme.Spacing.xs)
                Button(isTracked ? "Tracking" : "Track", action: onToggleTracked)
                    .buttonStyle(.bobbly(isTracked ? .primary : .secondary, fullWidth: false, compact: true))
                    .accessibilityLabel(isTracked ? "Stop tracking \(app.name)" : "Track \(app.name)")
                Button(action: onToggleExpanded) {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Hide steps for \(app.name)" : "Show steps for \(app.name)")
            }
            if isExpanded {
                NumberedSteps(steps: steps)
                    .padding(.bottom, Theme.Spacing.xs)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }
}
