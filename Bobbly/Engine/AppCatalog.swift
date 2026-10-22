//  AppCatalog.swift
//  Bobbly/Engine — built-in list of popular apps + URL schemes for the
//  Shortcuts fallback (tracked-app picker and automation walkthrough).

import Foundation

struct CatalogApp: Identifiable, Hashable, Sendable {
    /// Stable id == normalized name.
    let id: String
    let name: String
    /// Scheme without "://", used to re-open the app after an unlock.
    let urlScheme: String
    /// SF Symbol used as a placeholder icon.
    let symbol: String

    init(_ name: String, scheme: String, symbol: String) {
        self.id = AppKey.normalize(name)
        self.name = name
        self.urlScheme = scheme
        self.symbol = symbol
    }
}

enum AppCatalog {
    static let popular: [CatalogApp] = [
        CatalogApp("Instagram", scheme: "instagram", symbol: "camera"),
        CatalogApp("TikTok", scheme: "snssdk1233", symbol: "music.note"),
        CatalogApp("YouTube", scheme: "youtube", symbol: "play.rectangle"),
        CatalogApp("X", scheme: "twitter", symbol: "xmark"),
        CatalogApp("Facebook", scheme: "fb", symbol: "person.2"),
        CatalogApp("Snapchat", scheme: "snapchat", symbol: "bolt"),
        CatalogApp("Reddit", scheme: "reddit", symbol: "bubble.left.and.bubble.right"),
        CatalogApp("Threads", scheme: "barcelona", symbol: "at"),
        CatalogApp("Pinterest", scheme: "pinterest", symbol: "pin"),
        CatalogApp("Discord", scheme: "discord", symbol: "gamecontroller"),
        CatalogApp("Twitch", scheme: "twitch", symbol: "tv"),
        CatalogApp("Netflix", scheme: "nflx", symbol: "film"),
        CatalogApp("WhatsApp", scheme: "whatsapp", symbol: "phone.bubble"),
        CatalogApp("Telegram", scheme: "tg", symbol: "paperplane"),
        CatalogApp("LinkedIn", scheme: "linkedin", symbol: "briefcase"),
        CatalogApp("Tumblr", scheme: "tumblr", symbol: "text.bubble"),
        CatalogApp("Spotify", scheme: "spotify", symbol: "music.note.list"),
        CatalogApp("BeReal", scheme: "bereal", symbol: "camera.on.rectangle"),
    ]

    static func search(_ query: String) -> [CatalogApp] {
        let q = AppKey.normalize(query)
        guard !q.isEmpty else { return popular }
        return popular.filter { $0.id.contains(q) }
    }

    static func app(named name: String) -> CatalogApp? {
        let key = AppKey.normalize(name)
        return popular.first { $0.id == key }
    }

    /// Step-by-step instructions for the two automations one app needs.
    static func automationSteps(for appName: String) -> [String] {
        [
            "Open the Shortcuts app and tap Automation › New Automation (+).",
            "Choose App, pick \(appName), select \"Is Opened\" and \"Run Immediately\", then Next.",
            "Add the action \"Check Access in Bobbly\" and set App to \(appName).",
            "Add \"If\": Check Access result is false → \"Open URLs\" with bobbly://gate?app=\(appName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? appName).",
            "Also add \"Log App Event in Bobbly\" (App: \(appName), Event: Opened) at the top. Tap Done.",
            "Create a second automation: App › \(appName) › \"Is Closed\" › Run Immediately.",
            "Add \"Log App Event in Bobbly\" (App: \(appName), Event: Closed). Tap Done.",
        ]
    }
}
