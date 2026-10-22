//  WhitelistEditorView.swift
//  Bobbly/Features/Study — create or edit a named study whitelist.
//  Contract: StudyViewModel (`draft`, `isPickerPresented`, `saveDraft()`, …).

import SwiftUI
import FamilyControls

struct WhitelistEditorView: View {
    @Bindable var model: StudyViewModel
    /// `nil` = new whitelist.
    let whitelistID: UUID?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var isConfirmingDelete = false

    init(model: StudyViewModel, whitelistID: UUID?) {
        self.model = model
        self.whitelistID = whitelistID
    }

    var body: some View {
        NavigationStack {
            Form {
                if let draft = model.draft {
                    Section {
                        TextField("Study, Homework, Reading…", text: nameBinding)
                            .font(Theme.Typography.body)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                    } header: {
                        Text("Name")
                    }
                    .listRowBackground(Theme.Palette.surface)

                    Section {
                        if model.engineKind == .familyControls {
                            familyControlsApps(draft)
                        } else {
                            shortcutsApps(draft)
                        }
                    } header: {
                        Text("Allowed while studying")
                    } footer: {
                        Text(model.alwaysAllowedNote)
                    }
                    .listRowBackground(Theme.Palette.surface)

                    if let error = model.errorMessage {
                        Section {
                            InlineNotice(kind: .error, text: error)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }

                    if whitelistID != nil {
                        Section {
                            Button("Delete whitelist", role: .destructive) { isConfirmingDelete = true }
                        }
                        .listRowBackground(Theme.Palette.surface)
                    }
                } else {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .bobblyPage()
            .navigationTitle(whitelistID == nil ? "New whitelist" : "Edit whitelist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancelDraft()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.saveDraft() { dismiss() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!(model.draft?.isValid ?? false))
                }
            }
            .confirmationDialog("Delete this whitelist?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete whitelist", role: .destructive) {
                    if let whitelistID {
                        model.cancelDraft()
                        model.delete(whitelistID)
                    }
                    dismiss()
                }
            } message: {
                Text("You can't undo this.")
            }
        }
        .familyActivityPicker(isPresented: $model.isPickerPresented, selection: selectionBinding)
        .onAppear(perform: prepareDraft)
        .onDisappear {
            // Swiped away without saving: drop the draft so the next editor starts clean.
            if model.draft != nil { model.cancelDraft() }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func familyControlsApps(_ draft: WhitelistDraft) -> some View {
        let apps = draft.selection.applicationTokens
        let categories = draft.selection.categoryTokens.count
        let sites = draft.selection.webDomainTokens.count

        if needsRepick {
            Label("Screen Time access was reset, so this whitelist's apps need picking again.",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.amber)
        }

        Button {
            model.isPickerPresented = true
        } label: {
            Label(apps.isEmpty && categories == 0 ? "Choose allowed apps" : "Change allowed apps",
                  systemImage: "apps.iphone")
                .font(.body.weight(.semibold))
        }

        if apps.isEmpty && categories == 0 && sites == 0 {
            Text("Nothing allowed yet. Pick the apps you need for studying.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSecondary)
        } else {
            if !apps.isEmpty {
                TokenList(tokens: apps, limit: 20)
                    .padding(.vertical, Theme.Spacing.xxs)
            }
            if categories > 0 || sites > 0 {
                Text(extrasLine(categories: categories, sites: sites))
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private func shortcutsApps(_ draft: WhitelistDraft) -> some View {
        if model.trackedApps.isEmpty {
            Text("Bobbly doesn't track any apps yet. Add them under Blocked apps first; every tracked app that isn't allowed here stays blocked while you study.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSecondary)
        } else {
            ForEach(model.trackedApps) { app in
                Toggle(isOn: Binding(
                    get: { draft.allowedAppKeys.contains(app.appKey) },
                    set: { _ in model.toggleAllowed(appKey: app.appKey) }
                )) {
                    Label(app.name, systemImage: AppCatalog.app(named: app.name)?.symbol ?? "app.dashed")
                        .foregroundStyle(Theme.Palette.ink)
                }
                .tint(Theme.Palette.reed)
            }
        }
    }

    /// The saved picks were voided by a Screen Time reset.
    private var needsRepick: Bool {
        guard let whitelistID else { return false }
        return model.whitelists.first { $0.id == whitelistID }?.needsRepick ?? false
    }

    /// "1 category, 2 websites also allowed".
    private func extrasLine(categories: Int, sites: Int) -> String {
        var parts: [String] = []
        if categories > 0 { parts.append(Fmt.count(categories, "category", "categories")) }
        if sites > 0 { parts.append(Fmt.count(sites, "website")) }
        return parts.joined(separator: ", ") + " also allowed"
    }

    // MARK: Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { model.draft?.name ?? "" },
            set: { model.draft?.name = $0 }
        )
    }

    private var selectionBinding: Binding<FamilyActivitySelection> {
        Binding(
            get: { model.draft?.selection ?? FamilyActivitySelection() },
            set: { model.draft?.selection = $0 }
        )
    }

    private func prepareDraft() {
        if let whitelistID {
            if model.draft?.id != whitelistID { model.edit(whitelistID) }
        } else if model.draft == nil {
            model.newWhitelist()
            isNameFocused = true
        }
    }
}
