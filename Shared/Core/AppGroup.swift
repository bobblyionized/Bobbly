//  AppGroup.swift
//  Shared/Core — compiled into the app and every extension.

import Foundation

/// The App Group shared by the app, the intents (which run in-process) and
/// all four extensions. Everything that crosses a process boundary goes
/// through `AppGroup.defaults` via `SharedStore`.
enum AppGroup {
    static let identifier = "group.com.bobbly.shared"

    /// Shared defaults. If the signer stripped the App Group entitlement this
    /// still returns a usable (but process-local) store, so nothing crashes;
    /// `isContainerAvailable` reports the problem for diagnostics.
    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard

    /// `true` when the App Group entitlement survived signing.
    static var isContainerAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }
}
