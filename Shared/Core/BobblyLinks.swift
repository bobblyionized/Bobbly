//  BobblyLinks.swift
//  Shared/Core — deep-link URLs. Parsed by `DeepLink` in the app.

import Foundation

enum BobblyLink {
    static let scheme = "bobbly"

    enum Host: String {
        case gate
        case emergency
        case chat
        case tutorial
    }

    enum Query {
        static let app = "app"
        static let source = "source"
    }

    enum Source: String {
        case shortcuts
        case shield
        case notification
    }

    /// `bobbly://gate?app=instagram` — what a Shortcuts automation opens.
    static func gate(appName: String?, source: Source = .shortcuts) -> URL {
        build(.gate, items: [
            appName.map { URLQueryItem(name: Query.app, value: $0) },
            URLQueryItem(name: Query.source, value: source.rawValue),
        ])
    }

    /// `bobbly://emergency`
    static var emergency: URL { build(.emergency, items: []) }

    /// `bobbly://chat?app=…` — opens the chat directly (shield notification tap).
    static func chat(appName: String?, source: Source) -> URL {
        build(.chat, items: [
            appName.map { URLQueryItem(name: Query.app, value: $0) },
            URLQueryItem(name: Query.source, value: source.rawValue),
        ])
    }

    /// `bobbly://tutorial`
    static var tutorial: URL { build(.tutorial, items: []) }

    private static func build(_ host: Host, items: [URLQueryItem?]) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host.rawValue
        let query = items.compactMap { $0 }
        components.queryItems = query.isEmpty ? nil : query
        return components.url ?? URL(string: "\(scheme)://\(host.rawValue)")!
    }
}
