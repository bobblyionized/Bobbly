//  BlockedAppsViewModel.swift
//  Bobbly/Features/BlockedApps — choose what Bobbly blocks.
//   • FamilyControls: `FamilyActivityPicker` → `selection` → `saveSelection()`.
//   • Shortcuts: tracked apps from the catalog / custom (name + URL scheme),
//     each with an optional daily limit.

import Foundation
import Observation
import SwiftData
import FamilyControls

/// Value copy of a `TrackedApp` for lists.
struct TrackedAppRow: Identifiable, Hashable {
    let id: UUID
    var name: String
    var appKey: String
    var urlScheme: String?
    /// 0 = no limit.
    var dailyLimitMinutes: Int
    var isBlocked: Bool

    init(_ app: TrackedApp) {
        id = app.id
        name = app.name
        appKey = app.appKey
        urlScheme = app.urlScheme
        dailyLimitMinutes = app.dailyLimitMinutes
        isBlocked = app.isBlocked
    }
}

@Observable
@MainActor
final class BlockedAppsViewModel {
    unowned let env: AppEnvironment

    /// Bind to `FamilyActivityPicker(selection:)` / `.familyActivityPicker(isPresented:selection:)`.
    var selection = FamilyActivitySelection()
    var isPickerPresented = false

    /// Shortcuts engine rows.
    private(set) var trackedApps: [TrackedAppRow] = []
    /// Catalog search field.
    var catalogQuery: String = ""
    /// Custom app form.
    var customName: String = ""
    var customScheme: String = ""

    private(set) var errorMessage: String?
    /// Brief confirmation after saving ("Blocking 4 apps").
    private(set) var savedMessage: String?

    /// Limit choices for the per-app limit menu (minutes; 0 = none).
    let limitOptions = [0, 15, 30, 45, 60, 90, 120]

    init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: Derived

    var engineKind: EngineKind { env.engines.status.kind }

    /// Picker results needs authorization; `false` → show the tutorial link instead.
    var canUsePicker: Bool { env.engines.state == .familyControls }

    /// e.g. "4 apps · 1 category · 2 websites".
    var selectionSummary: String {
        var parts: [String] = []
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        let sites = selection.webDomainTokens.count
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if categories > 0 { parts.append("\(categories) categor\(categories == 1 ? "y" : "ies")") }
        if sites > 0 { parts.append("\(sites) website\(sites == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: " · ")
    }

    var hasUnsavedChanges: Bool { selection != env.shared.blockedSelection }

    /// Catalog apps matching `catalogQuery`.
    var filteredCatalog: [CatalogApp] { AppCatalog.search(catalogQuery) }

    func isTracked(_ app: CatalogApp) -> Bool {
        trackedApps.contains { $0.appKey == app.id }
    }

    // MARK: Actions

    func onAppear() {
        selection = env.shared.blockedSelection
        reload()
    }

    func presentPicker() {
        isPickerPresented = true
    }

    /// Opens the permission tutorial (shown when `canUsePicker` is false).
    /// This view is usually a sheet; the router dismisses it before the
    /// tutorial cover appears. Inside the tutorial it simply stays on the tutorial.
    func openTutorial() {
        env.router.presentTutorial()
    }

    /// FamilyControls: applies `selection` as the block list.
    func saveSelection() {
        do {
            try env.engines.updateBlockList(BlockList(selection: selection, appNames: blockedNames()))
            savedMessage = "Blocking \(selectionSummary.lowercased())"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        env.home.refresh()
    }

    /// Shortcuts: tracks + blocks a catalog app.
    func add(_ app: CatalogApp) {
        guard !isTracked(app) else { return }
        env.context.insert(TrackedApp(name: app.name, urlScheme: app.urlScheme))
        persistAndApply()
    }

    /// Shortcuts: tracks + blocks `customName` (`customScheme` optional).
    func addCustomApp() {
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { errorMessage = "Enter the app's name exactly as Shortcuts shows it."; return }
        guard !trackedApps.contains(where: { $0.appKey == AppKey.normalize(name) }) else { errorMessage = "\(name) is already tracked."; return }
        let scheme = customScheme.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "://", with: "")
        env.context.insert(TrackedApp(name: name, urlScheme: scheme.isEmpty ? nil : scheme))
        customName = ""
        customScheme = ""
        persistAndApply()
    }

    func remove(_ row: TrackedAppRow) {
        guard let app = fetch(row.id) else { return }
        env.context.delete(app)
        persistAndApply()
    }

    func setBlocked(_ row: TrackedAppRow, _ blocked: Bool) {
        fetch(row.id)?.isBlocked = blocked
        persistAndApply()
    }

    func setLimit(_ row: TrackedAppRow, minutes: Int) {
        fetch(row.id)?.dailyLimitMinutes = max(0, minutes)
        persistAndApply()
    }

    // MARK: Helpers

    private func reload() {
        let apps = (try? env.context.fetch(FetchDescriptor<TrackedApp>(sortBy: [SortDescriptor(\.name)]))) ?? []
        trackedApps = apps.map(TrackedAppRow.init)
    }

    private func blockedNames() -> [String] {
        trackedApps.filter(\.isBlocked).map(\.name)
    }

    private func persistAndApply() {
        try? env.context.save()
        reload()
        errorMessage = nil
        do {
            try env.engines.updateBlockList(BlockList(selection: env.shared.blockedSelection, appNames: blockedNames()))
        } catch {
            // FamilyControls without authorization: names are still saved for the fallback.
            env.shared.blockedAppKeys = blockedNames()
        }
        env.home.refresh()
    }

    private func fetch(_ id: UUID) -> TrackedApp? {
        let descriptor = FetchDescriptor<TrackedApp>(predicate: #Predicate { $0.id == id })
        return try? env.context.fetch(descriptor).first
    }
}
