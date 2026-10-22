//  StatsView.swift
//  Bobbly/Features/Stats — screen time (report extension under Screen Time,
//  Bobbly's own log under Shortcuts) plus Bobbly's side: blocked attempts,
//  unlocks, focus time and streak. Contract: StatsViewModel.

import SwiftUI
import Charts
import DeviceActivity

struct StatsView: View {
    @Bindable var model: StatsViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Apps shown as their own chart series; the rest fold into "Other".
    private let seriesLimit = 5

    init(model: StatsViewModel) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    rangePicker
                    if model.isEmpty {
                        Panel {
                            EmptyStateView(title: "Nothing to chart yet",
                                           message: "Stats fill in as your Shortcuts automations log app opens. If nothing shows up after using a tracked app, check the setup.",
                                           mood: .okay) {
                                Button("Check the setup") { model.openTutorial() }
                                    .buttonStyle(.bobbly(.secondary, fullWidth: false))
                            }
                        }
                    } else {
                        usageSection
                    }
                    bobblySection
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .bobblyPage()
            .refreshable { model.refresh() }
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.openSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search usage")
                }
            }
        }
        .onAppear { model.onAppear() }
    }

    // MARK: Range

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Picker("Range", selection: $model.range) {
                ForEach(StatsRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            Text(Fmt.dayRange(model.dateInterval))
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
    }

    // MARK: Usage

    @ViewBuilder private var usageSection: some View {
        switch model.dataSource {
        case .screenTimeReport:
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionTitle("Screen time")
                DeviceActivityReport(model.reportContext, filter: model.reportFilter)
                    .frame(height: 720)
                    .frame(maxWidth: .infinity)
            }

        case .shortcutsLog:
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionTitle("Screen time")

                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.minutes(model.totalMinutes))
                        .scaledFont(size: 44, relativeTo: .largeTitle, weight: .bold)
                        .foregroundStyle(Theme.Palette.ink)
                        .contentTransition(.numericText())
                    Text("in tracked apps, \(Fmt.minutes(model.averageMinutesPerDay)) a day on average")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                .accessibilityElement(children: .combine)

                Panel {
                    StackedUsageChart(points: foldedPoints, series: seriesNames, range: model.range)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.s) {
                    StatTile(value: Fmt.minutes(model.averageMinutesPerDay),
                             label: "Average a day",
                             systemImage: "chart.bar.fill",
                             tint: Theme.Palette.pond)
                    StatTile(value: Fmt.minutes(model.timeSavedMinutes),
                             label: "Time saved",
                             systemImage: "leaf.fill",
                             tint: Theme.Palette.reed,
                             detail: model.timeSavedMinutes > 0 ? "Unused time under your daily limits" : "Set daily limits in Blocked apps")
                }

                if !model.topApps.isEmpty {
                    topAppsList
                }
            }
        }
    }

    private var topAppsList: some View {
        let apps = Array(model.topApps.prefix(8))
        let maxMinutes = max(1, apps.first?.totalMinutes ?? 1)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Most used")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.ink)
            VStack(spacing: Theme.Spacing.s) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Circle()
                                .fill(color(forSeriesAt: index))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(app.appName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: Theme.Spacing.xs)
                            Text(Fmt.minutes(app.totalMinutes))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.Palette.ink)
                        }
                        ProgressTrack(progress: app.totalMinutes / maxMinutes, tint: color(forSeriesAt: index), height: 5)
                        Text(Fmt.count(app.opens, "open"))
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(app.appName), \(Fmt.minutes(app.totalMinutes)), \(Fmt.count(app.opens, "open"))")
                }
            }
            .padding(Theme.Spacing.m)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
    }

    // MARK: Bobbly's side

    private var bobblySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionTitle("Bobbly's side")

            Panel {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Blocked attempts")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Text("\(model.blockedInterruptions)")
                            .font(Theme.Typography.numeralSmall)
                            .foregroundStyle(Theme.Palette.ink)
                            .contentTransition(.numericText())
                    }
                    if model.blockedInterruptions == 0 {
                        Text("No blocked attempts in this range.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                    } else {
                        DailyBarChart(points: model.dailyInterruptions, range: model.range,
                                      valueName: "Attempts", tint: Theme.Palette.series[0]) { value in
                            "\(Int(value))"
                        }
                    }
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.s) {
                StatTile(value: "\(model.unlocksGranted)", label: "Unlocks granted",
                         systemImage: "lock.open.fill", tint: Theme.Palette.amber)
                StatTile(value: "\(model.unlocksDeclined)", label: "Times you said no",
                         systemImage: "hand.thumbsup.fill", tint: Theme.Palette.reed)
                StatTile(value: Fmt.minutes(Double(model.focusMinutes)), label: "Focus time",
                         systemImage: "book.fill", tint: Theme.Palette.reed)
                StatTile(value: "\(model.emergencyUnlocks)", label: "Emergency unblocks",
                         systemImage: "exclamationmark.octagon.fill", tint: Theme.Palette.signal)
                StatTile(value: Fmt.count(model.currentStreak, "day"), label: "Current streak",
                         systemImage: "flame.fill", tint: Theme.Palette.float,
                         detail: "Best: \(Fmt.count(model.bestStreak, "day"))")
            }
        }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .top),
               GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .top)]
    }

    // MARK: Chart data (presentation only: fold small apps into "Other")

    private var seriesNames: [String] {
        let top = model.topApps.prefix(seriesLimit).map(\.appName)
        let hasOther = model.topApps.count > seriesLimit
        return hasOther ? top + ["Other"] : top
    }

    private var foldedPoints: [UsageSeriesPoint] {
        let keep = Set(model.topApps.prefix(seriesLimit).map(\.appName))
        var totals: [String: UsageSeriesPoint] = [:]
        for point in model.dailyPerApp where point.minutes > 0 {
            let name = point.appName ?? "Other"
            let series = keep.contains(name) ? name : "Other"
            let key = "\(point.day.timeIntervalSince1970)|\(series)"
            var entry = totals[key] ?? UsageSeriesPoint(day: point.day, series: series, minutes: 0)
            entry.minutes += point.minutes
            totals[key] = entry
        }
        return totals.values.sorted { $0.day < $1.day }
    }

    private func color(forSeriesAt index: Int) -> Color {
        index < seriesLimit && index < Theme.Palette.series.count ? Theme.Palette.series[index] : Theme.Palette.seriesOther
    }
}

// MARK: - Charts

struct UsageSeriesPoint: Identifiable {
    let day: Date
    let series: String
    var minutes: Double
    var id: String { "\(day.timeIntervalSince1970)|\(series)" }
}

/// Minutes per day, stacked by app. Legend underneath (identity never by colour alone).
private struct StackedUsageChart: View {
    let points: [UsageSeriesPoint]
    let series: [String]
    let range: StatsRange

    private var colors: [Color] {
        series.enumerated().map { index, name in
            name == "Other" || index >= Theme.Palette.series.count ? Theme.Palette.seriesOther : Theme.Palette.series[index]
        }
    }

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value("Day", point.day, unit: .day),
                    y: .value("Minutes", point.minutes),
                    width: BobblyChartStyle.barWidth(for: range))
                .foregroundStyle(by: .value("App", point.series))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: series, range: colors)
        .chartLegend(position: .bottom, alignment: .leading, spacing: Theme.Spacing.s)
        .chartXAxis { BobblyChartStyle.dayAxis(for: range) }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.Palette.grid)
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(Fmt.minutes(minutes))
                    }
                }
                .foregroundStyle(Theme.Palette.inkTertiary)
            }
        }
        .frame(height: 230)
    }
}

/// One series per day (blocked attempts, search results).
struct DailyBarChart: View {
    let points: [StatsPoint]
    let range: StatsRange
    let valueName: String
    var tint: Color = Theme.Palette.series[0]
    let format: (Double) -> String

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value("Day", point.day, unit: .day),
                    y: .value(valueName, point.minutes),
                    width: BobblyChartStyle.barWidth(for: range))
                .foregroundStyle(tint)
                .cornerRadius(4)
        }
        .chartXAxis { BobblyChartStyle.dayAxis(for: range) }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.Palette.grid)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(format(number))
                    }
                }
                .foregroundStyle(Theme.Palette.inkTertiary)
            }
        }
        .frame(height: 170)
    }
}

/// Shared chart axis/mark specs.
enum BobblyChartStyle {
    static func barWidth(for range: StatsRange) -> MarkDimension {
        range == .week ? .fixed(20) : .ratio(0.62)
    }

    static func dayAxis(for range: StatsRange) -> some AxisContent {
        let format: Date.FormatStyle = range == .week
            ? Date.FormatStyle().weekday(.abbreviated)
            : Date.FormatStyle().month(.abbreviated).day()
        return AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) { _ in
            AxisValueLabel(format: format, centered: true)
                .foregroundStyle(Theme.Palette.inkTertiary)
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    StatsView(model: env.stats)
        .environment(env)
}
