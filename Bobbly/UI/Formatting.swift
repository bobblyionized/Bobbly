//  Formatting.swift
//  Bobbly/UI — display strings for durations, countdowns and counts.
//  Pure presentation; no business rules.

import Foundation

enum Fmt {
    /// "2h 05m", "14m", "0m".
    static func minutes(_ minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        let hours = total / 60
        let rest = total % 60
        if hours > 0 {
            return rest == 0 ? "\(hours)h" : String(format: "%dh %02dm", hours, rest)
        }
        return "\(rest)m"
    }

    /// Same as `minutes(_:)` for seconds.
    static func duration(_ seconds: TimeInterval) -> String {
        minutes(seconds / 60)
    }

    /// Ticking countdown: "7:05" or "1:02:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// "3:45 PM".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Duration option: "15 min", "1 hour", "4 hours".
    static func option(minutes: Int) -> String {
        if minutes >= 60 && minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(minutes) min"
    }

    /// Compact duration option: "15m", "1h", "4h".
    static func shortOption(minutes: Int) -> String {
        if minutes >= 60 && minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    /// "1 app", "3 apps".
    static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// "Oct 15 – Oct 21" (the interval's end is exclusive).
    static func dayRange(_ interval: DateInterval) -> String {
        let style = Date.FormatStyle().month(.abbreviated).day()
        let lastDay = interval.end.addingTimeInterval(-1)
        let start = interval.start.formatted(style)
        let end = lastDay.formatted(style)
        return start == end ? start : "\(start) – \(end)"
    }

    /// "Mon, Oct 21".
    static func day(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day())
    }

    /// One decimal for small rates ("2.4"), whole numbers otherwise.
    static func rate(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
    }
}
