import XCTest
@testable import Bobbly

final class ChatEngineTests: XCTestCase {

    private func makeEngine(unlocksToday: Int = 0, free: Int = 3, lives: Int = 3) -> ChatEngine {
        ChatEngine(context: ChatContext(unlocksToday: unlocksToday, dailyFreeUnlocks: free, livesRemaining: lives), seed: 42)
    }

    // MARK: Classification

    func testClassifiesLegitimateReasons() {
        XCTAssertEqual(ChatEngine.classify("I need to reply to my mom"), .communication)
        XCTAssertEqual(ChatEngine.classify("homework due tomorrow"), .school)
        XCTAssertEqual(ChatEngine.classify("Work email from my boss"), .work)
    }

    func testClassifiesBoredomHabitEmergencyAndUnclear() {
        XCTAssertEqual(ChatEngine.classify("I'm bored"), .boredom)
        XCTAssertEqual(ChatEngine.classify("just habit honestly"), .habit)
        XCTAssertEqual(ChatEngine.classify("idk"), .habit)
        XCTAssertEqual(ChatEngine.classify("There's an EMERGENCY!"), .emergency)
        XCTAssertEqual(ChatEngine.classify("asdf qwerty"), .unclear)
        XCTAssertEqual(ChatEngine.classify("   "), .unclear)
    }

    func testBoredomOutweighsSingleLegitWord() {
        XCTAssertEqual(ChatEngine.classify("bored at work"), .boredom)
    }

    // MARK: Strictness

    func testGrantMinutesShrinkWithEachUnlock() {
        XCTAssertEqual(ChatEngine.grantMinutes(for: .work, unlocksToday: 0), 15)
        XCTAssertEqual(ChatEngine.grantMinutes(for: .work, unlocksToday: 1), 10)
        XCTAssertEqual(ChatEngine.grantMinutes(for: .work, unlocksToday: 2), 5)
        XCTAssertEqual(ChatEngine.grantMinutes(for: .work, unlocksToday: 9), 5)
        XCTAssertEqual(ChatEngine.grantMinutes(for: .boredom, unlocksToday: 0), 7)
        XCTAssertEqual(ChatEngine.grantMinutes(for: .boredom, unlocksToday: 5), 3)
        XCTAssertEqual(ChatEngine.grantMinutes(for: .emergency, unlocksToday: 5), 15)
    }

    func testCooldownGrowsAndCaps() {
        XCTAssertEqual(ChatEngine.cooldownSeconds(unlocksToday: 0), 30)
        XCTAssertEqual(ChatEngine.cooldownSeconds(unlocksToday: 2), 50)
        XCTAssertEqual(ChatEngine.cooldownSeconds(unlocksToday: 10), 60)
    }

    // MARK: Flows

    func testStartWithoutTargetAsksForApp() {
        var engine = makeEngine()
        let turn = engine.start(subjectName: nil, knownApps: ["Instagram", "TikTok"])
        XCTAssertEqual(engine.phase, .askingApp)
        XCTAssertEqual(turn.quickReplies.map(\.title), ["Instagram", "TikTok"])
        let next = engine.respond(to: .text("Instagram"))
        XCTAssertEqual(engine.phase, .askingReason)
        XCTAssertEqual(engine.subjectName, "Instagram")
        XCTAssertFalse(next.quickReplies.isEmpty)
    }

    func testLegitimateReasonGrantsImmediately() {
        var engine = makeEngine()
        _ = engine.start(subjectName: "Instagram")
        let turn = engine.respond(to: .text("need to message my friend"))
        XCTAssertEqual(turn.decision, .grant(minutes: 15))
        XCTAssertEqual(engine.phase, .finished)
        XCTAssertEqual(engine.category, .communication)
    }

    func testSecondUnlockIsShorterAndWarnsPastFreeAllowance() {
        var engine = makeEngine(unlocksToday: 3, free: 3)
        _ = engine.start(subjectName: "Instagram")
        let turn = engine.respond(to: .quickReply(QuickReply("Work", kind: .reason(.work))))
        XCTAssertEqual(turn.decision, .grant(minutes: 5))
        XCTAssertTrue(turn.lines.contains { $0.style == .warning })
    }

    func testBoredomPushbackThenGiveUpDeclines() {
        var engine = makeEngine()
        _ = engine.start(subjectName: "TikTok")
        let pushback = engine.respond(to: .text("I'm bored"))
        XCTAssertEqual(engine.phase, .pushback)
        XCTAssertNil(pushback.decision)
        let giveUp = pushback.quickReplies.first { $0.kind == .giveUp }!
        let turn = engine.respond(to: .quickReply(giveUp))
        XCTAssertEqual(turn.decision, .declined)
    }

    func testCommitmentSentenceUnlocks() {
        var engine = makeEngine()
        _ = engine.start(subjectName: "TikTok")
        let pushback = engine.respond(to: .text("bored"))
        let anyway = pushback.quickReplies.first { $0.kind == .unlockAnyway }!
        let commitment = engine.respond(to: .quickReply(anyway))
        let phrase = try! XCTUnwrap(commitment.commitmentPhrase)
        XCTAssertEqual(engine.phase, .awaitingCommitment)

        let wrong = engine.respond(to: .text("let me in"))
        XCTAssertNil(wrong.decision)

        let typed = phrase.uppercased() + "!!"
        let turn = engine.respond(to: .text(typed))
        XCTAssertEqual(turn.decision, .grant(minutes: 7))
    }

    func testCooldownUnlocksOnlyAfterElapsed() {
        var engine = makeEngine(unlocksToday: 1)
        _ = engine.start(subjectName: "YouTube")
        let pushback = engine.respond(to: .text("just habit"))
        let anyway = pushback.quickReplies.first { $0.kind == .unlockAnyway }!
        _ = engine.respond(to: .quickReply(anyway))
        let start = Date(timeIntervalSince1970: 1_000_000)
        let cooling = engine.respond(to: .quickReply(QuickReply("wait", kind: .waitCooldown)), now: start)
        XCTAssertEqual(cooling.cooldown?.totalSeconds, 40)

        let early = engine.respond(to: .cooldownElapsed, now: start.addingTimeInterval(10))
        XCTAssertNil(early.decision)

        let done = engine.respond(to: .cooldownElapsed, now: start.addingTimeInterval(41))
        XCTAssertEqual(done.decision, .grant(minutes: 5))
    }

    func testUnclearAsksOnceThenPushesBack() {
        var engine = makeEngine()
        _ = engine.start(subjectName: "Reddit")
        let clarify = engine.respond(to: .text("hmm"))
        XCTAssertEqual(engine.phase, .askingReason)
        XCTAssertNil(clarify.decision)
        _ = engine.respond(to: .text("zzz"))
        XCTAssertEqual(engine.phase, .pushback)
    }

    func testEmergencyGrantsAndOffersEmergencyScreen() {
        var engine = makeEngine(unlocksToday: 4)
        _ = engine.start(subjectName: "WhatsApp")
        let turn = engine.respond(to: .text("urgent emergency"))
        XCTAssertEqual(turn.decision, .grant(minutes: 15))
        XCTAssertTrue(turn.quickReplies.contains { $0.kind == .openEmergency })
        let next = engine.respond(to: .quickReply(turn.quickReplies[0]))
        XCTAssertEqual(next.decision, .emergency)
    }

    func testStudySessionEndUsesEndStudyDecision() {
        var engine = makeEngine()
        _ = engine.start(subjectName: "Study", isStudySession: true)
        let turn = engine.respond(to: .text("my teacher needs me to submit the assignment"))
        XCTAssertEqual(turn.decision, .endStudy)
    }

    func testPhrasesNeverLeakPlaceholders() {
        for seed in UInt64(0)..<40 {
            var engine = ChatEngine(context: .relaxed, seed: seed)
            var lines = engine.start(subjectName: "Instagram").lines
            lines += engine.respond(to: .text("bored")).lines
            lines += engine.respond(to: .quickReply(QuickReply("x", kind: .unlockAnyway))).lines
            for line in lines {
                XCTAssertFalse(line.text.contains("{"), "Unfilled placeholder in: \(line.text)")
            }
        }
    }

    func testOverDailyLimitHalvesGrantAndWarns() {
        var context = ChatContext(unlocksToday: 0, dailyFreeUnlocks: 3, livesRemaining: 3)
        context.appUsageTodayMinutes = 42
        context.appDailyLimitMinutes = 30
        XCTAssertTrue(context.isOverDailyLimit)
        var engine = ChatEngine(context: context, seed: 7)
        _ = engine.start(subjectName: "Instagram")
        let turn = engine.respond(to: .text("need to reply to my mom"))
        XCTAssertEqual(turn.decision, .grant(minutes: ChatEngine.overLimitMinutes(15)))
        XCTAssertEqual(ChatEngine.overLimitMinutes(15), 7)
        let warnings = turn.lines.filter { $0.style == .warning }.map(\.text)
        XCTAssertTrue(warnings.contains { $0.contains("42") && $0.contains("30") })
        XCTAssertFalse(turn.lines.contains { $0.text.contains("{") })
    }

    func testUnderLimitIsNotStricter() {
        var context = ChatContext.relaxed
        context.appUsageTodayMinutes = 10
        context.appDailyLimitMinutes = 30
        XCTAssertFalse(context.isOverDailyLimit)
        context.appDailyLimitMinutes = 0
        context.appUsageTodayMinutes = 999
        XCTAssertFalse(context.isOverDailyLimit)
    }

    func testEmergencyIgnoresDailyLimit() {
        var context = ChatContext.relaxed
        context.appUsageTodayMinutes = 100
        context.appDailyLimitMinutes = 10
        var engine = ChatEngine(context: context, seed: 3)
        _ = engine.start(subjectName: "WhatsApp")
        XCTAssertEqual(engine.respond(to: .text("emergency")).decision, .grant(minutes: 15))
    }

    func testOutOfLivesStillAllowsButWarns() {
        var engine = makeEngine(unlocksToday: 5, free: 3, lives: 0)
        _ = engine.start(subjectName: "X")
        let turn = engine.respond(to: .text("work deadline"))
        XCTAssertEqual(turn.decision, .grant(minutes: 5))
        XCTAssertTrue(turn.lines.contains { $0.style == .warning })
    }

    func testStartOverRestartsConversation() {
        var engine = makeEngine()
        _ = engine.start(subjectName: nil, knownApps: ["Reddit"])
        _ = engine.respond(to: .text("Reddit"))
        let pushback = engine.respond(to: .text("bored"))
        _ = engine.respond(to: .quickReply(pushback.quickReplies.first { $0.kind == .giveUp }!))
        XCTAssertEqual(engine.phase, .finished)
        _ = engine.respond(to: .quickReply(QuickReply("Start over", kind: .startOver)))
        XCTAssertEqual(engine.phase, .askingApp)
        XCTAssertEqual(engine.reasonText, "")
    }

    func testFinishedConversationIgnoresInput() {
        var engine = makeEngine()
        _ = engine.start(subjectName: "X")
        _ = engine.respond(to: .text("homework"))
        XCTAssertEqual(engine.respond(to: .text("more")), ChatTurn.none)
    }

    func testCommitmentMatchingIgnoresCaseAndPunctuation() {
        XCTAssertTrue(ChatEngine.matchesCommitment("i choose to open tiktok, even though I'm bored.", phrase: "I choose to open TikTok even though I'm bored"))
        XCTAssertFalse(ChatEngine.matchesCommitment("", phrase: "anything"))
        XCTAssertFalse(ChatEngine.matchesCommitment("I choose", phrase: "I choose to open TikTok"))
    }
}
