import XCTest
@testable import Bobbly

final class MiscLogicTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func status(kind: EngineKind = .familyControls, detached: Bool = false, emergency: Date? = nil,
                        unlocks: [ActiveUnlock] = [], study: StudySnapshot? = nil, apps: Int = 0) -> EngineStatus {
        EngineStatus(kind: kind, isReady: true, isDetached: detached, emergencyUntil: emergency, activeUnlocks: unlocks,
                     study: study, blockedAppCount: apps, blockedCategoryCount: 0, blockedWebDomainCount: 0)
    }

    // MARK: Home protection state precedence

    @MainActor
    func testProtectionStatePrecedence() {
        let unlock = ActiveUnlock(id: UUID(), subject: .appName("X"), displayName: "X", grantedAt: now, expiresAt: now.addingTimeInterval(60))
        let study = StudySnapshot(ActiveStudy(sessionID: UUID(), whitelistID: UUID(), whitelistName: "S", selectionData: nil,
                                              allowedAppKeys: [], startedAt: now, endsAt: nil))

        XCTAssertEqual(HomeViewModel.protectionState(status: status(apps: 2), engineState: .undetermined, now: now), .setupNeeded)
        XCTAssertEqual(HomeViewModel.protectionState(status: status(apps: 0), engineState: .familyControls, now: now), .setupNeeded)
        XCTAssertEqual(HomeViewModel.protectionState(status: status(apps: 2), engineState: .familyControls, now: now), .protecting(blockedCount: 2))
        XCTAssertEqual(HomeViewModel.protectionState(status: status(unlocks: [unlock], apps: 2), engineState: .familyControls, now: now),
                       .unlocked(appName: "X", until: unlock.expiresAt))
        XCTAssertEqual(HomeViewModel.protectionState(status: status(unlocks: [unlock], study: study, apps: 2), engineState: .familyControls, now: now),
                       .studying(name: "S", until: nil))
        XCTAssertEqual(HomeViewModel.protectionState(status: status(emergency: now.addingTimeInterval(60), study: study, apps: 2),
                                                     engineState: .familyControls, now: now),
                       .emergency(until: now.addingTimeInterval(60)))
        XCTAssertEqual(HomeViewModel.protectionState(status: status(detached: true, apps: 2), engineState: .familyControls, now: now), .detached)
    }

    // MARK: Catalog

    func testCatalogSearchAndLookup() {
        XCTAssertEqual(AppCatalog.app(named: " instagram ")?.urlScheme, "instagram")
        XCTAssertTrue(AppCatalog.search("tik").contains { $0.name == "TikTok" })
        XCTAssertEqual(AppCatalog.search("").count, AppCatalog.popular.count)
        XCTAssertEqual(Set(AppCatalog.popular.map(\.id)).count, AppCatalog.popular.count, "catalog ids must be unique")
    }

    func testAutomationStepsMentionAppAndGateLink() {
        let steps = AppCatalog.automationSteps(for: "Pinterest")
        XCTAssertTrue(steps.contains { $0.contains("bobbly://gate?app=Pinterest") })
        XCTAssertTrue(steps.contains { $0.contains("Is Closed") })
        XCTAssertTrue(steps.contains { $0.contains("Check Access") })
    }

    // MARK: Study durations

    func testStudyDurations() {
        XCTAssertEqual(StudyDuration.minutes(90).minutes, 90)
        XCTAssertNil(StudyDuration.untilStopped.minutes)
        XCTAssertEqual(StudyDuration.minutes(120).title, "2 h")
        XCTAssertEqual(StudyDuration.minutes(25).title, "25 min")
        XCTAssertEqual(Set(StudyDuration.options.map(\.id)).count, StudyDuration.options.count)
    }

    func testActiveStudySessionProgress() {
        let session = ActiveStudySession(sessionID: UUID(), whitelistName: "S", startedAt: now, endsAt: now.addingTimeInterval(600))
        XCTAssertEqual(session.progress(at: now.addingTimeInterval(300)) ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(session.remaining(at: now.addingTimeInterval(700)), 0)
        let open = ActiveStudySession(sessionID: UUID(), whitelistName: "S", startedAt: now, endsAt: nil)
        XCTAssertNil(open.progress(at: now))
        XCTAssertNil(open.remaining(at: now))
    }

    // MARK: Chat cooldown value type

    func testChatCooldownMath() {
        let cooldown = ChatCooldown(startedAt: now, endsAt: now.addingTimeInterval(40))
        XCTAssertEqual(cooldown.totalSeconds, 40)
        XCTAssertEqual(cooldown.remainingSeconds(at: now.addingTimeInterval(10.2)), 30)
        XCTAssertEqual(cooldown.progress(at: now.addingTimeInterval(20)), 0.5, accuracy: 0.001)
        XCTAssertEqual(cooldown.remainingSeconds(at: now.addingTimeInterval(99)), 0)
    }

    // MARK: Companion lines

    func testEveryMoodTierHasLines() {
        for tier in CompanionMood.allCases {
            XCTAssertFalse(CompanionLines.line(for: tier, seed: 0).isEmpty)
            XCTAssertFalse(CompanionLines.line(for: tier, seed: -7).isEmpty)
        }
    }

    @MainActor
    func testCompanionSnapshotFromValues() {
        var values = CompanionValues.fresh(day: Calendar.current.startOfDay(for: now))
        values.lives = 0
        let snapshot = CompanionService.makeSnapshot(values, now: now)
        XCTAssertEqual(snapshot.tier, .exhausted)
        XCTAssertEqual(snapshot.maxLives, CompanionRules.maxLives)
        XCTAssertGreaterThan(snapshot.resetsAt, now)
    }
}
