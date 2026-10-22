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
    /// Screen Time access was revoked since this whitelist's apps were picked:
    /// its app picks are void — show "Pick apps again" (→ `edit(id)`).
    var needsRepick: Bool = false
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
                                    updatedAt: list.updatedAt,
                                    needsRepick: list.needsRepick)
        }
        trackedApps = tracked.map(TrackedAppRow.init)
        if selectedWhitelistID == nil || !whitelists.contains(where: { $0.id == selectedWhitelistID }) {
            selectedWhitelistID = whitelists.first?.id
        }
        activeSession = env.engines.status.study.map {
            ActiveStudySession(sessionID: $0.sessionID, whitelistName: $0.whitelistName, startedAt: $0.startedAt, endsAt: $0.endsAt)
        }
    }

    /// Brings SwiftData in line with the engines: closes sessions that ended
    /// elsewhere (timer ran out while Bobbly was closed, Siri detach) and flags
    /// whitelists whose app picks were voided by a Screen Time revocation.
    func syncWithEngine(now: Date = Date()) {
        invalidateWhitelistsIfTokensRevoked()

        // A timed session that ran out (the Shortcuts engine keeps it in the
        // store; FamilyControls' monitor clears it) is finished.
        if let study = env.shared.activeStudy, !study.isActive(at: now) {
            env.shared.recordStudyEnd(study, at: study.endsAt ?? now, reason: .completed)
            env.shared.activeStudy = nil
        }
        let running = (try? env.context.fetch(FetchDescriptor<StudySession>(predicate: #Predicate { $0.endedAt == nil }))) ?? []
        let activeID = env.shared.activeStudy?.sessionID
        for session in running where session.id != activeID {
            let resolution = Self.resolveEnd(of: session.startedAt, plannedEnd: session.plannedEnd,
                                             record: env.shared.studyEndRecord(for: session.id), now: now)
            session.endedAt = resolution.endedAt
            session.endedEarly = !resolution.completed
            if resolution.completed {
                env.companion.recordStudyFinished(minutes: session.focusMinutes(at: resolution.endedAt), endedEarly: false, now: now)
            }
            // Detached / unknown endings: no bonus and no penalty (emergencies are free).
        }
        try? env.context.save()
        refresh()
    }

    /// Pure: when/how a session that is no longer running ended.
    /// Never returns an end before `start` or after `now`.
    static func resolveEnd(of start: Date, plannedEnd: Date?, record: StudyEndRecord?, now: Date)
        -> (endedAt: Date, completed: Bool) {
        let rawEnd: Date
        let completed: Bool
        if let record {
            rawEnd = record.endedAt
            completed = record.reason == .completed
        } else if let plannedEnd, plannedEnd <= now {
            rawEnd = plannedEnd
            completed = true
        } else {
            rawEnd = now
            completed = false
        }
        return (max(start, min(rawEnd, now)), completed)
    }

    private static let tokensHandledKey = "bobbly.study.tokensRevocationHandledAt"

    /// After a revocation every saved whitelist token is void: clear the picks
    /// and flag the whitelist so the UI asks the user to pick apps again.
    private func invalidateWhitelistsIfTokensRevoked() {
        guard let revokedAt = env.shared.tokensRevokedAt else { return }
        let handled = UserDefaults.standard.object(forKey: Self.tokensHandledKey) as? Date
        guard handled.map({ $0 < revokedAt }) ?? true else { return }
        let lists = (try? env.context.fetch(FetchDescriptor<Whitelist>())) ?? []
        for list in lists where list.selectionData != nil && list.updatedAt <= revokedAt {
            let selection = list.selection
            let hadTokens = !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
                || !selection.webDomainTokens.isEmpty
            if hadTokens {
                list.selection = FamilyActivitySelection(includeEntireCategory: true)
                list.needsRepick = true
            }
        }
        try? env.context.save()
        UserDefaults.standard.set(revokedAt, forKey: Self.tokensHandledKey)
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
            let picked = !draft.selection.applicationTokens.isEmpty || !draft.selection.categoryTokens.isEmpty
                || !draft.selection.webDomainTokens.isEmpty
            if picked { existing.needsRepick = false }
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
        if engineKind == .familyControls && list.needsRepick {
            // Its saved picks were voided by a Screen Time revocation; starting
            // now would block everything with no exceptions.
            errorMessage = "Screen Time access was reset. Pick the apps for \(list.name) again first."
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

    /// Called by ChatViewModel when the chat approves ending the session
    /// (ended early: focus minutes count, small mood cost).
    func endSessionEarly(reason: String, now: Date = Date()) {
        finishRunningSession(reason: .endedEarly, now: now)
    }

    /// Ends a session immediately without the chat — emergency detach only.
    /// Recorded as ended early with no bonus and no penalty (emergencies are free).
    func stopSessionWithoutChat(now: Date = Date()) {
        finishRunningSession(reason: .detached, now: now)
    }

    // MARK: Helpers

    private func finishRunningSession(reason: StudyEndRecord.Reason, now: Date) {
        let study = env.shared.activeStudy
        if let study { env.shared.recordStudyEnd(study, at: now, reason: reason) }
        env.engines.endStudy()
        if let activeID = study?.sessionID {
            let descriptor = FetchDescriptor<StudySession>(predicate: #Predicate { $0.id == activeID })
            if let session = try? env.context.fetch(descriptor).first, session.endedAt == nil {
                session.endedAt = max(session.startedAt, now)
                session.endedEarly = true
                if reason == .endedEarly {
                    env.companion.recordStudyFinished(minutes: session.focusMinutes(at: now), endedEarly: true, now: now)
                }
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
