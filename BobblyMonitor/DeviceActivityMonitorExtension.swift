//  DeviceActivityMonitorExtension.swift
//  BobblyMonitor — principal class (see Info.plist).
//
//  Bobbly's timers are one-shot "trigger" activities whose interval STARTS
//  when an unlock / emergency / study session ends (see
//  `ActivitySchedules.trigger(at:)`). On start we finish that state and
//  re-derive shields with the SAME `ShieldPolicy.reconcile` the app uses, so
//  re-locking can't drift. `intervalDidEnd` repeats the reconcile (harmless)
//  and unregisters the trigger.

import Foundation
import DeviceActivity
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let shared = SharedStore.shared

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity.isBobblyActivity else { return }
        handleTrigger(activity, phase: "start")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity.isBobblyActivity else { return }
        handleTrigger(activity, phase: "end")
        if activity != .bobblyDaily {
            DeviceActivityCenter().stopMonitoring([activity])
        }
    }

    private func handleTrigger(_ activity: DeviceActivityName, phase: String) {
        // If the signer dropped/renamed the App Group this process sees an
        // empty private store; acting on it could unshield everything.
        guard AppGroup.isContainerAvailable else { return }
        let now = Date()
        let outcome = MonitorLogic.handle(activity, shared: shared, now: now)
        switch outcome {
        case .unlocksEnded(let grants):
            if let first = grants.first {
                let name = grants.count == 1 ? first.displayName : "\(grants.count) apps"
                BobblyNotifications.postUnlockEnded(grantID: first.id, appName: name)
            }
        case .emergencyEnded:
            BobblyNotifications.postEmergencyEnded()
        case .studyEnded(let name):
            BobblyNotifications.postStudyEnded(whitelistName: name)
        case .none:
            break
        }
        let summary = ShieldPolicy.reconcile(shared: shared, now: now, requireAppGroup: true)
        shared.appendLog("monitor \(phase) \(activity.rawValue.replacingOccurrences(of: "com.bobbly.activity.", with: "")): \(outcome.logDescription); \(summary)")
    }
}
