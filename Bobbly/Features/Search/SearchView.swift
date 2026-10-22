//  SearchView.swift
//  Bobbly/Features/Search — screen-time searcher: an app plus a date range
//  gives its total, daily average, longest session, opens and a per-day
//  chart. Under Screen Time the results render inside the report extension.
//  Contract: SearchViewModel.

import SwiftUI
import DeviceActivity
import FamilyControls

struct SearchView: View {
    @State private var model: SearchViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isQueryFocused: Bool
    /// Bumped on every search the user runs, so the Screen Time report reloads
    /// even when only the name filter changed (the filter itself is equal).
    @State private var reportRevision = 0

    init(model: SearchViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if model.dataSource == .shortcutsLog {
                        queryField(text: $model.query)
                        if showsSuggestions {
                            suggestions
                        }
                    } else {
                        appPicker(nameFilter: $model.query)
                    }
                    dateControls
                    Button {
                        isQueryFocused = false
                        runSearch()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bobblyPrimary)
                    .disabled(!canSearch)

                    results
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xxl)
                .animation(Theme.Motion.standard, value: model.preset)
                .animation(Theme.Motion.reveal, value: model.result)
            }
            .scrollDismissesKeyboard(.interactively)
            .bobblyPage()
            .navigationTitle("Search usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .familyActivityPicker(isPresented: $model.isPickerPresented, selection: $model.pickerSelection)
        .onChange(of: model.isPickerPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented { model.applyPickerSelection() }
        }
        .onAppear { model.onAppear() }
    }

    // MARK: Input

    private func queryField(text: Binding<String>) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Palette.inkTertiary)
                .accessibilityHidden(true)
            TextField("App name, like Instagram", text: text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.ink)
                .focused($isQueryFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { runSearch() }
            if !model.query.isEmpty {
                Button {
                    clearQuery(text)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Palette.inkTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.Palette.surface, in: Capsule())
        .overlay { Capsule().stroke(Theme.Palette.hairline, lineWidth: 1) }
    }

    private func runSearch() {
        model.search()
        reportRevision += 1
    }

    /// Shortcuts: the query is the whole search, so clear everything.
    /// Screen Time: the query only narrows the picked apps, so keep the picks
    /// and the report, drop the name filter and re-run.
    private func clearQuery(_ text: Binding<String>) {
        switch model.dataSource {
        case .shortcutsLog:
            model.clear()
        case .screenTimeReport:
            text.wrappedValue = ""
            if model.hasSearched { runSearch() }
        }
    }

    private var showsSuggestions: Bool {
        !model.suggestions.isEmpty && model.result?.appName != model.query
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(model.query.isEmpty ? "Apps Bobbly knows" : "Matching apps")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSecondary)
            FlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
                ForEach(model.suggestions, id: \.self) { name in
                    Button {
                        isQueryFocused = false
                        model.select(suggestion: name)
                    } label: {
                        Label(name, systemImage: AppCatalog.app(named: name)?.symbol ?? "app.dashed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.Palette.sunken, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func appPicker(nameFilter: Binding<String>) -> some View {
        let picked = model.pickedAppCount
        let categories = model.pickerSelection.categoryTokens.count
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button {
                model.presentPicker()
            } label: {
                IconRow(systemImage: "apps.iphone",
                        title: picked == 0 && categories == 0 ? "Choose apps to look up" : pickedSummary(apps: picked, categories: categories),
                        detail: picked == 0 && categories == 0 ? "Screen Time keeps app names private, so you pick them here." : "Tap to change") {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                }
                .padding(Theme.Spacing.s)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            }
            .buttonStyle(.plain)

            if picked > 0 {
                TokenList(tokens: model.pickerSelection.applicationTokens, limit: 5)
                    .padding(.horizontal, Theme.Spacing.xs)
            }

            queryField(text: nameFilter)
            Text("Optional: narrows the picked apps by name.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkTertiary)
        }
    }

    private func pickedSummary(apps: Int, categories: Int) -> String {
        var parts: [String] = []
        if apps > 0 { parts.append(Fmt.count(apps, "app")) }
        if categories > 0 { parts.append(Fmt.count(categories, "category", "categories")) }
        return parts.joined(separator: ", ") + " picked"
    }

    private var canSearch: Bool {
        switch model.dataSource {
        case .shortcutsLog:
            return !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .screenTimeReport:
            return model.pickedAppCount > 0 || !model.pickerSelection.categoryTokens.isEmpty
        }
    }

    // MARK: Dates

    private var dateControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionTitle("When")
            FlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
                ForEach(SearchDatePreset.allCases) { preset in
                    ChoiceChip(title: preset.title, isSelected: model.preset == preset) {
                        model.preset = preset
                    }
                }
            }
            if model.preset == .custom {
                VStack(spacing: 0) {
                    DatePicker("From", selection: startBinding, in: ...Date.now, displayedComponents: .date)
                        .padding(.vertical, Theme.Spacing.xs)
                    Divider().overlay(Theme.Palette.hairline)
                    DatePicker("To", selection: endBinding, in: ...Date.now, displayedComponents: .date)
                        .padding(.vertical, Theme.Spacing.xs)
                }
                .padding(.horizontal, Theme.Spacing.m)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .transition(.opacity)
            } else {
                Text(Fmt.dayRange(model.dateInterval))
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
    }

    /// DatePicker edits only (programmatic preset changes don't call `datesChanged()`).
    private var startBinding: Binding<Date> {
        Binding(get: { model.startDate }, set: { model.startDate = $0; model.datesChanged() })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { model.endDate }, set: { model.endDate = $0; model.datesChanged() })
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        switch model.dataSource {
        case .shortcutsLog:
            if let result = model.result {
                SearchResultView(result: result, columns: columns)
            } else if model.hasSearched {
                Panel {
                    EmptyStateView(title: "No usage for \u{201C}\(model.query)\u{201D}",
                                   message: "Check the spelling or try a longer range. Bobbly only knows apps that your Shortcuts automations log.",
                                   mood: .okay)
                }
            } else {
                hint("Look up any app Bobbly tracks: its total, daily average, longest session and opens.")
            }

        case .screenTimeReport:
            if let filter = model.reportFilter {
                DeviceActivityReport(model.reportContext, filter: filter)
                    .id(reportRevision)
                    .frame(height: 640)
                    .frame(maxWidth: .infinity)
            } else if model.hasSearched {
                InlineNotice(kind: .info, text: "Pick at least one app first.")
            } else {
                hint("Pick apps to see their total, daily average, pickups and busiest day.")
            }
        }
    }

    private func hint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            BobblyCharacter(mood: .happy, size: 44, isAnimated: false)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .top),
               GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .top)]
    }
}

// MARK: - Result (Shortcuts engine)

private struct SearchResultView: View {
    let result: AppUsageSearchResult
    let columns: [GridItem]

    private var chartRange: StatsRange { result.daily.count <= 8 ? .week : .month }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                AppGlyph(systemImage: AppCatalog.app(named: result.appName)?.symbol ?? "app.dashed", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.appName)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(Fmt.dayRange(result.range))
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.s) {
                StatTile(value: Fmt.minutes(result.totalMinutes), label: "Total",
                         systemImage: "hourglass", tint: Theme.Palette.pond)
                StatTile(value: Fmt.minutes(result.averageMinutesPerDay), label: "Average a day",
                         systemImage: "chart.bar.fill", tint: Theme.Palette.pond)
                StatTile(value: Fmt.minutes(result.longestSessionMinutes), label: "Longest session",
                         systemImage: "stopwatch.fill", tint: Theme.Palette.float,
                         detail: result.longestSessionStart.map { "Started \(Fmt.day($0)), \(Fmt.time($0))" })
                StatTile(value: Fmt.rate(result.opensPerDay), label: "Opens a day",
                         systemImage: "arrow.up.forward.app.fill", tint: Theme.Palette.amber,
                         detail: "\(Fmt.count(result.totalOpens, "open")) in total")
            }

            if result.daily.count > 1 {
                Panel {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Minutes a day")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.ink)
                        DailyBarChart(points: result.daily, range: chartRange, valueName: "Minutes",
                                      tint: Theme.Palette.series[0]) { value in
                            Fmt.minutes(value)
                        }
                    }
                }
            }
        }
    }
}
