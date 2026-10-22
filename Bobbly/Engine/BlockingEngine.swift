//  BlockingEngine.swift
//  Bobbly/Engine — the one interface both blocking engines implement.

import Foundation
import FamilyControls
import ManagedSettings

// MARK: - Domain types

/// What an unlock request / chat is about.
enum UnlockSubject: Hashable, Codable {
    /// Shortcuts engine: an app by name, e.g. "Instagram".
    case appName(String)
    /// FamilyControls engine: a shielded app's opaque token.
    /// UI: render its name/icon with FamilyControls' `Label(token)`.
    case application(ApplicationToken)
    /// Ending the running study session early.
    case studySession

    /// Normalized name for name-based subjects.
    var appKey: String? {
        if case .appName(let name) = self { return AppKey.normalize(name) }
        return nil
    }
}

/// The user's block list, in both engines' vocabularies. Each engine uses its part.
struct BlockList: Equatable {
    /// FamilyControls engine.
    var selection: FamilyActivitySelection
    /// Shortcuts engine (names as typed; normalized internally).
    var appNames: [String]

    static let empty = BlockList(selection: FamilyActivitySelection(), appNames: [])
}

/// A running chat-granted unlock.
struct ActiveUnlock: Identifiable, Hashable {
    var id: UUID
    var subject: UnlockSubject
    /// "Instagram", or "This app" for token grants whose name is unknown to the app.
    var displayName: String
    var grantedAt: Date
    var expiresAt: Date

    func remaining(at now: Date = Date()) -> TimeInterval { max(0, expiresAt.timeIntervalSince(now)) }

    init(id: UUID, subject: UnlockSubject, displayName: String, grantedAt: Date, expiresAt: Date) {
        self.id = id
        self.subject = subject
        self.displayName = displayName
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
    }

    init(grant: UnlockGrant) {
        let subject: UnlockSubject
        if let token = grant.applicationToken {
            subject = .application(token)
        } else {
            subject = .appName(grant.appKey ?? grant.displayName)
        }
        self.init(id: grant.id, subject: subject, displayName: grant.displayName, grantedAt: grant.grantedAt, expiresAt: grant.expiresAt)
    }
}

/// The running study session as the engines see it.
struct StudySnapshot: Equatable {
    var sessionID: UUID
    var whitelistID: UUID
    var whitelistName: String
    var startedAt: Date
    /// `nil` = until stopped.
    var endsAt: Date?

    init(_ study: ActiveStudy) {
        sessionID = study.sessionID
        whitelistID = study.whitelistID
        whitelistName = study.whitelistName
        startedAt = study.startedAt
        endsAt = study.endsAt
    }
}

/// Everything the UI needs to describe the current protection state.
struct EngineStatus: Equatable {
    var kind: EngineKind
    /// FamilyControls: authorization approved. Shortcuts: always `true`.
    var isReady: Bool
    var isDetached: Bool
    var emergencyUntil: Date?
    var activeUnlocks: [ActiveUnlock]
    var study: StudySnapshot?
    /// Counts in the current block list.
    var blockedAppCount: Int
    var blockedCategoryCount: Int
    var blockedWebDomainCount: Int

    var hasAnythingBlocked: Bool { blockedAppCount + blockedCategoryCount + blockedWebDomainCount > 0 }

    func isEmergencyActive(at now: Date = Date()) -> Bool { (emergencyUntil ?? .distantPast) > now }

    static let placeholder = EngineStatus(kind: .shortcuts, isReady: false, isDetached: false, emergencyUntil: nil,
                                          activeUnlocks: [], study: nil, blockedAppCount: 0,
                                          blockedCategoryCount: 0, blockedWebDomainCount: 0)
}

/// What `detach()` did, plus the manual steps the user still has to do.
struct DetachReport: Equatable {
    var engine: EngineKind
    var clearedShields: Bool
    var stoppedMonitoring: Bool
    var revokedAuthorization: Bool
    /// Ordered, user-facing instructions (e.g. delete the Shortcuts automations).
    var manualSteps: [String]
    var errors: [String]
}

enum EngineError: LocalizedError, Equatable {
    case notAuthorized
    case invalidSubject
    case monitoringFailed(String)
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Bobbly doesn't have Screen Time access."
        case .invalidSubject: return "That can't be unlocked this way."
        case .monitoringFailed(let detail): return "Couldn't schedule the re-lock: \(detail)"
        case .authorizationFailed(let detail): return "Screen Time access failed: \(detail)"
        }
    }
}

// MARK: - Protocol

/// A way of blocking apps. `EngineSelector` picks the implementation at launch.
@MainActor
protocol BlockingEngine: AnyObject {
    var kind: EngineKind { get }

    /// Current state, derived from `SharedStore`.
    var status: EngineStatus { get }

    /// Makes this the running engine (writes `SharedStore.engineKind`, applies shields).
    func activate()

    /// Replaces the block list and applies it immediately.
    func block(_ list: BlockList) throws

    /// Temporarily unlocks one or more apps with ONE unlock (the daily unlock
    /// counter increases once). Each re-locks automatically at expiry.
    /// Use `grantUnlock(_:displayName:minutes:)` for a single app.
    @discardableResult
    func grantUnlocks(_ subjects: [UnlockSubject], displayName: String, minutes: Int) throws -> [ActiveUnlock]

    /// Ends an unlock early ("Lock it again").
    func revokeUnlock(id: UUID)

    /// Free emergency unblock: removes every block (incl. study) for `minutes`.
    func emergencyUnblockAll(minutes: Int) throws

    /// Ends an emergency unblock early.
    func endEmergency()

    /// Blocks everything except the study whitelist until `study.endsAt` (or until stopped).
    func startStudy(_ study: ActiveStudy) throws

    /// Ends the running study session.
    func endStudy()

    /// Emergency detach: removes all shields/monitoring and turns Bobbly off.
    func detach() async -> DetachReport

    /// Undo detach (FamilyControls may need authorization again — see `EngineSelector`).
    func reattach()

    /// Pure access decision for a named app (Shortcuts `CheckAccessIntent`).
    func decision(forAppNamed appName: String, now: Date) -> AccessDecision
}

extension BlockingEngine {
    /// Temporarily unlocks one app. Re-locks automatically at expiry.
    @discardableResult
    func grantUnlock(_ subject: UnlockSubject, displayName: String, minutes: Int) throws -> ActiveUnlock {
        guard let unlock = try grantUnlocks([subject], displayName: displayName, minutes: minutes).first else {
            throw EngineError.invalidSubject
        }
        return unlock
    }

    /// Builds an `EngineStatus` from the shared store (both engines use it).
    func makeStatus(shared: SharedStore, isReady: Bool, now: Date = Date()) -> EngineStatus {
        let selection = shared.blockedSelection
        let isFamily = kind == .familyControls
        return EngineStatus(
            kind: kind,
            isReady: isReady,
            isDetached: shared.isDetached,
            emergencyUntil: shared.isEmergencyActive(at: now) ? shared.emergencyUntil : nil,
            activeUnlocks: shared.activeGrants(at: now).map(ActiveUnlock.init(grant:)).sorted { $0.expiresAt < $1.expiresAt },
            study: shared.activeStudy.flatMap { $0.isActive(at: now) ? StudySnapshot($0) : nil },
            blockedAppCount: isFamily ? selection.applicationTokens.count : shared.blockedAppKeys.count,
            blockedCategoryCount: isFamily ? selection.categoryTokens.count : 0,
            blockedWebDomainCount: isFamily ? selection.webDomainTokens.count : 0
        )
    }
}
