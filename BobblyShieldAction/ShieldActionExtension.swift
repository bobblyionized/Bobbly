//  ShieldActionExtension.swift
//  BobblyShieldAction — principal class (see Info.plist).
//
//  Primary "Talk to Bobbly": shields can't open apps (Apple limit), so we
//  store the token for the app and post a notification; tapping it opens
//  bobbly://chat?source=shield. Response `.defer` keeps the shield up and
//  refreshes it ("Tap the notification ↑").
//  Secondary "Go back": counts a blocked interruption and closes the app.

import Foundation
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    private let shared = SharedStore.shared

    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let tokenData = TokenCoding.encode(application)
        let name = shared.lastShieldedApp.flatMap { $0.applicationTokenData == tokenData ? $0.name : nil }
        completionHandler(respond(to: action, request: PendingShieldRequest(
            applicationTokenData: tokenData, webDomainTokenData: nil, appName: name, requestedAt: Date())))
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action, request: PendingShieldRequest(
            applicationTokenData: nil, webDomainTokenData: TokenCoding.encode(webDomain), appName: nil, requestedAt: Date())))
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action, request: PendingShieldRequest(
            applicationTokenData: nil, webDomainTokenData: nil, appName: nil, requestedAt: Date()),
            attemptKey: "category:" + (TokenCoding.encode(category)?.base64EncodedString() ?? "?")))
    }

    private func respond(to action: ShieldAction, request: PendingShieldRequest,
                         attemptKey: String? = nil) -> ShieldActionResponse {
        // One blocked attempt per app, however many shield buttons get pressed.
        let key = attemptKey
            ?? request.applicationTokenData.map { "app:" + $0.base64EncodedString() }
            ?? request.webDomainTokenData.map { "web:" + $0.base64EncodedString() }
            ?? "unknown"
        switch action {
        case .primaryButtonPressed:
            shared.recordShieldInterruption(attemptKey: key)
            shared.pendingShieldRequest = request
            shared.lastShieldNotificationAt = Date()
            BobblyNotifications.postTalkToBobbly(appName: request.appName)
            shared.appendLog("shield: talk to Bobbly (\(request.appName ?? "unknown app"))")
            return .defer
        case .secondaryButtonPressed:
            shared.recordShieldInterruption(attemptKey: key)
            return .close
        @unknown default:
            return .close
        }
    }
}
