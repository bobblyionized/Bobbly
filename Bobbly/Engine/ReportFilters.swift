//  ReportFilters.swift
//  Bobbly/Engine — DeviceActivityFilter builders for the embedded
//  `DeviceActivityReport` views (FamilyControls engine only).

import Foundation
import DeviceActivity
import ManagedSettings

enum ReportFilters {
    /// Daily segments over `interval` for the current user (individual
    /// authorization) on this device. Empty token sets = all apps.
    /// Uses `init(segment:devices:applications:categories:webDomains:)`
    /// ("Creates a new filter for the current user"; `devices: nil` = this device).
    static func daily(during interval: DateInterval,
                      applications: Set<ApplicationToken> = [],
                      categories: Set<ActivityCategoryToken> = [],
                      webDomains: Set<WebDomainToken> = []) -> DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .daily(during: interval),
            devices: nil,
            applications: applications,
            categories: categories,
            webDomains: webDomains
        )
    }

    /// Today from midnight to the next midnight.
    static func today(now: Date = Date(), calendar: Calendar = .current) -> DeviceActivityFilter {
        daily(during: UsageAggregator.lastDays(1, now: now, calendar: calendar))
    }
}
