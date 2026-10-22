//  StatsViewModel.swift
//  Bobbly/Features/Stats — Swift Charts data: daily totals per app, 7/30-day
//  trend, streak, time saved vs limits, blocked interruptions.
//
//  Under FamilyControls, real per-app screen time only exists inside the
//  sandboxed report extension, so the view embeds
//  `DeviceActivityReport(reportContext, filter: reportFilter)` for the usage
//  charts and uses this model's Bobbly-side numbers for everything else.

import Foundation
import Observation
import DeviceActivity
import SwiftData
import SwiftUI

enum StatsRange: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }
    var days: Int { self == .week ? 7 : 30 }
    var title: String { self == .week ? "7 days" : "30 days" }
}

enum StatsDataSource: Equatable {
    /// FamilyControls: usage charts come from the DeviceActivityReport extension.
    case screenTimeReport
    /// Shortcuts: usage comes from Bobbly's own open/close log.
    case shortcutsLog
}

@Observable
@MainActor
final class StatsViewModel {
    unowned let env: AppEnvironment

    /// Selected range (segmented control). Changing it refreshes.
    var range: StatsRange = .week {
        didSet { if oldValue != range { refresh() } }
    }

    // Usage (Shortcuts engine; empty under FamilyControls → use the report).
    /// One point per day, all apps combined (trend line/bars), oldest first.
    private(set) var dailyTotals: [StatsPoint] = []
    /// One point per day per app (stacked bars; `appName` is the series).
    private(set) var dailyPerApp: [StatsPoint] = []
    /// Most-used apps in range.
    private(set) var topApps: [AppUsageSummary] = []
    private(set) var totalMinutes: Double = 0
    private(set) var averageMinutesPerDay: Double = 0
    /// Unused part of daily limits in range (needs limits on tracked apps).
    private(set) var timeSavedMinutes: Double = 0

    // Bobbly-side numbers (both engines).
    private(set) var blockedInterruptions: Int = 0
    private(set) var unlocksGranted: Int = 0
    private(set) var unlocksDeclined: Int = 0
    private(set) var emergencyUnlocks: Int = 0
    /// Minutes spent in study sessions in range.
    private(set) var focusMinutes: Int = 0
    /// Per-day blocked interruptions (bar chart), oldest first.
    private(set) var dailyInterruptions: [StatsPoint] = []

    init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: Derived

    var dataSource: StatsDataSource {
        env.engines.status.kind == .familyControls ? .screenTimeReport : .shortcutsLog
    }

    var currentStreak: Int { env.companion.snapshot.currentStreak }
    var bestStreak: Int { env.companion.snapshot.bestStreak }

    var dateInterval: DateInterval { UsageAggregator.lastDays(range.days) }

    /// FamilyControls: embed `DeviceActivityReport(reportContext, filter: reportFilter)`.
    var reportContext: DeviceActivityReport.Context { .bobblyTotalActivity }
    var reportFilter: DeviceActivityFilter { ReportFilters.daily(during: dateInterval) }

    /// `true` when there is nothing at all to chart (show an empty state).
    var isEmpty: Bool {
        dataSource == .shortcutsLog && totalMinutes == 0 && blockedInterruptions == 0 && unlocksGranted == 0
    }

    // MARK: Actions

    func onAppear() {
        refresh()
    }

    func refresh() {
        let now = Date()
        let interval = dateInterval
        let tracker = env.tracker

        if dataSource == .shortcutsLog {
            let records = tracker.records(in: interval)
            dailyTotals = UsageAggregator.dailyTotals(records, range: interval, perApp: false, now: now)
            dailyPerApp = UsageAggregator.dailyTotals(records, range: interval, perApp: true, now: now)
            topApps = UsageAggregator.summaries(records, range: interval, now: now)
            totalMinutes = dailyTotals.reduce(0) { $0 + $1.minutes }
            averageMinutesPerDay = totalMinutes / Double(max(1, range.days))
            timeSavedMinutes = UsageAggregator.timeSavedMinutes(records, limits: tracker.dailyLimits(), range: interval, now: now)
        } else {
            dailyTotals = []
            dailyPerApp = []
            topApps = []
            totalMinutes = 0
            averageMinutesPerDay = 0
            timeSavedMinutes = 0
        }

        blockedInterruptions = tracker.interruptionCount(in: interval)
        dailyInterruptions = UsageAggregator.days(in: interval).map { day -> StatsPoint in
            let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
            return StatsPoint(day: day, appName: nil, minutes: Double(tracker.interruptionCount(in: DateInterval(start: day, end: end))))
        }

        let events = tracker.unlockEvents(in: interval)
        unlocksGranted = events.filter { $0.granted && !$0.isEmergency }.count
        unlocksDeclined = events.filter { !$0.granted }.count
        emergencyUnlocks = events.filter { $0.isEmergency }.count

        focusMinutes = studyMinutes(in: interval, now: now)
    }

    /// Opens the screen-time searcher.
    func openSearch() {
        env.router.present(.search)
    }

    /// Opens the permission tutorial (e.g. from the "Set up Screen Time" empty state).
    func openTutorial() {
        env.router.presentTutorial()
    }

    // MARK: Helpers

    private func studyMinutes(in interval: DateInterval, now: Date) -> Int {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<StudySession>(predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end })
        let sessions = (try? env.context.fetch(descriptor)) ?? []
        return sessions.reduce(0) { $0 + $1.focusMinutes(at: now) }
    }
}
