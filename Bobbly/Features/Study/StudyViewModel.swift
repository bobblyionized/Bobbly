//  StudyViewModel.swift
//  Bobbly/Features/Study — named whitelists + study sessions that block
//  everything except the whitelist. Ending early goes through the chat.

import Foundation
import Observation
import SwiftData
import FamilyControls

enum StudyDuration: Hashable, Identifiable {
    case minutes(Int)
    case untilStopped

    static let options: [StudyDuration] = [.minutes(25), .minutes(50), .minutes(90), .untilStopped]

    var id: String {
        switch self {
        case .minutes(let m): return "m\(m)"
        case .untilStopped: return "open"
        }
    }

    var title: String {
        switch self {
        case .minutes(let m): return m >= 60 && m % 60 == 0 ? "\(m / 60) h" : "\(m) min"
        case .untilStopped: return "Until I stop"
        }
    }

    var minutes: Int? {
        if case .minutes(let m) = self { return m }
        return nil
    }
}

/// Row in the whitelist list.
struct WhitelistSummary: Identifiable, Hashable {
    let id: UUID
    var name: String
    /// FamilyControls picks (render with the picker summary / `Label(token)`).
    var appCount: Int
    var categoryCount: Int
    var webDomainCount: Int
    /// Shortcuts engine: allowed tracked app names.
    var allowedAppNames: [String]
    var updatedAt: Date
}

/// Editable copy of a whitelist (the editor sheet binds to `draft`).
struct WhitelistDraft: Equatable {
    /// `nil` = new whitelist.
    var id: UUID?
    var name: String
    /// Bind to `FamilyActivityPicker(selection:)`.
    var selection: FamilyActivitySelection
    /// Shortcuts engine: allowed app keys (toggle rows from `trackedApps`).
    var allowedAppKeys: Set<String>

    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// The running session for the "studying" card.
struct ActiveStudySession: Equatable {
    var sessionID: UUID
    var whitelistName: String
    var startedAt: Date
    /// `nil` = until stopped.
    var endsAt: Date?

    func remaining(at now: Date = Date()) -> TimeInterval? {
        endsAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    func elapsed(at now: Date = Date()) -> TimeInterval { max(0, now.timeIntervalSince(startedAt)) }

    /// 0...1 for timed sessions; `nil` for open-ended.
    func progress(at now: Date = Date()) -> Double? {
        guard let endsAt else { return nil }
        let total = endsAt.timeIntervalSince(startedAt)
        return total > 0 ? min(1, elapsed(at: now) / total) : 1
    }
}

@Observable
@MainActor
final class StudyViewModel {
    unowned let env: AppEnvironment

    private(set) var whitelists: [WhitelistSummary] = []
    private(set) var activeSession: ActiveStudySession?
    /// Whitelist chosen for the next session.
    var selectedWhitelistID: UUID?
    var selectedDuration: StudyDuration = .minutes(50)
    let durationOptions = StudyDuration.options

    /// Non-nil while the editor sheet is open.
    var draft: WhitelistDraft?
    /// Presents `FamilyActivityPicker(selection: $draft.selection)`.
    var isPickerPresented = false
    /// Shortcuts engine: apps that can be toggled into a whitelist.
    private(set) var trackedApps: [TrackedAppRow] = []
    private(set) var errorMessage: String?

    /// Static note for the UI.
    let alwaysAllowedNote = "Phone, Messages and Settings always stay available, and so does Bobbly."

    init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: Derived

    var engineKind: EngineKind { env.engines.status.kind }
    var isSessionRunning: Bool { activeSession != nil }
    var canStart: Bool { selectedWhitelistID != nil && activeSession == nil }

    // MARK: Lifecycle

    func onAppear() {
        refresh()
    }

    func refresh() {
        let lists = (try? env.context.fetch(FetchDescriptor<Whitelist>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let tracked = (try? env.context.fetch(FetchDescriptor<TrackedApp>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let namesByKey = Dictionary(tracked.map { ($0.appKey, $0.name) }, uniquingKeysWith: { first, _ in first })

        whitelists = lists.map { list -> WhitelistSummary in
            let selection = list.selection
            return WhitelistSummary(id: list.id, name: list.name,
                                    appCount: selection.applicationTokens.count,
                                    categoryCount: selection.categoryTokens.count,
                                    webDomainCount: selection.webDomainTokens.count,
                                    allowedAppNames: list.allowedAppKeys.map { namesByKey[$0] ?? $0 },
                                    updatedAt: list.updatedAt)
        }
        trackedApps = tracked.map(TrackedAppRow.init)
        if selectedWhitelistID == nil || !whitelists.contains(where: { $0.id == selectedWhitelistID }) {
            selectedWhitelistID = whitelists.first?.id
        }
        activeSession = env.engines.status.study.map {
            ActiveStudySession(sessionID: $0.sessionID, whitelistName: $0.whitelistName, startedAt: $0.startedAt, endsAt: $0.endsAt)
        }
    }

    /// Closes SwiftData sessions that the monitor already ended (timer ran out
    /// while Bobbly was closed) and credits the companion.
    func syncWithEngine(now: Date = Date()) {
        // A timed session that ran out (Shortcuts engine keeps it in the store
        // until now; FamilyControls' monitor clears it) is finished.
        if let study = env.shared.activeStudy, !study.isActive(at: now) {
            env.shared.activeStudy = nil
            env.shared.lastStudyEndedAt = study.endsAt ?? now
        }
        let running = (try? env.context.fetch(FetchDescriptor<StudySession>(predicate: #Predicate { $0.endedAt == nil }))) ?? []
        let activeID = env.shared.activeStudy?.sessionID
        for session in running where session.id != activeID {
            let end = min(now, session.plannedEnd ?? env.shared.lastStudyEndedAt ?? now)
            session.endedAt = end
            session.endedEarly = false
            env.companion.recordStudyFinished(minutes: session.focusMinutes(at: end), endedEarly: false, now: now)
        }
        try? env.context.save()
        refresh()
    }

    // MARK: Whitelist editing

    func newWhitelist() {
        draft = WhitelistDraft(id: nil, name: "", selection: FamilyActivitySelection(includeEntireCategory: true), allowedAppKeys: [])
    }

    func edit(_ id: UUID) {
        guard let list = fetchWhitelist(id) else { return }
        draft = WhitelistDraft(id: list.id, name: list.name, selection: list.selection, allowedAppKeys: Set(list.allowedAppKeys))
    }

    /// Shortcuts editor: toggles a tracked app in the draft.
    func toggleAllowed(appKey: String) {
        guard var current = draft else { return }
        if current.allowedAppKeys.contains(appKey) { current.allowedAppKeys.remove(appKey) } else { current.allowedAppKeys.insert(appKey) }
        draft = current
    }

    /// Saves `draft`. - Returns: `true` on success (close the sheet).
    @discardableResult
    func saveDraft() -> Bool {
        guard let draft, draft.isValid else {
            errorMessage = "Give your whitelist a name."
            return false
        }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = draft.id, let existing = fetchWhitelist(id) {
            existing.name = name
            existing.selection = draft.selection
            existing.allowedAppKeys = Array(draft.allowedAppKeys).sorted()
        } else {
            env.context.insert(Whitelist(name: name, selection: draft.selection, allowedAppKeys: Array(draft.allowedAppKeys).sorted()))
        }
        try? env.context.save()
        self.draft = nil
        errorMessage = nil
        refresh()
        return true
    }

    func cancelDraft() {
        draft = nil
        isPickerPresented = false
    }

    func delete(_ id: UUID) {
        guard let list = fetchWhitelist(id) else { return }
        env.context.delete(list)
        try? env.context.save()
        refresh()
    }

    // MARK: Sessions

    /// Starts a session with `selectedWhitelistID` for `selectedDuration`.
    func startSession(now: Date = Date()) {
        guard let id = selectedWhitelistID, let list = fetchWhitelist(id) else {
            errorMessage = "Pick a whitelist first."
            return
        }
        let endsAt = selectedDuration.minutes.map { now.addingTimeInterval(TimeInterval($0 * 60)) }
        let session = StudySession(whitelistID: list.id, whitelistName: list.name, startedAt: now, plannedEnd: endsAt)
        env.context.insert(session)
        session.whitelist = list
        try? env.context.save()

        let study = ActiveStudy(sessionID: session.id, whitelistID: list.id, whitelistName: list.name,
                                selectionData: list.selectionData, allowedAppKeys: list.allowedAppKeys,
                                startedAt: now, endsAt: endsAt)
        do {
            try env.engines.startStudy(study)
            errorMessage = nil
        } catch {
            env.context.delete(session)
            try? env.context.save()
            errorMessage = error.localizedDescription
        }
        refresh()
        env.home.refresh()
    }

    /// "End early" → Bobbly has to agree first.
    func requestEndEarly() {
        guard let activeSession else { return }
        env.openChat(ChatTarget.studySession(named: activeSession.whitelistName))
    }

    /// Called by ChatViewModel when the chat approves ending the session.
    func endSessionEarly(reason: String, now: Date = Date()) {
        finishRunningSession(endedEarly: true, now: now)
    }

    /// Ends a session immediately without the chat (emergency paths only).
    func stopSessionWithoutChat(now: Date = Date()) {
        finishRunningSession(endedEarly: true, now: now)
    }

    // MARK: Helpers

    private func finishRunningSession(endedEarly: Bool, now: Date) {
        let activeID = env.shared.activeStudy?.sessionID
        env.engines.endStudy()
        if let activeID {
            let descriptor = FetchDescriptor<StudySession>(predicate: #Predicate { $0.id == activeID })
            if let session = try? env.context.fetch(descriptor).first, session.endedAt == nil {
                session.endedAt = now
                session.endedEarly = endedEarly
                env.companion.recordStudyFinished(minutes: session.focusMinutes(at: now), endedEarly: endedEarly, now: now)
                try? env.context.save()
            }
        }
        refresh()
        env.home.refresh()
    }

    private func fetchWhitelist(_ id: UUID) -> Whitelist? {
        let descriptor = FetchDescriptor<Whitelist>(predicate: #Predicate { $0.id == id })
        return try? env.context.fetch(descriptor).first
    }
}
