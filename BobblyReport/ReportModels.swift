//  ReportModels.swift
//  BobblyReport — configuration values produced by the report scenes and
//  rendered by the (UI-owned) report views. Plain values; no I/O.

import Foundation
import ManagedSettings

/// One app's usage in the filter's range.
struct ReportAppUsage: Identifiable, Hashable {
    /// Bundle id when available, else the name.
    let id: String
    var name: String
    /// Render the real icon with `Label(token)` when non-nil.
    var token: ApplicationToken?
    var duration: TimeInterval
    var pickups: Int
    var notifications: Int
}

/// One day's total.
struct ReportDay: Identifiable, Hashable {
    var id: Date { date }
    /// Start of day.
    let date: Date
    var duration: TimeInterval
    var pickups: Int
}

/// Stats tab (`.bobblyTotalActivity`).
struct TotalActivityConfiguration: Equatable {
    var totalDuration: TimeInterval
    var averagePerDay: TimeInterval
    var totalPickups: Int
    /// Oldest first, one per day segment.
    var days: [ReportDay]
    /// Most used first (top 10).
    var topApps: [ReportAppUsage]

    static let empty = TotalActivityConfiguration(totalDuration: 0, averagePerDay: 0, totalPickups: 0, days: [], topApps: [])
}

/// One app in the search results.
struct AppSearchResultItem: Identifiable, Hashable {
    let id: String
    var name: String
    var token: ApplicationToken?
    var totalDuration: TimeInterval
    var averagePerDay: TimeInterval
    /// "Opens" ≈ pickups that started in this app.
    var totalPickups: Int
    var pickupsPerDay: Double
    /// DeviceActivity exposes no per-session data; the busiest day stands in
    /// for "longest session".
    var busiestDay: Date?
    var busiestDayDuration: TimeInterval
    /// Oldest first.
    var daily: [ReportDay]
}

/// Search sheet (`.bobblyAppSearch`).
struct AppSearchConfiguration: Equatable {
    /// Name filter read from SharedStore (best effort; may be empty).
    var query: String
    var dayCount: Int
    var results: [AppSearchResultItem]

    static let empty = AppSearchConfiguration(query: "", dayCount: 0, results: [])
}

/// Home card (`.bobblyTodaySummary`).
struct TodaySummaryConfiguration: Equatable {
    var totalDuration: TimeInterval
    var pickups: Int
    /// Top 3 apps today.
    var topApps: [ReportAppUsage]

    static let empty = TodaySummaryConfiguration(totalDuration: 0, pickups: 0, topApps: [])
}

enum ReportFormat {
    /// "2h 05m" / "14m".
    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: interval) ?? "0m"
    }
}
