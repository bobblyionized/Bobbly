//  NotificationService.swift
//  Bobbly/App — notification permission state (tutorial step 3, diagnostics).

import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
final class NotificationService {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return true
        case .denied, .notDetermined: return false
        @unknown default: return false
        }
    }

    var isDenied: Bool { authorization == .denied }

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
    }

    /// Shows the system prompt (only works while `.notDetermined`).
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refresh()
        return granted
    }
}
