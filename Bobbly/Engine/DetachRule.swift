//  DetachRule.swift
//  Bobbly/Engine — the ONE rule for which engine performs an emergency
//  detach, shared by the in-app Emergency screen (EngineSelector) and the
//  "Detach Bobbly" Siri intent so both always do the same thing.

import Foundation

enum DetachRule {
    /// Detach through FamilyControls (clear stores, stop monitoring, revoke
    /// authorization) whenever it is the recorded engine OR Screen Time access
    /// exists at all — e.g. the user switched to Shortcuts while still
    /// authorized. Both paths set the same "Bobbly off" flags.
    static func usesFamilyControls(engineKind: EngineKind?, isAuthorized: Bool) -> Bool {
        engineKind == .familyControls || isAuthorized
    }

    /// Runs the detach with the engine chosen by `usesFamilyControls`.
    @MainActor
    static func detach(shared: SharedStore, familyControls: FamilyControlsEngine, shortcuts: ShortcutsEngine) async -> DetachReport {
        if usesFamilyControls(engineKind: shared.engineKind, isAuthorized: familyControls.isAuthorized) {
            return await familyControls.detach()
        }
        return await shortcuts.detach()
    }
}
