//  BlockedAppsView.swift
//  Bobbly/Features/BlockedApps — choose what Bobbly blocks. Screen Time:
//  the system app picker. Shortcuts: tracked apps with daily limits, a
//  catalog of popular apps and a custom-app form. Contract: BlockedAppsViewModel.

import SwiftUI
import FamilyControls

struct BlockedAppsView: View {
    @State private var model: BlockedAppsViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: BlockedAppsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.engineKind == .familyControls {
                    familyControlsContent
                } else {
                    ShortcutsBlockedApps(model: model)
                }
            }
            .bobblyPage()
            .navigationTitle("Blocked apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .familyActivityPicker(isPresented: $model.isPickerPresented, selection: $model.selection)
        .onAppear { model.onAppear() }
        .bobblyHaptic(trigger: model.savedMessage) { _, new in
            new == nil ? nil : SensoryFeedback.success
        }
    }

    // MARK: Screen Time

    private var familyControlsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if !model.canUsePicker {
                    Panel {
                        EmptyStateView(title: "Screen Time access needed",
                                       message: "Bobbly can pick apps once you allow Screen Time access. Open Settings › Permission tutorial to turn it on.",
                                       mood: .okay)
                    }
                } else {
                    Panel(padding: Theme.Spacing.l) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bobbly blocks")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Palette.inkSecondary)
                                Text(model.selectionSummary)
                                    .font(Theme.Typography.title)
                                    .foregroundStyle(Theme.Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)

                            Button {
                                model.presentPicker()
                            } label: {
                                Label(model.selection.applicationTokens.isEmpty ? "Choose apps" : "Change apps",
                                      systemImage: "plus.app")
                            }
                            .buttonStyle(.bobblySecondary)
                        }
                    }

                    if !model.selection.applicationTokens.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            SectionTitle("Apps")
                            TokenList(tokens: model.selection.applicationTokens, limit: 40)
                                .padding(Theme.Spacing.m)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.Palette.surface,
                                            in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                        }
                    }

                    if let error = model.errorMessage {
                        InlineNotice(kind: .error, text: error)
                    }
                    if let saved = model.savedMessage, !model.hasUnsavedChanges {
                        InlineNotice(kind: .success, text: saved)
                    }

                    Button {
                        model.saveSelection()
                    } label: {
                        Label("Save and block", systemImage: "lock.fill")
                    }
                    .buttonStyle(.bobblyPrimary)
                    .disabled(!model.hasUnsavedChanges)

                    Text("Talk to Bobbly whenever you need one of these apps back.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkTertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }
}

// MARK: - Shortcuts engine

private struct ShortcutsBlockedApps: View {
    @Bindable var model: BlockedAppsViewModel

    var body: some View {
        List {
            Section {
                if model.trackedApps.isEmpty {
                    Text("No apps yet. Add a popular app below, or any app by name.")
                        .font(.callout)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                } else {
                    ForEach(model.trackedApps) { row in
                        TrackedAppRowView(row: row,
                                          limitOptions: model.limitOptions,
                                          onBlockedChange: { model.setBlocked(row, $0) },
                                          onLimitChange: { model.setLimit(row, minutes: $0) })
                    }
                    .onDelete { offsets in
                        let rows = offsets.map { model.trackedApps[$0] }
                        rows.forEach { model.remove($0) }
                    }
                }
            } header: {
                Text("Your apps")
            } footer: {
                Text("Each app needs its Shortcuts automations to be blocked. The permission tutorial walks you through them.")
            }
            .listRowBackground(Theme.Palette.surface)

            if let error = model.errorMessage {
                Section {
                    InlineNotice(kind: .error, text: error)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .accessibilityHidden(true)
                    TextField("Find a popular app", text: $model.catalogQuery)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                ForEach(model.filteredCatalog) { app in
                    HStack(spacing: Theme.Spacing.s) {
                        AppGlyph(systemImage: app.symbol, size: 30)
                        Text(app.name)
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        if model.isTracked(app) {
                            Label("Added", systemImage: "checkmark")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Theme.Palette.reed)
                                .accessibilityLabel("\(app.name) added")
                        } else {
                            Button("Add") { model.add(app) }
                                .buttonStyle(.bobbly(.secondary, fullWidth: false, compact: true))
                                .accessibilityLabel("Add \(app.name)")
                        }
                    }
                }
            } header: {
                Text("Popular apps")
            }
            .listRowBackground(Theme.Palette.surface)

            Section {
                TextField("App name, exactly as Shortcuts shows it", text: $model.customName)
                    .autocorrectionDisabled()
                TextField("URL scheme (optional), like spotify", text: $model.customScheme)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("Add app") { model.addCustomApp() }
                    .disabled(model.customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Another app")
            } footer: {
                Text("The URL scheme lets Bobbly reopen the app after an unlock.")
            }
            .listRowBackground(Theme.Palette.surface)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct TrackedAppRowView: View {
    let row: TrackedAppRow
    let limitOptions: [Int]
    let onBlockedChange: (Bool) -> Void
    let onLimitChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                AppGlyph(systemImage: AppCatalog.app(named: row.name)?.symbol ?? "app.dashed", size: 30)
                Text(row.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Toggle("Block \(row.name)", isOn: Binding(get: { row.isBlocked }, set: { onBlockedChange($0) }))
                    .labelsHidden()
                    .tint(Theme.Palette.pond)
            }
            Menu {
                Picker("Daily limit", selection: Binding(get: { row.dailyLimitMinutes }, set: { onLimitChange($0) })) {
                    ForEach(limitOptions, id: \.self) { minutes in
                        Text(minutes == 0 ? "No limit" : Fmt.option(minutes: minutes)).tag(minutes)
                    }
                }
            } label: {
                Label(row.dailyLimitMinutes == 0 ? "No daily limit" : "\(Fmt.option(minutes: row.dailyLimitMinutes)) a day",
                      systemImage: "timer")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.pond)
            }
            .accessibilityLabel("Daily limit for \(row.name)")
        }
        .padding(.vertical, 4)
    }
}
