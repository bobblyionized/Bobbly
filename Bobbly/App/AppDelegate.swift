//  AppDelegate.swift
//  Bobbly/App — notification taps → deep links. Buffers URLs that arrive
//  before the SwiftUI scene has wired up `urlHandler` (cold launch from a tap).

import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var pendingURLs: [URL] = []

    /// Set by BobblyApp once the environment exists; flushes buffered URLs.
    var urlHandler: (@MainActor (URL) -> Void)? {
        didSet { flushPendingURLs() }
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    private func route(_ url: URL) {
        if let urlHandler {
            urlHandler(url)
        } else {
            pendingURLs.append(url)
        }
    }

    private func flushPendingURLs() {
        guard let urlHandler, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        for url in urls { urlHandler(url) }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let urlString = response.notification.request.content.userInfo[BobblyNotifications.urlKey] as? String
        if let urlString, let url = URL(string: urlString) {
            Task { @MainActor in
                self.route(url)
            }
        }
        completionHandler()
    }
}
