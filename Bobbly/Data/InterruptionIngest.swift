//  InterruptionIngest.swift
//  Bobbly/Data — pure helpers for copying the shield extension's per-day
//  interruption counts (SharedStore) into SwiftData history.

import Foundation

enum InterruptionIngest {
    struct Item: Equatable {
        let dayKey: String
        let delta: Int
    }

    /// Days whose shared count exceeds what was already imported, oldest first.
    static func pending(shared: [String: Int], imported: [String: Int]) -> [Item] {
        shared.compactMap { entry -> Item? in
            let delta = entry.value - (imported[entry.key] ?? 0)
            return delta > 0 ? Item(dayKey: entry.key, delta: delta) : nil
        }
        .sorted { (Double($0.dayKey) ?? 0) < (Double($1.dayKey) ?? 0) }
    }

    /// Timestamp to log a day's interruptions at: noon of that day, but never
    /// in the future (today before noon → now).
    static func date(forDayKey key: String, now: Date) -> Date {
        guard let seconds = Double(key) else { return now }
        return min(now, Date(timeIntervalSince1970: seconds).addingTimeInterval(12 * 3600))
    }
}
