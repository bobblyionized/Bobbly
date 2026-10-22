//  BobblyModelContainer.swift
//  Bobbly/Data — one ModelContainer for the app process (UI + App Intents).
//
//  Stored in the app's own container, NOT the App Group: if a signer strips
//  the App Group entitlement, a group-container store would fail to open.

import Foundation
import SwiftData

enum BobblyModelContainer {
    static let schema = Schema([
        TrackedApp.self,
        Whitelist.self,
        StudySession.self,
        UsageSession.self,
        UnlockEvent.self,
        InterruptionEvent.self,
        CompanionState.self,
    ])

    /// The process-wide container. App Intents run in-process and use it too.
    static let shared: ModelContainer = make(inMemory: false)

    /// Never crashes: falls back to an in-memory store if the on-disk store
    /// cannot be opened (diagnostics will show `isUsingFallbackStore`).
    static func make(inMemory: Bool) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fallbackError = String(describing: error)
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // An in-memory store with a valid schema cannot fail to open.
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }

    /// Set when the on-disk store failed to open.
    private(set) static var fallbackError: String?

    static var isUsingFallbackStore: Bool { fallbackError != nil }

    /// In-memory container pre-filled with sample data for SwiftUI previews and tests.
    @MainActor
    static func preview() -> ModelContainer {
        let container = make(inMemory: true)
        PreviewData.populate(container.mainContext)
        return container
    }
}

/// Sample rows for previews.
@MainActor
enum PreviewData {
    static func populate(_ context: ModelContext) {
        let now = Date()
        let apps = [
            TrackedApp(name: "Instagram", urlScheme: "instagram", dailyLimitMinutes: 30),
            TrackedApp(name: "TikTok", urlScheme: "snssdk1233", dailyLimitMinutes: 20),
            TrackedApp(name: "YouTube", urlScheme: "youtube", dailyLimitMinutes: 45),
        ]
        for app in apps { context.insert(app) }

        for dayOffset in 0..<14 {
            let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            for (index, app) in apps.enumerated() {
                let start = Calendar.current.date(bySettingHour: 9 + index * 3, minute: 0, second: 0, of: day) ?? day
                let minutes = Double(5 + ((dayOffset * 7 + index * 11) % 40))
                context.insert(UsageSession(appName: app.name, start: start, end: start.addingTimeInterval(minutes * 60)))
            }
        }

        context.insert(Whitelist(name: "Study", allowedAppKeys: ["notes", "calculator"]))
        context.insert(UnlockEvent(appName: "Instagram", appKey: "instagram", reason: "reply to my mom", categoryRaw: "communication", minutes: 15, granted: true))
        context.insert(InterruptionEvent(appName: "TikTok", source: .gate))
        context.insert(CompanionState())
        try? context.save()
    }
}
