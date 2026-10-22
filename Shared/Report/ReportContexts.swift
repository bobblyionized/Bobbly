//  ReportContexts.swift
//  Shared/Report — compiled into the app and BobblyReport only.
//
//  The app embeds `DeviceActivityReport(context, filter:)`; the report
//  extension renders the scene whose `context` matches.

import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
    /// Stats tab: totals per day + top apps for the filter's date range.
    static let bobblyTotalActivity = Self("com.bobbly.report.totalActivity")
    /// Search screen: per-app totals/average/pickups for the picked apps + range.
    static let bobblyAppSearch = Self("com.bobbly.report.appSearch")
    /// Home: a compact "today so far" summary.
    static let bobblyTodaySummary = Self("com.bobbly.report.todaySummary")
}
