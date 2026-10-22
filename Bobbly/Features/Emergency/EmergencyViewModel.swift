//  EmergencyViewModel.swift
//  Bobbly/Features/Emergency — always-free emergency unblock and emergency
//  detach, both behind a 10-second hold-to-confirm.

import Foundation
import Observation

/// The two hold-to-confirm buttons.
enum EmergencyAction: String, Identifiable, CaseIterable {
    /// Unblock everything for `selectedMinutes`.
    case unblock
    /// Remove all shields/monitoring, revoke Screen Time access, turn Bobbly off.
    case detach

    var id: String { rawValue }
}

enum DetachPhase: Equatable {
    case idle
    case working
    case finished(DetachReport)
}

@Observable
@MainActor
final class EmergencyViewModel {
    unowned let env: AppEnvironment

    /// Minutes offered for the emergency unblock.
    let durationOptions: [Int] = [15, 30, 60, 120, 240]
    var selectedMinutes: Int
    /// Seconds the user must hold a button.
    let holdDuration: TimeInterval = 10

    /// Which button is being held (nil = none).
    private(set) var holdingAction: EmergencyAction?
    /// 0...1 progress of the current hold (drive a ring/fill).
    private(set) var holdProgress: Double = 0
    private(set) var detachPhase: DetachPhase = .idle
    /// User-facing error from the last action.
    private(set) var errorMessage: String?
    /// Shown after a successful unblock, e.g. "Everything is unblocked until 3:45 PM."
    private(set) var confirmation: String?

    /// Siri phrases that work even if the UI is broken.
    let siriPhrases = ["\"Hey Siri, Bobbly emergency\"", "\"Hey Siri, detach Bobbly\""]
    /// Deep link that opens this screen.
    let deepLink = "bobbly://emergency"

    @ObservationIgnored private var holdTask: Task<Void, Never>?

    init(env: AppEnvironment) {
        self.env = env
        let preferred = env.preferences.defaultEmergencyMinutes
        self.selectedMinutes = [15, 30, 60, 120, 240].contains(preferred) ? preferred : 30
    }

    // MARK: Derived

    var engineKind: EngineKind { env.engines.status.kind }
    var emergencyUntil: Date? { env.engines.status.emergencyUntil }
    var isEmergencyActive: Bool { env.engines.status.isEmergencyActive() }
    var isDetached: Bool { env.engines.status.isDetached || env.engines.state == .detached }

    /// What detach will do for the running engine (shown before holding).
    var detachExplanation: [String] {
        switch engineKind {
        case .familyControls:
            return [
                "Removes every Bobbly shield right away.",
                "Stops all Bobbly schedules and timers.",
                "Revokes Bobbly's Screen Time access (it disappears from Settings › Screen Time).",
            ]
        case .shortcuts:
            return [
                "Turns Bobbly off: every Shortcuts check lets apps open.",
                "Ends any study session or unlock timers.",
                "Shows how to delete the Shortcuts automations.",
            ]
        }
    }

    // MARK: Actions

    func onAppear() {
        errorMessage = nil
        env.engines.refresh()
    }

    /// Finger down on a hold button. Fires the action after `holdDuration`.
    func beginHold(_ action: EmergencyAction) {
        guard holdingAction == nil else { return }
        holdingAction = action
        holdProgress = 0
        errorMessage = nil
        let start = Date()
        holdTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                let progress = min(1, Date().timeIntervalSince(start) / self.holdDuration)
                self.holdProgress = progress
                if progress >= 1 {
                    self.holdingAction = nil
                    await self.complete(action)
                    return
                }
            }
        }
    }

    /// Finger lifted early: cancels the hold.
    func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        holdingAction = nil
        holdProgress = 0
    }

    /// Ends a running emergency unblock now (blocks come back).
    func endEmergencyNow() {
        env.engines.endEmergency()
        confirmation = nil
        env.refreshAll()
    }

    /// Turns Bobbly back on after a detach (may show the Screen Time prompt again).
    func reattach() async {
        await env.engines.reattach()
        detachPhase = .idle
        env.refreshAll()
    }

    // MARK: Private

    private func complete(_ action: EmergencyAction) async {
        holdProgress = 0
        switch action {
        case .unblock: performUnblock()
        case .detach: await performDetach()
        }
    }

    private func performUnblock() {
        do {
            try env.engines.emergencyUnblockAll(minutes: selectedMinutes)
            env.companion.refresh()
            env.tracker.logUnlock(appName: "Everything", appKey: nil, reason: "Emergency unblock",
                                  category: ReasonCategory.emergency.rawValue, minutes: selectedMinutes,
                                  granted: true, isEmergency: true)
            let until = Date().addingTimeInterval(TimeInterval(selectedMinutes * 60))
            confirmation = "Everything is unblocked until \(until.formatted(date: .omitted, time: .shortened))."
        } catch {
            errorMessage = error.localizedDescription
        }
        env.refreshAll()
    }

    private func performDetach() async {
        detachPhase = .working
        let report = await env.engines.detach()
        detachPhase = .finished(report)
        if let firstError = report.errors.first { errorMessage = firstError }
        env.refreshAll()
    }
}
