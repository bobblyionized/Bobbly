//  Preferences.swift
//  Bobbly/Data — app-only user preferences (standard UserDefaults), with
//  values the extensions need mirrored into SharedStore.

import Foundation
import Observation

@Observable
@MainActor
final class Preferences {
    private let defaults: UserDefaults
    private let shared: SharedStore

    private enum Key {
        static let hasCompletedTutorial = "bobbly.prefs.hasCompletedTutorial"
        static let defaultEmergencyMinutes = "bobbly.prefs.defaultEmergencyMinutes"
        static let hapticsEnabled = "bobbly.prefs.hapticsEnabled"
        static let companionName = "bobbly.prefs.companionName"
        static let setupMode = "bobbly.prefs.setupMode"
    }

    /// The tutorial auto-presents on launch until this is `true`.
    var hasCompletedTutorial: Bool {
        didSet { defaults.set(hasCompletedTutorial, forKey: Key.hasCompletedTutorial) }
    }

    /// Pre-selected duration on the Emergency screen.
    var defaultEmergencyMinutes: Int {
        didSet { defaults.set(defaultEmergencyMinutes, forKey: Key.defaultEmergencyMinutes) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    /// Unlocks per day that don't cost a life (mirrored to SharedStore for the shield).
    var dailyFreeUnlocks: Int {
        didSet { shared.dailyFreeUnlocks = dailyFreeUnlocks }
    }

    /// Shortcuts engine setup style. Defaults to `.quick` where supported (iOS 26+).
    var setupMode: SetupMode {
        didSet { defaults.set(setupMode.rawValue, forKey: Key.setupMode) }
    }

    init(defaults: UserDefaults = .standard, shared: SharedStore = .shared) {
        self.defaults = defaults
        self.shared = shared
        self.hasCompletedTutorial = defaults.bool(forKey: Key.hasCompletedTutorial)
        self.defaultEmergencyMinutes = (defaults.object(forKey: Key.defaultEmergencyMinutes) as? Int) ?? 30
        self.hapticsEnabled = (defaults.object(forKey: Key.hapticsEnabled) as? Bool) ?? true
        self.dailyFreeUnlocks = shared.dailyFreeUnlocks
        let storedMode = defaults.string(forKey: Key.setupMode).flatMap(SetupMode.init(rawValue:))
        // Quick setup needs iOS 26; never come back as `.quick` where it can't work.
        self.setupMode = (storedMode == .quick && !QuickSetup.isAvailable) ? .perApp : (storedMode ?? SetupMode.recommended)
    }
}
