//  SearchViewModel.swift
//  Bobbly/Features/Search — screen-time searcher: app + date range →
//  total, average/day, longest session, opens/day, per-day bars.
//
//  Shortcuts engine: computed here from Bobbly's usage log (`result`).
//  FamilyControls: app names exist only inside the report extension, so the
//  user picks apps with `FamilyActivityPicker` (`pickerSelection`) and the view
//  embeds `DeviceActivityReport(reportContext, filter: reportFilter!)`.

import Foundation
import Observation
import DeviceActivity
import FamilyControls
import SwiftUI

enum SearchDatePreset: String, CaseIterable, Identifiable {
    case today
    case last7Days
    case last30Days
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .last7Days: return "7 days"
        case .last30Days: return "30 days"
        case .custom: return "Custom"
        }
    }
}

@Observable
@MainActor
final class SearchViewModel {
    unowned let env: AppEnvironment

    /// Search field text (app name). Updates `suggestions` live.
    var query: String = "" {
        didSet { if oldValue != query { updateSuggestions() } }
    }
    /// Date preset chips. Picking one (other than `.custom`) sets the dates.
    var preset: SearchDatePreset = .last7Days {
        didSet { if oldValue != preset { applyPreset() } }
    }
    /// Inclusive start day (DatePicker binding; switches preset to `.custom`).
    var startDate: Date
    /// Inclusive end day.
    var endDate: Date

    /// App names matching `query` (Shortcuts engine).
    private(set) var suggestions: [String] = []
    /// Result for the best match, or `nil` (no search yet / no match).
    private(set) var result: AppUsageSearchResult?
    private(set) var hasSearched = false

    // FamilyControls search input.
    var pickerSelection = FamilyActivitySelection()
    var isPickerPresented = false
    /// Non-nil once apps were picked; embed the report with it.
    private(set) var reportFilter: DeviceActivityFilter?

    init(env: AppEnvironment) {
        self.env = env
        let interval = UsageAggregator.lastDays(7)
        self.startDate = interval.start
        self.endDate = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
    }

    // MARK: Derived

    var dataSource: StatsDataSource {
        env.engines.status.kind == .familyControls ? .screenTimeReport : .shortcutsLog
    }

    var reportContext: DeviceActivityReport.Context { .bobblyAppSearch }

    /// [startDate 00:00, endDate+1 00:00).
    var dateInterval: DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let endDay = calendar.startOfDay(for: max(startDate, endDate))
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        return DateInterval(start: start, end: end)
    }

    /// Number of picked apps (FamilyControls).
    var pickedAppCount: Int { pickerSelection.applicationTokens.count }

    // MARK: Actions

    func onAppear() {
        updateSuggestions()
    }

    /// Runs the search for `query` over `dateInterval` (Shortcuts engine),
    /// or rebuilds `reportFilter` (FamilyControls).
    func search() {
        hasSearched = true
        switch dataSource {
        case .shortcutsLog:
            let interval = dateInterval
            let records = env.tracker.records(in: interval)
            result = UsageAggregator.search(records, appQuery: query, range: interval)
        case .screenTimeReport:
            env.shared.reportSearchQuery = query
            reportFilter = pickerSelection.applicationTokens.isEmpty && pickerSelection.categoryTokens.isEmpty
                ? nil
                : ReportFilters.daily(during: dateInterval,
                                      applications: pickerSelection.applicationTokens,
                                      categories: pickerSelection.categoryTokens,
                                      webDomains: pickerSelection.webDomainTokens)
        }
    }

    /// Tap on a suggestion: fills the field and searches.
    func select(suggestion: String) {
        query = suggestion
        search()
    }

    /// Called when the user edits a DatePicker (switches preset to custom, re-searches).
    func datesChanged() {
        preset = .custom
        if hasSearched { search() }
    }

    func presentPicker() {
        isPickerPresented = true
    }

    /// Call after FamilyActivityPicker closes.
    func applyPickerSelection() {
        search()
    }

    func clear() {
        query = ""
        result = nil
        reportFilter = nil
        hasSearched = false
        pickerSelection = FamilyActivitySelection()
    }

    // MARK: Helpers

    private func updateSuggestions() {
        guard dataSource == .shortcutsLog else { suggestions = []; return }
        suggestions = Array(UsageAggregator.matchingAppNames(env.tracker.knownAppNames(), query: query).prefix(8))
    }

    private func applyPreset() {
        let days: Int
        switch preset {
        case .today: days = 1
        case .last7Days: days = 7
        case .last30Days: days = 30
        case .custom: return
        }
        let interval = UsageAggregator.lastDays(days)
        startDate = interval.start
        endDate = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        if hasSearched { search() }
    }
}
