//  ActivityNames.swift
//  Shared/Core — names of ManagedSettings stores and DeviceActivity
//  activities, plus schedule construction. Must be identical in the app and
//  the monitor extension, which is why it lives here.

import Foundation
import DeviceActivity
import ManagedSettings

extension ManagedSettingsStore.Name {
    /// Shields for the user's block list (minus active unlocks).
    static let bobblyBlock = Self("com.bobbly.store.block")
    /// Shields for a running study session (everything except the whitelist).
    static let bobblyStudy = Self("com.bobbly.store.study")

    /// Every store Bobbly writes to. Detach clears all of them.
    static let bobblyAll: [ManagedSettingsStore.Name] = [.bobblyBlock, .bobblyStudy]
}

extension DeviceActivityName {
    /// Repeating midnight-to-midnight activity; its start resets daily counters.
    static let bobblyDaily = Self("com.bobbly.activity.daily")

    // Triggers get a unique name per instance, so stopping an old trigger (the
    // monitor does that in `intervalDidEnd`) can never cancel a newer one.
    static let bobblyEmergencyPrefix = "com.bobbly.activity.emergency."
    static let bobblyStudyPrefix = "com.bobbly.activity.study."
    static let bobblyUnlockPrefix = "com.bobbly.activity.unlock."

    /// Trigger: STARTS when Emergency unblock expires -> shields are re-applied.
    static func bobblyEmergency(_ id: UUID = UUID()) -> DeviceActivityName {
        DeviceActivityName(bobblyEmergencyPrefix + id.uuidString)
    }

    /// Trigger: STARTS when a timed study session finishes -> study shields removed.
    static func bobblyStudy(_ id: UUID = UUID()) -> DeviceActivityName {
        DeviceActivityName(bobblyStudyPrefix + id.uuidString)
    }

    var isBobblyEmergencyTrigger: Bool { rawValue.hasPrefix(DeviceActivityName.bobblyEmergencyPrefix) }
    var isBobblyStudyTrigger: Bool { rawValue.hasPrefix(DeviceActivityName.bobblyStudyPrefix) }

    /// Trigger per chat-granted unlock: STARTS at expiry and re-locks that app.
    static func bobblyUnlock(_ grantID: UUID) -> DeviceActivityName {
        DeviceActivityName(bobblyUnlockPrefix + grantID.uuidString)
    }

    /// The grant id if this is an unlock activity.
    var bobblyUnlockGrantID: UUID? {
        guard rawValue.hasPrefix(DeviceActivityName.bobblyUnlockPrefix) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(DeviceActivityName.bobblyUnlockPrefix.count)))
    }

    var isBobblyActivity: Bool { rawValue.hasPrefix("com.bobbly.activity.") }
}

enum ActivitySchedules {
    /// DeviceActivity refuses intervals shorter than 15 minutes.
    static let minimumInterval: TimeInterval = 15 * 60

    /// Length of a trigger interval (must be ≥ 15 min; +1 min of slack).
    static let triggerLength: TimeInterval = minimumInterval + 60

    /// Components used for one-off schedules. Developer-forum reports show that
    /// mixing date (year/month/day) and time components makes callbacks silently
    /// never fire, while time-only components (hour/minute/second) on BOTH ends
    /// work; `nextInterval` resolves them to the next matching occurrence.
    static let timeUnits: Set<Calendar.Component> = [.hour, .minute, .second]

    /// A non-repeating schedule whose interval STARTS at `date`.
    ///
    /// Unlocks are often 5–15 minutes, below DeviceActivity's 15-minute minimum,
    /// so instead of waiting for `intervalDidEnd` we schedule an interval that
    /// begins at the moment something must happen (re-lock, emergency over,
    /// study over). The monitor acts in `intervalDidStart` (and again,
    /// harmlessly, in `intervalDidEnd`). `date` must be in the future.
    static func trigger(at date: Date, calendar: Calendar = .current) -> DeviceActivitySchedule {
        let (start, end) = triggerComponents(at: date, calendar: calendar)
        return DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false)
    }

    /// Pure helper (unit-tested): time-only start/end components for `trigger(at:)`.
    static func triggerComponents(at date: Date, calendar: Calendar = .current) -> (start: DateComponents, end: DateComponents) {
        (calendar.dateComponents(timeUnits, from: date),
         calendar.dateComponents(timeUnits, from: date.addingTimeInterval(triggerLength)))
    }

    /// Triggers closer than this are pushed out (schedules starting "now" can be missed).
    static let minimumLeadTime: TimeInterval = 5

    /// The trigger date actually used for an event at `date` (never sooner than now + lead).
    static func triggerDate(for date: Date, now: Date) -> Date {
        max(date, now.addingTimeInterval(minimumLeadTime))
    }

    /// 00:00 – 23:59 every day.
    static var daily: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
    }
}
