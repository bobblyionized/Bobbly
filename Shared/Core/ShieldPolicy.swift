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

    /// Re-derives every Bobbly shield from `shared`.
    /// - Returns: a short description of what was applied (for diagnostics).
    @discardableResult
    static func reconcile(shared: SharedStore = .shared, now: Date = Date()) -> String {
        shared.pruneExpiredGrants(now: now)

        if shared.isEmergencyActive(at: now) == false, shared.emergencyUntil != nil {
            shared.emergencyUntil = nil
        }
        if let study = shared.activeStudy, !study.isActive(at: now) {
            shared.activeStudy = nil
            shared.lastStudyEndedAt = study.endsAt ?? now
        }

        guard shared.engineKind == .familyControls else {
            clearAll()
            return "cleared (engine is not FamilyControls)"
        }
        if shared.isDetached {
            clearAll()
            return "cleared (detached)"
        }
        if shared.isEmergencyActive(at: now) {
            clearAll()
            return "cleared (emergency)"
        }

        let unlocked = Set(shared.activeGrants(at: now).compactMap(\.applicationToken))
        applyBlockList(shared.blockedSelection, unlocked: unlocked)

        if let study = shared.activeStudy, study.isActive(at: now) {
            applyStudy(whitelist: study.selection, unlocked: unlocked)
            return "block list + study '\(study.whitelistName)', \(unlocked.count) unlocked"
        } else {
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

    private static func applyBlockList(_ selection: FamilyActivitySelection, unlocked: Set<ApplicationToken>) {
        let store = ManagedSettingsStore(named: .bobblyBlock)

        let apps = selection.applicationTokens.subtracting(unlocked)
        store.shield.applications = apps.isEmpty ? nil : apps

        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: unlocked)

        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens

        store.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
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
