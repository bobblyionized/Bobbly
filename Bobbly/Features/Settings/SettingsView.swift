//  SettingsView.swift
//  Bobbly/Features/Settings — which engine is blocking and why, unlock
//  preferences, the tutorial, emergency entry and diagnostics.
//  Contract: SettingsViewModel.

import SwiftUI

struct SettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var isLogExpanded = false
    @State private var isConfirmingShortcuts = false

    init(model: SettingsViewModel) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            List {
                engineSection
                unlocksSection
                bobblySection
                helpSection
                emergencySection
                diagnosticsSection
            }
            .scrollContentBackground(.hidden)
            .bobblyPage()
            .navigationTitle("Settings")
            .refreshable { model.refresh() }
            .confirmationDialog("Use Shortcuts automations instead?",
                                isPresented: $isConfirmingShortcuts, titleVisibility: .visible) {
                Button("Use Shortcuts") { model.switchToShortcutsFallback() }
            } message: {
                Text("Shortcuts blocking is softer: it can be bypassed by deleting the automations. It stays on until you retry Screen Time access.")
            }
        }
        .onAppear { model.onAppear() }
        .bobblyHaptic(.success, trigger: model.didCopyDiagnostics)
    }

    // MARK: Engine

    private var engineSection: some View {
        Section {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Image(systemName: engineSymbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(engineTint)
                    .frame(width: 34, height: 34)
                    .background(engineTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.engineState.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(model.engineExplanation)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)

            if !model.diagnostics.appGroupAvailable {
                WarningRow(title: "Shared storage is missing",
                           detail: "Your signing tool dropped the App Group, so the shield and timers can't read Bobbly's settings. Re-sign Bobbly and keep its App Group entitlement.")
            }
            if model.diagnostics.usingFallbackDataStore {
                WarningRow(title: "Using temporary storage",
                           detail: "Bobbly couldn't open its database, so history resets when the app closes.")
            }

            if model.canRetryScreenTime {
                Button {
                    Task { await model.retryScreenTimeAccess() }
                } label: {
                    HStack {
                        Label("Retry Screen Time access", systemImage: "hourglass")
                        Spacer()
                        if model.isRequestingAuthorization {
                            ProgressView()
                        }
                    }
                }
                .disabled(model.isRequestingAuthorization)
            }

            if model.engineState == .familyControls {
                Button {
                    isConfirmingShortcuts = true
                } label: {
                    Label("Use Shortcuts automations instead", systemImage: "square.stack.3d.up")
                }
            }
        } header: {
            Text("Blocking")
        }
        .listRowBackground(Theme.Palette.surface)
    }

    private var engineSymbol: String {
        switch model.engineState {
        case .undetermined: return "questionmark.circle"
        case .familyControls: return "hourglass"
        case .shortcutsFallback: return "square.stack.3d.up"
        case .detached: return "power"
        }
    }

    private var engineTint: Color {
        switch model.engineState {
        case .undetermined: return Theme.Palette.inkSecondary
        case .familyControls: return Theme.Palette.pond
        case .shortcutsFallback: return Theme.Palette.amber
        case .detached: return Theme.Palette.signal
        }
    }

    // MARK: Unlocks

    private var unlocksSection: some View {
        Section {
            Picker("Free unlocks a day", selection: $model.dailyFreeUnlocks) {
                ForEach(model.freeUnlockOptions, id: \.self) { count in
                    Text(count == 0 ? "None" : "\(count)").tag(count)
                }
            }
            Picker("Emergency unblock length", selection: $model.defaultEmergencyMinutes) {
                ForEach(model.emergencyMinuteOptions, id: \.self) { minutes in
                    Text(Fmt.option(minutes: minutes)).tag(minutes)
                }
            }
            Toggle("Haptics", isOn: $model.hapticsEnabled)
                .tint(Theme.Palette.pond)
        } header: {
            Text("Unlocks")
        } footer: {
            Text("Each unlock past the free ones costs Bobbly a life. Emergency unblocks are always free.")
        }
        .listRowBackground(Theme.Palette.surface)
    }

    // MARK: Bobbly

    private var bobblySection: some View {
        Section {
            Button { model.openBlockedApps() } label: {
                NavigationRowLabel(title: "Blocked apps", systemImage: "lock.app.dashed", tint: Theme.Palette.pond)
            }
            Button { model.openCompanion() } label: {
                NavigationRowLabel(title: "Bobbly", systemImage: "face.smiling", tint: Theme.Palette.float)
            }
        }
        .listRowBackground(Theme.Palette.surface)
    }

    // MARK: Help

    private var helpSection: some View {
        Section {
            Button { model.openTutorial() } label: {
                NavigationRowLabel(title: "Permission tutorial", systemImage: "checklist", tint: Theme.Palette.reed)
            }
            LabeledContent {
                Text(model.notificationsAuthorized ? "On" : "Off")
                    .foregroundStyle(model.notificationsAuthorized ? Theme.Palette.inkSecondary : Theme.Palette.signal)
            } label: {
                Label("Notifications", systemImage: "bell.badge")
                    .foregroundStyle(Theme.Palette.ink)
            }
        } header: {
            Text("Help")
        } footer: {
            if !model.notificationsAuthorized {
                Text("Turn notifications on in the tutorial. The shield's \u{201C}Talk to Bobbly\u{201D} button needs them to open the chat.")
            }
        }
        .listRowBackground(Theme.Palette.surface)
    }

    // MARK: Emergency

    private var emergencySection: some View {
        Section {
            Button { model.openEmergency() } label: {
                NavigationRowLabel(title: "Emergency unblock or detach", systemImage: "exclamationmark.octagon.fill",
                                   tint: Theme.Palette.signal)
            }
        } footer: {
            Text("Also works with \u{201C}Hey Siri, Bobbly emergency\u{201D} or the link bobbly://emergency, even if the app won't open.")
        }
        .listRowBackground(Theme.Palette.surface)
    }

    // MARK: Diagnostics

    private var diagnosticsSection: some View {
        let d = model.diagnostics
        return Section {
            LabeledContent("Engine", value: d.activeEngine.displayName)
            LabeledContent("Screen Time access", value: d.authorizationStatus)
            LabeledContent("App Group", value: d.appGroupAvailable ? "Available" : "Missing")
            LabeledContent("Data store", value: d.usingFallbackDataStore ? "Temporary" : "On device")
            LabeledContent("Scheduled timers", value: "\(d.monitoredActivities.count)")

            if let error = d.lastAuthorizationError {
                ErrorDetail(title: "Last Screen Time error", text: error)
            }
            if let error = d.lastMonitoringError {
                ErrorDetail(title: "Last timer error", text: error)
            }

            DisclosureGroup("Recent log", isExpanded: $isLogExpanded) {
                if d.recentLog.isEmpty {
                    Text("Nothing logged yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                } else {
                    ForEach(Array(d.recentLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Button {
                model.copyDiagnostics()
            } label: {
                Label(model.didCopyDiagnostics ? "Copied" : "Copy diagnostics",
                      systemImage: model.didCopyDiagnostics ? "checkmark" : "doc.on.doc")
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Bobbly \(model.appVersion)")
        }
        .listRowBackground(Theme.Palette.surface)
    }
}

// MARK: - Rows

private struct NavigationRowLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkTertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

private struct WarningRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.signal)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ErrorDetail: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.Palette.inkSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    SettingsView(model: env.settings)
        .environment(env)
}
