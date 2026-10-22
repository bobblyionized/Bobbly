//  RootView.swift
//  Bobbly/App — root tabs plus the sheet/cover routing (owned by UI).
//  Wiring kept from phase 1: tab selection, `router.sheet`, `router.cover`
//  and which ViewModel each route gets (see CONTRACT.md › Routing).

import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var router = env.router

        TabView(selection: $router.selectedTab) {
            HomeView(model: env.home)
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
                .tag(AppTab.home)
            ChatView(model: env.chat)
                .tabItem { Label(AppTab.chat.title, systemImage: AppTab.chat.systemImage) }
                .tag(AppTab.chat)
            StudyView(model: env.study)
                .tabItem { Label(AppTab.study.title, systemImage: AppTab.study.systemImage) }
                .tag(AppTab.study)
            StatsView(model: env.stats)
                .tabItem { Label(AppTab.stats.title, systemImage: AppTab.stats.systemImage) }
                .tag(AppTab.stats)
            SettingsView(model: env.settings)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
        .tint(Theme.Palette.pond)
        .bobblyHaptic(.selection, trigger: router.selectedTab)
        .sheet(item: $router.sheet) { route in
            sheetContent(route)
                .tint(Theme.Palette.pond)
        }
        .fullScreenCover(item: $router.cover) { route in
            coverContent(route)
                .tint(Theme.Palette.pond)
        }
    }

    @ViewBuilder
    private func sheetContent(_ route: SheetRoute) -> some View {
        switch route {
        case .emergency:
            EmergencyView(model: env.makeEmergencyViewModel())
        case .search:
            SearchView(model: env.makeSearchViewModel())
        case .blockedApps:
            BlockedAppsView(model: env.makeBlockedAppsViewModel())
        case .companion:
            CompanionView(model: env.makeCompanionViewModel())
        case .whitelistEditor(let whitelistID):
            WhitelistEditorView(model: env.study, whitelistID: whitelistID)
        }
    }

    @ViewBuilder
    private func coverContent(_ route: CoverRoute) -> some View {
        switch route {
        case .gate(let target):
            GateView(model: env.makeGateViewModel(target: target))
        case .tutorial:
            PermissionsTutorialView(model: env.makeTutorialViewModel())
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.preview())
}
