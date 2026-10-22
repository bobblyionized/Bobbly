//  BobblyApp.swift
//  Bobbly/App — entry point: builds the environment, wires deep links,
//  notification taps and scene-phase refreshes.

import SwiftUI
import SwiftData

@main
@MainActor
struct BobblyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .modelContainer(env.container)
                .onOpenURL { url in
                    env.handle(url: url)
                }
                .task {
                    let environment = env
                    appDelegate.urlHandler = { url in environment.handle(url: url) }
                    await environment.launch()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await env.sceneDidBecomeActive() }
                }
        }
    }
}
