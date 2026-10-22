//  BobblyReportExtension.swift
//  BobblyReport — ExtensionKit entry point. Each scene answers one
//  `DeviceActivityReport.Context` the app embeds (see Shared/Report).

import DeviceActivity
import SwiftUI

@main
struct BobblyReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityReport { configuration in
            TotalActivityView(configuration: configuration)
        }
        AppSearchReport { configuration in
            AppSearchReportView(configuration: configuration)
        }
        TodaySummaryReport { configuration in
            TodaySummaryView(configuration: configuration)
        }
    }
}
