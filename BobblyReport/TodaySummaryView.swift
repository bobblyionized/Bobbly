//  TodaySummaryView.swift
//  BobblyReport — Home's "today so far" card: screen time, pickups and the
//  top three apps. Rendered inside the report extension (UI-owned).
//  Input: TodaySummaryConfiguration (ReportModels.swift).

import SwiftUI

struct TodaySummaryView: View {
    let configuration: TodaySummaryConfiguration

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .background(ReportTheme.page)
    }

    private var content: some View {
        ReportPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ReportFormat.duration(configuration.totalDuration))
                            .font(ReportTheme.display)
                            .foregroundStyle(ReportTheme.ink)
                        Text("screen time today")
                            .font(.footnote)
                            .foregroundStyle(ReportTheme.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(configuration.pickups)")
                            .font(ReportTheme.numeralSmall)
                            .foregroundStyle(ReportTheme.ink)
                        Text(configuration.pickups == 1 ? "pickup" : "pickups")
                            .font(.footnote)
                            .foregroundStyle(ReportTheme.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                if configuration.topApps.isEmpty {
                    Text("No screen time yet today.")
                        .font(.callout)
                        .foregroundStyle(ReportTheme.inkSecondary)
                } else {
                    let longest = max(1, configuration.topApps.map(\.duration).max() ?? 1)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(configuration.topApps) { app in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    ReportAppLabel(name: app.name, token: app.token)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ReportTheme.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(ReportFormat.duration(app.duration))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(ReportTheme.ink)
                                }
                                ReportBar(fraction: app.duration / longest)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}
