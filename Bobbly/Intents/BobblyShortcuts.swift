//  BobblyShortcuts.swift
//  Bobbly/Intents — Siri phrases. `CheckAccessIntent` and `LogAppEventIntent`
//  need no phrases: they appear as actions in the Shortcuts app automatically.

import AppIntents

struct BobblyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EmergencyUnblockIntent(),
            phrases: [
                "\(.applicationName) emergency",
                "Emergency unblock with \(.applicationName)",
            ],
            shortTitle: "Emergency Unblock",
            systemImageName: "exclamationmark.octagon"
        )
        AppShortcut(
            intent: DetachBobblyIntent(),
            phrases: [
                "Detach \(.applicationName)",
                "Turn off \(.applicationName)",
            ],
            shortTitle: "Detach Bobbly",
            systemImageName: "power"
        )
    }
}
