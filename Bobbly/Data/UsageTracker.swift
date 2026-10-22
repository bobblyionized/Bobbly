//  UsageTracker.swift
//  Bobbly/Data — writes/reads usage, interruptions and unlock history in
//  SwiftData. Used by ViewModels and by App Intents (in-process, main actor).

import Foundation
import SwiftData

@MainActor
final class UsageTracker {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Session logging (Shortcuts automations)

    /// "App opened": closes any dangling open session of the same app and starts a new one.
    func logOpened(appName: String, at date: Date = Date()) {
        closeOpenSessions(appKey: AppKey.normalize(appName), at: date)
        context.insert(UsageSession(appName: displayName(for: appName), start: date))
        save()
    }

    /// "App opened" from the quick-setup Gate. Without the optional "Is Closed"
    /// automation there will never be a close event, so the open is logged as a
    /// zero-length session: Stats/Search count the open without inventing time.
    func logGateOpen(appName: String, tracksTime: Bool, at date: Date = Date()) {
        if tracksTime {
            logOpened(appName: appName, at: date)
            return
        }
        closeOpenSessions(appKey: AppKey.normalize(appName), at: date)
        context.insert(UsageSession(appName: displayName(for: appName), start: date, end: date))
        save()
    }

    /// "App closed": ends the most recent open session; ignores closes without an open.
    func logClosed(appName: String, at date: Date = Date()) {
        closeOpenSessions(appKey: AppKey.normalize(appName), at: date)
        save()
    }

    private func closeOpenSessions(appKey: String, at date: Date) {
        let descriptor = FetchDescriptor<UsageSession>(
            predicate: #Predicate { $0.appKey == appKey && $0.end == nil }
        )
        for session in (try? context.fetch(descriptor)) ?? [] {
            session.end = min(max(date, session.start), session.start.addingTimeInterval(UsageAggregator.openSessionCap))
        }
    }

    /// Prefer the tracked app's canonical spelling ("Instagram" not "instagram").
    private func displayName(for appName: String) -> String {
        let key = AppKey.normalize(appName)
        let descriptor = FetchDescriptor<TrackedApp>(predicate: #Predicate { $0.appKey == key })
        return (try? context.fetch(descriptor).first?.name) ?? appName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Interruptions & unlocks

    func logInterruption(appName: String, source: InterruptionSource, count: Int = 1, at date: Date = Date()) {
        guard count > 0 else { return }
        context.insert(InterruptionEvent(appName: appName, date: date, source: source, count: count))
        save()
    }

    /// One blocked attempt = one interruption: `CheckAccessIntent` logs the
    /// attempt and its shortcut then opens the Gate, which must not count it
    /// again. Logs only if no interruption for the same app exists within `window`.
    /// - Returns: `true` if it was logged.
    @discardableResult
    func logInterruptionIfNew(appName: String, source: InterruptionSource,
                              window: TimeInterval = 120, at date: Date = Date()) -> Bool {
        let since = date.addingTimeInterval(-window)
        let descriptor = FetchDescriptor<InterruptionEvent>(predicate: #Predicate { $0.date >= since })
        let key = AppKey.normalize(appName)
        let recent = (try? context.fetch(descriptor)) ?? []
        if recent.contains(where: { AppKey.normalize($0.appName) == key && $0.date <= date }) { return false }
        logInterruption(appName: appName, source: source, at: date)
        return true
    }

    @discardableResult
    func logUnlock(appName: String, appKey: String?, reason: String, category: String, minutes: Int,
                   granted: Bool, isEmergency: Bool = false, costLife: Bool = false, at date: Date = Date()) -> UnlockEvent {
        let event = UnlockEvent(appName: appName, appKey: appKey, reason: reason, categoryRaw: category,
                                minutes: minutes, granted: granted, isEmergency: isEmergency, costLife: costLife, date: date)
        context.insert(event)
        save()
        return event
    }

    // MARK: - Queries

    /// Usage records overlapping `range` (includes sessions that started up to a day earlier).
    func records(in range: DateInterval) -> [UsageRecord] {
        let lower = range.start.addingTimeInterval(-24 * 60 * 60)
        let upper = range.end
        let descriptor = FetchDescriptor<UsageSession>(
            predicate: #Predicate { $0.start >= lower && $0.start < upper },
            sortBy: [SortDescriptor(\.start)]
        )
        let now = Date()
        return ((try? context.fetch(descriptor)) ?? [])
            .map(\.record)
            .filter { UsageAggregator.overlap($0, with: range, now: now) > 0 || range.contains($0.start) }
    }

    /// Every app name seen in usage logs or tracked apps (search suggestions).
    func knownAppNames() -> [String] {
        let tracked = ((try? context.fetch(FetchDescriptor<TrackedApp>())) ?? []).map(\.name)
        let logged = ((try? context.fetch(FetchDescriptor<UsageSession>())) ?? []).map(\.appName)
        return Array(Set(tracked + logged)).sorted()
    }

    func interruptionCount(in range: DateInterval) -> Int {
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<InterruptionEvent>(predicate: #Predicate { $0.date >= start && $0.date < end })
        return ((try? context.fetch(descriptor)) ?? []).reduce(0) { $0 + $1.count }
    }

    func unlockEvents(in range: DateInterval) -> [UnlockEvent] {
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<UnlockEvent>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// `[appKey: dailyLimitMinutes]` for tracked apps with a limit.
    func dailyLimits() -> [String: Int] {
        let apps = (try? context.fetch(FetchDescriptor<TrackedApp>())) ?? []
        var limits: [String: Int] = [:]
        for app in apps where app.dailyLimitMinutes > 0 { limits[app.appKey] = app.dailyLimitMinutes }
        return limits
    }

    func save() {
        do { try context.save() } catch { SharedStore.shared.appendLog("SwiftData save failed: \(error)") }
    }
}
