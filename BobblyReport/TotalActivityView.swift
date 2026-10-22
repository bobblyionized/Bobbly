//  TotalActivityView.swift
//  BobblyReport — the Stats tab's screen time under Screen Time: total,
//  daily average, pickups, a per-day chart and the most-used apps.
//  Rendered inside the report extension (UI-owned).
//  Input: TotalActivityConfiguration (ReportModels.swift).

import SwiftUI
import Charts

struct TotalActivityView: View {
    let configuration: TotalActivityConfiguration

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headline

                if configuration.days.count > 1 {
                    ReportPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Screen time a day")
                                .font(.headline)
                                .foregroundStyle(ReportTheme.ink)
                            ReportDayChart(days: configuration.days, height: 190)
                        }
                    }
                }

                if configuration.topApps.isEmpty {
                    ReportPanel {
                        Text("No screen time recorded in this range yet.")
                            .font(.callout)
                            .foregroundStyle(ReportTheme.inkSecondary)
                    }
                } else {
                    topApps
                }
            }
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ReportTheme.page)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ReportFormat.duration(configuration.totalDuration))
                .font(ReportTheme.display)
                .foregroundStyle(ReportTheme.ink)
            Text("\(ReportFormat.duration(configuration.averagePerDay)) a day on average, \(configuration.totalPickups) pickups")
                .font(.subheadline)
                .foregroundStyle(ReportTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var topApps: some View {
        let apps = Array(configuration.topApps.prefix(8))
        let longest = max(1, apps.first?.duration ?? 1)
        return ReportPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Most used")
                    .font(.headline)
                    .foregroundStyle(ReportTheme.ink)
                ForEach(apps) { app in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            ReportAppLabel(name: app.name, token: app.token)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(ReportTheme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(ReportFormat.duration(app.duration))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(ReportTheme.ink)
                        }
                        ReportBar(fraction: app.duration / longest)
                        Text("\(app.pickups) pickups, \(app.notifications) notifications")
                            .font(.caption)
                            .foregroundStyle(ReportTheme.inkTertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
