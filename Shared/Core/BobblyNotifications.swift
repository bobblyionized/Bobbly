//  BobblyNotifications.swift
//  Shared/Core — local notifications posted by the app, the shield-action
//  extension and the monitor. Tapping one opens the URL in `userInfo[urlKey]`.

import Foundation
import UserNotifications

enum BobblyNotifications {
    /// `userInfo` key holding the deep-link URL string to open on tap.
    static let urlKey = "bobbly.url"

    enum ID {
        static let talkToBobbly = "com.bobbly.notification.talk"
        static let gateRequest = "com.bobbly.notification.gate"
        static let emergencyEnded = "com.bobbly.notification.emergencyEnded"
        static let studyEnded = "com.bobbly.notification.studyEnded"
        static func unlockEnding(_ grantID: UUID) -> String { "com.bobbly.notification.unlockEnding.\(grantID.uuidString)" }
        static func unlockEnded(_ grantID: UUID) -> String { "com.bobbly.notification.unlockEnded.\(grantID.uuidString)" }
    }

    /// Posted when the shield's "Talk to Bobbly" button is pressed. Shields
    /// cannot open apps, so the user taps this banner to reach the chat.
    static func postTalkToBobbly(appName: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Bobbly is ready to talk"
        content.body = appName.map { "Tap to tell Bobbly why you want to open \($0)." }
            ?? "Tap to tell Bobbly why you want to open this app."
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = [urlKey: BobblyLink.chat(appName: appName, source: .shield).absoluteString]
        post(id: ID.talkToBobbly, content: content, after: nil)
    }

    /// Fallback when the Gate intent can't bring Bobbly to the foreground
    /// (system declined): tap to open the Gate. `appName == nil` = group mode.
    static func postGateRequest(appName: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Bobbly is here"
        content.body = appName.map { "\($0) is blocked. Tap to talk to Bobbly." }
            ?? "That app is blocked. Tap to talk to Bobbly."
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = [urlKey: BobblyLink.gate(appName: appName, source: .notification).absoluteString]
        post(id: ID.gateRequest, content: content, after: nil)
    }

    /// Warns shortly before an unlock ends.
    static func scheduleUnlockEnding(grantID: UUID, appName: String, endsAt: Date, now: Date = Date()) {
        let content = UNMutableNotificationContent()
        content.title = "1 minute left"
        content.body = "\(appName) locks again in a minute. Wrap it up!"
        content.sound = .default
        let fireIn = endsAt.addingTimeInterval(-60).timeIntervalSince(now)
        guard fireIn > 1 else { return }
        post(id: ID.unlockEnding(grantID), content: content, after: fireIn)
    }

    /// "Locked again" — immediately (`at == nil`, used by the monitor) or
    /// scheduled for the expiry (Shortcuts engine, which has no monitor).
    static func postUnlockEnded(grantID: UUID, appName: String, at date: Date? = nil, now: Date = Date()) {
        let content = UNMutableNotificationContent()
        content.title = "\(appName) is locked again"
        content.body = "Time's up. Bobbly is proud of you."
        post(id: ID.unlockEnded(grantID), content: content, after: date.map { $0.timeIntervalSince(now) })
    }

    static func postEmergencyEnded(at date: Date? = nil, now: Date = Date()) {
        let content = UNMutableNotificationContent()
        content.title = "Emergency unblock ended"
        content.body = "Your blocks are back on."
        post(id: ID.emergencyEnded, content: content, after: date.map { $0.timeIntervalSince(now) })
    }

    static func postStudyEnded(whitelistName: String, at date: Date? = nil, now: Date = Date()) {
        let content = UNMutableNotificationContent()
        content.title = "Study session complete"
        content.body = "\(whitelistName) is done. Bobbly is thrilled!"
        content.sound = .default
        post(id: ID.studyEnded, content: content, after: date.map { $0.timeIntervalSince(now) })
    }

    /// Removes every pending and delivered Bobbly notification (detach).
    /// Every notification this app schedules is a `com.bobbly.notification.*` one.
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    static func cancel(ids: [String]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func post(id: String, content: UNMutableNotificationContent, after seconds: TimeInterval?) {
        let trigger = seconds.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0), repeats: false) }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
