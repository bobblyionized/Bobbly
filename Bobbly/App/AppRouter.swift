//  AppRouter.swift
//  Bobbly/App — navigation state (tabs, sheets, full-screen covers) and
//  deep-link parsing. Orchestration (what a link *does*) is in AppEnvironment.

import Foundation
import Observation

/// Root tabs, in display order.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case chat
    case study
    case stats
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .chat: return "Chat"
        case .study: return "Study"
        case .stats: return "Stats"
        case .settings: return "Settings"
        }
    }

    /// SF Symbol for the tab item.
    var systemImage: String {
        switch self {
        case .home: return "house"
        case .chat: return "bubble.left.and.bubble.right"
        case .study: return "book"
        case .stats: return "chart.bar"
        case .settings: return "gearshape"
        }
    }
}

/// Sheets presented over the tab view.
enum SheetRoute: Identifiable, Hashable {
    /// Emergency unblock + detach.
    case emergency
    /// Screen-time searcher.
    case search
    /// Pick / edit blocked apps.
    case blockedApps
    /// Bobbly companion detail.
    case companion
    /// Create (`nil`) or edit a study whitelist. Uses `AppEnvironment.study`.
    case whitelistEditor(whitelistID: UUID?)

    var id: String {
        switch self {
        case .emergency: return "emergency"
        case .search: return "search"
        case .blockedApps: return "blockedApps"
        case .companion: return "companion"
        case .whitelistEditor(let id): return "whitelistEditor-\(id?.uuidString ?? "new")"
        }
    }
}

/// Full-screen covers.
enum CoverRoute: Identifiable, Hashable {
    /// Block screen opened by bobbly://gate.
    case gate(ChatTarget)
    /// Permissions tutorial (first launch / Settings).
    case tutorial

    var id: String {
        switch self {
        case .gate(let target): return "gate-\(target.id.uuidString)"
        case .tutorial: return "tutorial"
        }
    }
}

/// Parsed `bobbly://` URL.
enum DeepLink: Equatable {
    /// `bobbly://gate?app=instagram[&source=shortcuts]`
    case gate(appName: String?, source: BobblyLink.Source)
    /// `bobbly://chat?app=…&source=shield`
    case chat(appName: String?, source: BobblyLink.Source)
    /// `bobbly://emergency`
    case emergency
    /// `bobbly://tutorial`
    case tutorial

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == BobblyLink.scheme,
              let hostString = components.host?.lowercased(),
              let host = BobblyLink.Host(rawValue: hostString)
        else { return nil }

        let items = components.queryItems ?? []
        let rawApp = items.first { $0.name == BobblyLink.Query.app }?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let app = (rawApp?.isEmpty ?? true) ? nil : rawApp
        let source = items.first { $0.name == BobblyLink.Query.source }?.value
            .flatMap(BobblyLink.Source.init(rawValue:)) ?? .shortcuts

        switch host {
        case .gate: self = .gate(appName: app, source: source)
        case .chat: self = .chat(appName: app, source: source)
        case .emergency: self = .emergency
        case .tutorial: self = .tutorial
        }
    }
}

@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .home
    /// Bind with `.sheet(item: $router.sheet)`.
    var sheet: SheetRoute?
    /// Bind with `.fullScreenCover(item: $router.cover)`.
    var cover: CoverRoute?

    /// SwiftUI can't dismiss one modal and present another in the same update;
    /// the second is presented after this delay.
    static let modalHandoffDelay: Duration = .milliseconds(450)

    @ObservationIgnored private var pendingModalTask: Task<Void, Never>?

    func select(_ tab: AppTab) {
        selectedTab = tab
    }

    /// Presents a sheet. If a full-screen cover is up, it is dismissed first
    /// and the sheet follows after `modalHandoffDelay`.
    func present(_ route: SheetRoute) {
        pendingModalTask?.cancel()
        guard cover != nil else {
            sheet = route
            return
        }
        cover = nil
        schedule { $0.sheet = route }
    }

    func presentGate(_ target: ChatTarget) {
        presentCover(.gate(target))
    }

    func presentTutorial() {
        presentCover(.tutorial)
    }

    func dismissSheet() {
        pendingModalTask?.cancel()
        sheet = nil
    }

    func dismissCover() {
        pendingModalTask?.cancel()
        cover = nil
    }

    /// Closes any modal (including a pending one) and shows `tab`.
    func showTab(_ tab: AppTab) {
        pendingModalTask?.cancel()
        sheet = nil
        cover = nil
        selectedTab = tab
    }

    /// Presents a cover. If a sheet is up, it is dismissed first and the cover
    /// follows after `modalHandoffDelay` (same race as sheet-over-cover).
    private func presentCover(_ route: CoverRoute) {
        pendingModalTask?.cancel()
        guard sheet != nil else {
            cover = route
            return
        }
        sheet = nil
        schedule { $0.cover = route }
    }

    private func schedule(_ change: @escaping @MainActor (AppRouter) -> Void) {
        pendingModalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: AppRouter.modalHandoffDelay)
            guard let self, !Task.isCancelled else { return }
            change(self)
        }
    }
}
