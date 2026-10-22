//  ReportTheme.swift
//  BobblyReport — the app's "still water" tokens for the report extension
//  (UI-owned). The extension can't see Bobbly/UI/Theme.swift, so the values
//  are mirrored here; keep them in sync with Theme.Palette.

import SwiftUI
import UIKit
import Charts
import FamilyControls
import ManagedSettings

enum ReportTheme {
    static let page = color(light: 0xEDF2EF, dark: 0x0B1F27)
    static let surface = color(light: 0xF9FBFA, dark: 0x13303A)
    static let sunken = color(light: 0xE1E9E5, dark: 0x0F2830)
    static let hairline = color(light: 0xC9D7D2, dark: 0x24464F)
    static let grid = color(light: 0xDCE5E1, dark: 0x1E3E48)

    static let ink = color(light: 0x12303C, dark: 0xE6EFEC)
    static let inkSecondary = color(light: 0x47616C, dark: 0xA2B8B7)
    static let inkTertiary = color(light: 0x748B93, dark: 0x6F8C90)

    static let pond = color(light: 0x1E6F6A, dark: 0x5BC2B5)
    static let float = color(light: 0xF0602C, dark: 0xFF8552)
    static let amber = color(light: 0x95590A, dark: 0xF2B544)

    /// Chart series slot 1 (single-series bars).
    static let series = color(light: 0x009483, dark: 0x14A394)

    static let panelRadius: CGFloat = 22

    static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let numeral = Font.system(.title2, design: .rounded).weight(.semibold)
    static let numeralSmall = Font.system(.title3, design: .rounded).weight(.semibold)
    static let heading = Font.system(.title3, design: .rounded).weight(.semibold)

    static func color(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            ReportTheme.rgb(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}

// MARK: - Shared pieces

/// Tonal panel, same as the app's `Panel`.
struct ReportPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(ReportTheme.surface,
                        in: RoundedRectangle(cornerRadius: ReportTheme.panelRadius, style: .continuous))
    }
}

/// Real app icon and name when the token is known, else the name.
struct ReportAppLabel: View {
    let name: String
    let token: ApplicationToken?

    var body: some View {
        if let token {
            Label(token)
        } else {
            Label(name, systemImage: "app.dashed")
        }
    }
}

/// Thin horizontal bar.
struct ReportBar: View {
    let fraction: Double
    var tint: Color = ReportTheme.series

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ReportTheme.sunken)
                Capsule()
                    .fill(tint)
                    .frame(width: max(5, proxy.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// Minutes per day as bars.
struct ReportDayChart: View {
    let days: [ReportDay]
    var height: CGFloat = 180

    var body: some View {
        let format: Date.FormatStyle = days.count <= 8
            ? Date.FormatStyle().weekday(.abbreviated)
            : Date.FormatStyle().month(.abbreviated).day()
        Chart(days) { day in
            BarMark(x: .value("Day", day.date, unit: .day),
                    y: .value("Minutes", day.duration / 60),
                    width: days.count <= 8 ? .fixed(20) : .ratio(0.62))
                .foregroundStyle(ReportTheme.series)
                .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: days.count <= 8 ? 1 : 7)) { _ in
                AxisValueLabel(format: format, centered: true)
                    .foregroundStyle(ReportTheme.inkTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(ReportTheme.grid)
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(ReportFormat.duration(minutes * 60))
                    }
                }
                .foregroundStyle(ReportTheme.inkTertiary)
            }
        }
        .frame(height: height)
    }
}
