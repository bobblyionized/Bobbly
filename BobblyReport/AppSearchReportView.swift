//  AppSearchReportView.swift
//  BobblyReport — screen-time search results under Screen Time: per app,
//  the total, daily average, pickups and busiest day (DeviceActivity has no
//  per-session data, so the busiest day stands in for "longest session"),
//  plus a per-day chart. Rendered inside the report extension (UI-owned).
//  Input: AppSearchConfiguration (ReportModels.swift).

import SwiftUI
import Charts

struct AppSearchReportView: View {
    let configuration: AppSearchConfiguration

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if configuration.results.isEmpty {
                    ReportPanel {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No usage found")
                                .font(ReportTheme.heading)
                                .foregroundStyle(ReportTheme.ink)
                            Text(configuration.query.isEmpty
                                 ? "None of the picked apps were used in this range. Try a longer range."
                                 : "None of the picked apps match \u{201C}\(configuration.query)\u{201D} in this range.")
                                .font(.callout)
                                .foregroundStyle(ReportTheme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ForEach(configuration.results) { item in
                        ResultCard(item: item)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ReportTheme.page)
    }
}

private struct ResultCard: View {
    let item: AppSearchResultItem

    private let columns = [GridItem(.flexible(), spacing: 10, alignment: .top),
                           GridItem(.flexible(), spacing: 10, alignment: .top)]

    var body: some View {
        ReportPanel {
            VStack(alignment: .leading, spacing: 14) {
                ReportAppLabel(name: item.name, token: item.token)
                    .font(ReportTheme.heading)
                    .foregroundStyle(ReportTheme.ink)
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ReportFigure(value: ReportFormat.duration(item.totalDuration), label: "Total")
                    ReportFigure(value: ReportFormat.duration(item.averagePerDay), label: "Average a day")
                    ReportFigure(value: pickupsPerDay, label: "Pickups a day",
                           detail: "\(item.totalPickups) in total")
                    ReportFigure(value: item.busiestDay.map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "None",
                           label: "Busiest day",
                           detail: item.busiestDay == nil ? nil : ReportFormat.duration(item.busiestDayDuration))
                }

                if item.daily.count > 1 {
                    ReportDayChart(days: item.daily, height: 130)
                }
            }
        }
    }

    private var pickupsPerDay: String {
        item.pickupsPerDay < 10
            ? String(format: "%.1f", item.pickupsPerDay)
            : "\(Int(item.pickupsPerDay.rounded()))"
    }
}

private struct ReportFigure: View {
    let value: String
    let label: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(ReportTheme.numeralSmall)
                .foregroundStyle(ReportTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.footnote)
                .foregroundStyle(ReportTheme.inkSecondary)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ReportTheme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ReportTheme.sunken, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
