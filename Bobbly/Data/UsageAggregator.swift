//  UsageAggregator.swift
//  Bobbly/Data — pure aggregation + search over logged usage sessions.
//  No SwiftData here so it is trivially unit-testable.

import Foundation

/// Value copy of a `UsageSession`.
struct UsageRecord: Hashable, Sendable {
    var appName: String
    var appKey: String
    var start: Date
    /// `nil` = still open (never got a "closed" event).
    var end: Date?

    init(appName: String, appKey: String? = nil, start: Date, end: Date?) {
        self.appName = appName
        self.appKey = appKey ?? AppKey.normalize(appName)
        self.start = start
        self.end = end
    }
}

/// One bar / point in a chart. `appName == nil` means "all apps".
struct StatsPoint: Identifiable, Hashable, Sendable {
    var day: Date
    var appName: String?
    var minutes: Double

    var id: String { "\(appName ?? "*")|\(day.timeIntervalSince1970)" }
}

/// Totals for one app over a range.
struct AppUsageSummary: Identifiable, Hashable, Sendable {
    var appName: String
    var appKey: String
    var totalMinutes: Double
    var opens: Int

    var id: String { appKey }
}

/// What the screen-time searcher shows for one app + date range.
struct AppUsageSearchResult: Hashable, Sendable {
    var appName: String
    var range: DateInterval
    var totalMinutes: Double
    var averageMinutesPerDay: Double
    var longestSessionMinutes: Double
    var longestSessionStart: Date?
    var totalOpens: Int
    var opensPerDay: Double
    /// One point per day in the range (zero days included), oldest first.
    var daily: [StatsPoint]
}

enum UsageAggregator {
    /// A session that never received a "closed" event counts at most this long.
    static let openSessionCap: TimeInterval = 3 * 60 * 60

    /// Effective end of a record (open sessions are capped and never exceed `now`).
    static func effectiveEnd(of record: UsageRecord, now: Date) -> Date {
        if let end = record.end { return max(end, record.start) }
        return max(record.start, min(now, record.start.addingTimeInterval(openSessionCap)))
    }

    /// Seconds of `record` that fall inside `interval`.
    static func overlap(_ record: UsageRecord, with interval: DateInterval, now: Date) -> TimeInterval {
        let start = max(record.start, interval.start)
        let end = min(effectiveEnd(of: record, now: now), interval.end)
        return max(0, end.timeIntervalSince(start))
    }

    /// Start-of-day dates covering `range`, oldest first.
    static func days(in range: DateInterval, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: range.start)
        while day < range.end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Interval for the last `count` days including today.
    static func lastDays(_ count: Int, now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let todayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(max(1, count) - 1), to: todayStart) ?? todayStart
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        return DateInterval(start: start, end: end)
    }

    /// Minutes per day (and per app when `perApp`), zero-filled, oldest first.
    static func dailyTotals(_ records: [UsageRecord], range: DateInterval, perApp: Bool,
                            now: Date = Date(), calendar: Calendar = .current) -> [StatsPoint] {
        let dayList = days(in: range, calendar: calendar)
        var apps: [(key: String, name: String)] = [(key: "*", name: "*")]
        if perApp {
            apps = Dictionary(grouping: records, by: \.appKey)
                .map { entry -> (key: String, name: String) in
                    (key: entry.key, name: entry.value.first?.appName ?? entry.key)
                }
                .sorted { $0.name < $1.name }
        }

        var points: [StatsPoint] = []
        for day in dayList {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            guard let window = DateInterval(start: day, end: dayEnd).intersection(with: range) else { continue }
            for app in apps {
                let seconds = records
                    .filter { !perApp || $0.appKey == app.key }
                    .reduce(0) { $0 + overlap($1, with: window, now: now) }
                points.append(StatsPoint(day: day, appName: perApp ? app.name : nil, minutes: seconds / 60))
            }
        }
        return points
    }

    /// Per-app totals in `range`, most used first.
    static func summaries(_ records: [UsageRecord], range: DateInterval, now: Date = Date()) -> [AppUsageSummary] {
        Dictionary(grouping: records, by: \.appKey).compactMap { entry -> AppUsageSummary? in
            let key = entry.key
            let group = entry.value
            let seconds = group.reduce(0) { $0 + overlap($1, with: range, now: now) }
            let opens = group.filter { range.contains($0.start) }.count
            guard seconds > 0 || opens > 0 else { return nil }
            return AppUsageSummary(appName: group.first?.appName ?? key, appKey: key, totalMinutes: seconds / 60, opens: opens)
        }
        .sorted { $0.totalMinutes == $1.totalMinutes ? $0.appName < $1.appName : $0.totalMinutes > $1.totalMinutes }
    }

    /// App names matching `query` (prefix matches first, then substring), case/diacritic-insensitive.
    static func matchingAppNames(_ names: [String], query: String) -> [String] {
        let q = AppKey.normalize(query)
        let unique = Array(Set(names)).sorted()
        guard !q.isEmpty else { return unique }
        let prefix = unique.filter { AppKey.normalize($0).hasPrefix(q) }
        let contains = unique.filter { !AppKey.normalize($0).hasPrefix(q) && AppKey.normalize($0).contains(q) }
        return prefix + contains
    }

    /// The screen-time searcher. Picks the best matching app for `appQuery`
    /// (exact > prefix > substring) and computes its stats over `range`.
    static func search(_ records: [UsageRecord], appQuery: String, range: DateInterval,
                       now: Date = Date(), calendar: Calendar = .current) -> AppUsageSearchResult? {
        let names = records.map(\.appName)
        let q = AppKey.normalize(appQuery)
        guard !q.isEmpty else { return nil }
        let exact = names.first { AppKey.normalize($0) == q }
        guard let appName = exact ?? matchingAppNames(names, query: appQuery).first else { return nil }
        let key = AppKey.normalize(appName)
        let appRecords = records.filter { $0.appKey == key }

        let daily = dailyTotals(appRecords, range: range, perApp: false, now: now, calendar: calendar)
            .map { StatsPoint(day: $0.day, appName: appName, minutes: $0.minutes) }
        let total = daily.reduce(0) { $0 + $1.minutes }
        let dayCount = Double(max(1, daily.count))

        var longest: (minutes: Double, start: Date?) = (0, nil)
        for record in appRecords {
            let minutes = overlap(record, with: range, now: now) / 60
            if minutes > longest.minutes { longest = (minutes, record.start) }
        }
        let opens = appRecords.filter { range.contains($0.start) }.count

        return AppUsageSearchResult(
            appName: appName,
            range: range,
            totalMinutes: total,
            averageMinutesPerDay: total / dayCount,
            longestSessionMinutes: longest.minutes,
            longestSessionStart: longest.start,
            totalOpens: opens,
            opensPerDay: Double(opens) / dayCount,
            daily: daily
        )
    }

    /// "Time saved against your limit": for every day and every app with a
    /// limit, the unused part of the limit. Days in the future count nothing.
    static func timeSavedMinutes(_ records: [UsageRecord], limits: [String: Int], range: DateInterval,
                                 now: Date = Date(), calendar: Calendar = .current) -> Double {
        let activeLimits = limits.filter { $0.value > 0 }
        guard !activeLimits.isEmpty else { return 0 }
        let clipped = DateInterval(start: range.start, end: max(range.start, min(range.end, now)))
        let points = dailyTotals(records.filter { activeLimits[$0.appKey] != nil }, range: clipped, perApp: true, now: now, calendar: calendar)
        var saved = 0.0
        for day in days(in: clipped, calendar: calendar) {
            for (key, limit) in activeLimits {
                let used = points.first { $0.day == day && AppKey.normalize($0.appName ?? "") == key }?.minutes ?? 0
                saved += max(0, Double(limit) - used)
            }
        }
        return saved
    }
}
