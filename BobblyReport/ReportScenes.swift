//  ReportScenes.swift
//  BobblyReport — DeviceActivityReportScene implementations (Core-owned logic).
//  App names exist only here (sandboxed), so all name-based aggregation and
//  the searcher's filtering happen in this extension.

import Foundation
import DeviceActivity
import ManagedSettings
import SwiftUI

// MARK: - Aggregation

/// One app's usage on one day, flattened from DeviceActivityData.
struct ReportRow {
    let key: String
    let name: String
    let token: ApplicationToken?
    let day: Date
    let duration: TimeInterval
    let pickups: Int
    let notifications: Int
}

enum ReportAggregation {
    /// Flattens the async result tree into rows + per-day totals.
    static func collect(_ data: DeviceActivityResults<DeviceActivityData>,
                        calendar: Calendar = .current) async -> (rows: [ReportRow], days: [ReportDay]) {
        var rows: [ReportRow] = []
        var dayTotals: [Date: ReportDay] = [:]

        for await activity in data {
            for await segment in activity.activitySegments {
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                var dayPickups = 0
                for await category in segment.categories {
                    for await app in category.applications {
                        let name = app.application.localizedDisplayName ?? app.application.bundleIdentifier ?? "App"
                        let key = app.application.bundleIdentifier ?? name
                        rows.append(ReportRow(key: key, name: name, token: app.application.token, day: day,
                                              duration: app.totalActivityDuration, pickups: app.numberOfPickups,
                                              notifications: app.numberOfNotifications))
                        dayPickups += app.numberOfPickups
                    }
                }
                var total = dayTotals[day] ?? ReportDay(date: day, duration: 0, pickups: 0)
                total.duration += segment.totalActivityDuration
                total.pickups += dayPickups
                dayTotals[day] = total
            }
        }
        return (rows, dayTotals.values.sorted { $0.date < $1.date })
    }

    /// Per-app totals, most used first.
    static func apps(from rows: [ReportRow]) -> [ReportAppUsage] {
        var byKey: [String: ReportAppUsage] = [:]
        for row in rows {
            var usage = byKey[row.key] ?? ReportAppUsage(id: row.key, name: row.name, token: row.token, duration: 0, pickups: 0, notifications: 0)
            usage.duration += row.duration
            usage.pickups += row.pickups
            usage.notifications += row.notifications
            byKey[row.key] = usage
        }
        return byKey.values.sorted { $0.duration > $1.duration }
    }
}

// MARK: - Scenes

/// Stats tab.
struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .bobblyTotalActivity
    let content: (TotalActivityConfiguration) -> TotalActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TotalActivityConfiguration {
        let (rows, days) = await ReportAggregation.collect(data)
        let total = days.reduce(0) { $0 + $1.duration }
        return TotalActivityConfiguration(
            totalDuration: total,
            averagePerDay: days.isEmpty ? 0 : total / Double(days.count),
            totalPickups: days.reduce(0) { $0 + $1.pickups },
            days: days,
            topApps: Array(ReportAggregation.apps(from: rows).prefix(10))
        )
    }
}

/// Screen-time searcher: the host's filter already limits apps + dates;
/// the optional name query (SharedStore, best effort) narrows further.
struct AppSearchReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .bobblyAppSearch
    let content: (AppSearchConfiguration) -> AppSearchReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> AppSearchConfiguration {
        let (rows, days) = await ReportAggregation.collect(data)
        let query = SharedStore.shared.reportSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = AppKey.normalize(query)
        let matching = normalizedQuery.isEmpty ? rows : rows.filter { AppKey.normalize($0.name).contains(normalizedQuery) }
        let dayCount = max(1, days.count)

        let results = Dictionary(grouping: matching, by: \.key).map { entry -> AppSearchResultItem in
            let key = entry.key
            let appRows = entry.value
            var perDay: [Date: ReportDay] = [:]
            for row in appRows {
                var day = perDay[row.day] ?? ReportDay(date: row.day, duration: 0, pickups: 0)
                day.duration += row.duration
                day.pickups += row.pickups
                perDay[row.day] = day
            }
            let daily = perDay.values.sorted { $0.date < $1.date }
            let total = daily.reduce(0) { $0 + $1.duration }
            let pickups = daily.reduce(0) { $0 + $1.pickups }
            let busiest = daily.max { $0.duration < $1.duration }
            return AppSearchResultItem(
                id: key, name: appRows.first?.name ?? key, token: appRows.first?.token,
                totalDuration: total, averagePerDay: total / Double(dayCount),
                totalPickups: pickups, pickupsPerDay: Double(pickups) / Double(dayCount),
                busiestDay: busiest?.date, busiestDayDuration: busiest?.duration ?? 0, daily: daily)
        }
        .sorted { $0.totalDuration > $1.totalDuration }

        return AppSearchConfiguration(query: query, dayCount: days.count, results: results)
    }
}

/// Home "today so far" card.
struct TodaySummaryReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .bobblyTodaySummary
    let content: (TodaySummaryConfiguration) -> TodaySummaryView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodaySummaryConfiguration {
        let (rows, days) = await ReportAggregation.collect(data)
        return TodaySummaryConfiguration(
            totalDuration: days.reduce(0) { $0 + $1.duration },
            pickups: days.reduce(0) { $0 + $1.pickups },
            topApps: Array(ReportAggregation.apps(from: rows).prefix(3))
        )
    }
}
