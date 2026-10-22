//  ShieldPolicy.swift
//  Shared/Core — turns the SharedStore state into ManagedSettings shields.
//
//  Called by the app after every change, and by the monitor extension when an
//  unlock / emergency / study interval ends. Because both run the same
//  function on the same SharedStore, the shields are always derived from one
//  source of truth and re-locking cannot drift.

import Foundation
import FamilyControls
import ManagedSettings

enum ShieldPolicy {

    /// What `reconcile` decides to do, before touching ManagedSettings (unit-tested).
    enum Action: Equatable {
        /// State is unreadable (no engine recorded, or the App Group is missing
        /// in an extension): leave every shield exactly as it is.
        case skip(reason: String)
        /// Remove every Bobbly shield.
        case clear(reason: String)
        /// Apply the block list (and the study whitelist session, if running).
        case apply
    }

    /// Pure decision. Clearing only happens when the state *explicitly* says
    /// so (Shortcuts engine, detached, emergency); an unreadable store never
    /// unshields anything.
    static func action(engineKind: EngineKind?, isDetached: Bool, isEmergencyActive: Bool,
                       appGroupAvailable: Bool, requireAppGroup: Bool) -> Action {
        if requireAppGroup && !appGroupAvailable { return .skip(reason: "App Group unavailable") }
        guard let engineKind else { return .skip(reason: "no engine recorded") }
        if engineKind != .familyControls { return .clear(reason: "Shortcuts engine") }
        if isDetached { return .clear(reason: "detached") }
        if isEmergencyActive { return .clear(reason: "emergency") }
        return .apply
    }

    /// Re-derives every Bobbly shield from `shared`.
    /// - Parameter requireAppGroup: pass `true` from extensions — if the signer
    ///   dropped/renamed the App Group they see an empty private store and must
    ///   not act on it.
    /// - Returns: a short description of what was applied (for diagnostics).
    @discardableResult
    static func reconcile(shared: SharedStore = .shared, now: Date = Date(), requireAppGroup: Bool = false) -> String {
        let decision = action(engineKind: shared.engineKind, isDetached: shared.isDetached,
                              isEmergencyActive: shared.isEmergencyActive(at: now),
                              appGroupAvailable: AppGroup.isContainerAvailable, requireAppGroup: requireAppGroup)
        if case .skip(let reason) = decision { return "skipped (\(reason))" }

        shared.pruneExpiredGrants(now: now)
        if shared.isEmergencyActive(at: now) == false, shared.emergencyUntil != nil {
            shared.emergencyUntil = nil
        }
        if let study = shared.activeStudy, !study.isActive(at: now) {
            shared.recordStudyEnd(study, at: study.endsAt ?? now, reason: .completed)
            shared.activeStudy = nil
        }

        if case .clear(let reason) = decision {
            clearAll()
            return "cleared (\(reason))"
        }

        let unlocked = Set(shared.activeGrants(at: now).compactMap(\.applicationToken))
        if let study = shared.activeStudy, study.isActive(at: now) {
            let whitelist = study.selection
            // Whitelisted apps/sites stay usable while studying, even if they
            // are also on the block list (same rule as AccessPolicy).
            applyBlockList(shared.blockedSelection,
                           unlocked: unlocked.union(whitelist.applicationTokens),
                           allowedWebDomains: whitelist.webDomainTokens)
            applyStudy(whitelist: whitelist, unlocked: unlocked)
            return "block list + study '\(study.whitelistName)', \(unlocked.count) unlocked"
        } else {
            applyBlockList(shared.blockedSelection, unlocked: unlocked, allowedWebDomains: [])
            ManagedSettingsStore(named: .bobblyStudy).clearAllSettings()
            return "block list, \(unlocked.count) unlocked"
        }
    }

    /// Removes every shield Bobbly ever set (all named stores + the default store).
    static func clearAll() {
        for name in ManagedSettingsStore.Name.bobblyAll {
            ManagedSettingsStore(named: name).clearAllSettings()
        }
        ManagedSettingsStore().clearAllSettings()
    }

    // MARK: - Private

    /// - Parameters:
    ///   - unlocked: app tokens to leave unshielded (chat unlocks + study whitelist).
    ///   - allowedWebDomains: site tokens to leave unshielded (study whitelist).
    private static func applyBlockList(_ selection: FamilyActivitySelection, unlocked: Set<ApplicationToken>,
                                       allowedWebDomains: Set<WebDomainToken>) {
        let store = ManagedSettingsStore(named: .bobblyBlock)

        let apps = selection.applicationTokens.subtracting(unlocked)
        store.shield.applications = apps.isEmpty ? nil : apps

        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: unlocked)

        let sites = selection.webDomainTokens.subtracting(allowedWebDomains)
        store.shield.webDomains = sites.isEmpty ? nil : sites

        store.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: allowedWebDomains)
    }

    /// Blocks every app/site except the whitelist (Phone, Messages and
    /// Settings are exempt by iOS itself; Bobbly cannot shield itself).
    private static func applyStudy(whitelist: FamilyActivitySelection, unlocked: Set<ApplicationToken>) {
        let store = ManagedSettingsStore(named: .bobblyStudy)
        store.shield.applications = nil
        store.shield.applicationCategories = .all(except: whitelist.applicationTokens.union(unlocked))
        store.shield.webDomains = nil
        store.shield.webDomainCategories = .all(except: whitelist.webDomainTokens)
    }
}
