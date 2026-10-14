import XCTest
@testable import MPMCore

/// The walkthrough of the addendum (§13), on the engine: the arithmetic, the handshake and the
/// freeze. Defaults: R 10 min, r 3, so q = 1:15 and reminders at 5:00, 2:30 and 1:15 left.
final class SessionTests: XCTestCase {
    var s: Session!
    var said: [String] = []
    var sounds: [SoundKind] = []

    override func setUp() {
        s = Session(cfg: .default, now: Date(timeIntervalSince1970: 1_700_000_000))
        said = []
        sounds = []
        s.onSay = { [unowned self] t, _ in self.said.append(t) }
        s.onSound = { [unowned self] k in self.sounds.append(k) }
        s.onSavePlan = { _ in true }
        s.names.b = "Sam"
        s.intake = Session.Intake(stage: .time, ids: [])
    }

    func testArithmetic() {
        let c = SessionConfig.default
        XCTAssertEqual(c.q, 75)
        XCTAssertEqual(c.zMax, 3)
        XCTAssertEqual(c.remTimes, [300, 150, 75])
        XCTAssertEqual(c.awayFor(z: 0, x: 0), 150)
        XCTAssertEqual(c.awayFor(z: 1, x: 2), 100)
        XCTAssertEqual(c.awayFor(z: 3, x: 0), 1200)
        XCTAssertEqual(Format.fmt(75), "1:15")
        XCTAssertEqual(Format.fmt(600), "10 min")
        XCTAssertEqual(Format.fmt(50), "50 s")
        XCTAssertEqual(Format.digits(372), "6:12")
    }

    /// Types two steps at the intake and opens the session: round 1 runs after B's Go.
    private func openWithTwoSteps() {
        XCTAssertNil(s.intakeSubmit("10"))
        XCTAssertEqual(s.intake.stage, .ask)
        XCTAssertNil(s.intakeSubmit("Fix the login bug"))
        XCTAssertNil(s.intakeSubmit("Write onboarding copy"))
        XCTAssertEqual(s.intake.stage, .ready)
        XCTAssertEqual(s.bView(), .ready)
        s.okReady()
        XCTAssertEqual(s.state, .idle)
        let r = s.openReq!
        XCTAssertEqual(r.to, .work)
        XCTAssertEqual(r.verdict, .approved)         // policy answers at once
        XCTAssertEqual(r.decidedBy, .policy)
        s.accept(r.id)
    }

    func testIntakeAndFirstRound() {
        openWithTwoSteps()
        XCTAssertEqual(s.state, .work)
        XCTAssertEqual(s.round, 1)
        XCTAssertEqual(s.title(s.slot(.doing)), "Fix the login bug")
        XCTAssertEqual(s.title(s.slot(.next)), "Write onboarding copy")
        XCTAssertEqual(s.left(), 600, accuracy: 0.01)
        XCTAssertEqual(sounds, [.start])
        XCTAssertTrue(said.last!.hasPrefix("Round 1"))
    }

    func testRemindersThenTimeUpFreezes() {
        openWithTwoSteps()
        s.advance(real: 300)
        XCTAssertNotNil(s.strip)                      // 5:00 left: a strip
        XCTAssertNil(s.lastRem)
        s.advance(real: 150)
        s.advance(real: 75)
        XCTAssertEqual(s.lastRem, 75)                 // the last reminder covers the screen
        XCTAssertEqual(s.coverModel()?.kind, .reminder)
        s.advance(real: 75)
        XCTAssertTrue(s.frozen)
        XCTAssertEqual(s.reading, 600)
        XCTAssertEqual(s.left(), 0)
        let ended = s.endedScreen()!
        XCTAssertEqual(ended.heading, "Time's up.")
        XCTAssertEqual(ended.buttons.count, 2)         // Go, and Snooze with 3 left
        XCTAssertTrue(ended.buttons[1].label.contains("3 left"))
        XCTAssertTrue(sounds.contains(.timeup))
        // Frozen: nothing moves, the plan is closed, the sitting clock runs.
        let seated = s.seated
        s.advance(real: 100)
        XCTAssertTrue(s.frozen)
        XCTAssertEqual(s.seated, seated + 100, accuracy: 0.01)
        XCTAssertNotNil(s.editBlock())
    }

    func testSnoozeDoublesTheCheckup() {
        openWithTwoSteps()
        s.advance(real: 600)
        s.raise(.snooze)
        let r = s.openReq!
        XCTAssertEqual(r.verdict, .approved)
        s.accept(r.id)
        XCTAssertEqual(s.state, .snooze)
        XCTAssertEqual(s.z, 1)
        XCTAssertEqual(s.left(), 75, accuracy: 0.01)
        s.advance(real: 75)
        XCTAssertTrue(s.frozen)
        s.accept(s.sys!.id)
        XCTAssertEqual(s.state, .status)
        XCTAssertEqual(s.statusLen, 300)              // 1:15 × 2^2 ÷ 1
        XCTAssertEqual(s.roundRun, 675, accuracy: 0.01)
    }

    /// Round 2 of the walkthrough: two steps cleared, early move at 8:05 → check-up 0:50.
    func testEarlyMoveWithTwoCleared() {
        openWithTwoSteps()
        let repro = s.addChild(s.slot(.doing), "Repro on Safari")!
        s.advance(real: 400)
        s.markDone(repro)
        s.advance(real: 40)
        s.nextPhase()                                 // a request to start check-up
        let r = s.openReq!
        XCTAssertEqual(r.to, .status)
        XCTAssertEqual(r.verdict, .approved)
        XCTAssertFalse(s.frozen)                      // the clock keeps running
        s.advance(real: 30)
        s.markDone(s.slot(.doing)!)                   // Doing done: Next is promoted
        XCTAssertEqual(s.title(s.slot(.doing)), "Write onboarding copy")
        XCTAssertTrue(said.contains { $0.contains("Now doing Write onboarding copy") || $0.contains("Write onboarding copy") })
        s.advance(real: 15)
        s.accept(r.id)                                // Go at 8:05
        XCTAssertEqual(s.state, .status)
        XCTAssertEqual(s.x, 2)
        XCTAssertEqual(s.statusLen, 50, accuracy: 0.01)
        XCTAssertEqual(s.roundRun, 485, accuracy: 0.01)
        // Policy refuses an early move out of check-up.
        s.raise(.strategy)
        let early = s.openReq!
        XCTAssertEqual(early.verdict, .refused)
        XCTAssertTrue(early.reason.hasPrefix("Check-up has"))
        s.ack(early.id)
        XCTAssertNil(s.openReq)
        // The check-up ends: frozen, the System asks to start planning.
        s.advance(real: 50)
        XCTAssertTrue(s.frozen)
        XCTAssertEqual(s.sys?.to, .strategy)
        s.advance(real: 165)                          // a freeze of 2:45
        s.accept(s.sys!.id)
        XCTAssertEqual(s.state, .strategy)
        XCTAssertEqual(s.left(), 75, accuracy: 0.01)
        XCTAssertEqual(s.diff.count, 3)                // Fix done, Write promoted, Repro new → done
        XCTAssertNotNil(s.held?.say)                  // the assistant answered during the check-up
        XCTAssertNotNil(s.held?.brief)
    }

    func testPlanEndsWithAutoCommitAndSitCheck() {
        s.seatStart = 38 * 60
        openWithTwoSteps()
        s.advance(real: 600)
        s.accept(s.sys!.id)                           // check-up, 2:30 (nothing cleared)
        XCTAssertEqual(s.statusLen, 150)
        s.advance(real: 150)
        s.accept(s.sys!.id)                           // plan
        XCTAssertEqual(s.state, .strategy)
        s.advance(real: 75)                           // plan over: auto-commit keeps the pair
        XCTAssertTrue(s.frozen)
        XCTAssertFalse(s.planChosen)
        // seated 38 + 10 + freeze… > 45 min: a break first.
        XCTAssertEqual(s.sys?.to, .break)
        let m = s.endedScreen()!
        XCTAssertEqual(m.question, "Start your movement break?")
        s.accept(s.sys!.id)
        XCTAssertEqual(s.state, .break)
        s.advance(real: 180)
        XCTAssertTrue(s.frozen)
        XCTAssertEqual(s.seated, 0)
        XCTAssertEqual(s.sys?.to, .work)
        s.accept(s.sys!.id)
        XCTAssertEqual(s.round, 2)
        XCTAssertEqual(s.state, .work)
    }

    func testHumanAWaitsAndMayRefuse() {
        openWithTwoSteps()
        s.setAuto(false)
        s.advance(real: 100)
        s.nextPhase()
        let r = s.openReq!
        XCTAssertNil(r.verdict)
        XCTAssertEqual(s.stripModel()?.kind, .waiting)
        s.decide(r.id, .refused, "Not yet, finish the bug.", by: .a)
        let d = s.openReq!
        XCTAssertEqual(d.verdict, .refused)
        XCTAssertEqual(d.reason, "Not yet, finish the bug.")
        XCTAssertEqual(s.stripModel()?.kind, .refused)
        s.ack(d.id)
        XCTAssertEqual(s.state, .work)
        // The clock ending overtakes a waiting request.
        s.nextPhase()
        let w = s.openReq!
        s.advance(real: 500)
        XCTAssertEqual(s.request(w.id)?.outcome, .overtaken)
        XCTAssertTrue(s.frozen)
    }

    func testEndSessionPolicy() {
        openWithTwoSteps()
        XCTAssertTrue(s.canEnd())
        s.advance(real: 600)
        s.accept(s.sys!.id)                           // check-up
        s.raise(.end)
        XCTAssertEqual(s.openReq?.verdict, .refused)
        XCTAssertEqual(s.openReq?.reason, "Finish the check-up first.")
        s.ack(s.openReq!.id)
        s.advance(real: 150)
        s.accept(s.sys!.id)                           // plan
        s.raise(.end)
        XCTAssertEqual(s.openReq?.verdict, .approved)
        s.accept(s.openReq!.id)
        XCTAssertNil(s.state)
        XCTAssertEqual(said.last, "Session ended.")
    }

    func testUndoRedoAndDependencyCycle() {
        let a = s.addChild(nil, "A")!
        let b = s.addChild(nil, "B")!
        s.addDep(b, on: a)
        XCTAssertTrue(s.isBlocked(b))
        s.addDep(a, on: b)                            // a cycle: refused
        XCTAssertEqual(s.nodes[a]!.deps, [])
        XCTAssertEqual(s.events.last { $0.outcome == .error }?.title, "patch refused: dependency cycle")
        s.undo()
        XCTAssertFalse(s.isBlocked(b))
        s.redo()
        XCTAssertTrue(s.isBlocked(b))
        XCTAssertEqual(s.validateCommit(b, a), "B is waiting for A, so it cannot be Doing yet.")
        XCTAssertNil(s.validateCommit(a, b))
    }

    func testAnnounceIsDeterministic() {
        var c = AnnounceContext()
        c.sessionId = "s1"; c.round = 2; c.R = 600; c.q = 75; c.Zmax = 3; c.z = 0; c.doing = "Fix"; c.next = "Copy"
        let a = Announce.phrase("round_start", c, voice: .rich), b = Announce.phrase("round_start", c, voice: .rich)
        XCTAssertEqual(a.text, b.text)
        XCTAssertEqual(Announce.phrase("round_start", c, voice: .fixed).text, "Round 2. Fix doing, Copy next. 10 min, starting now.")
        XCTAssertEqual(Announce.phrase("request_refused", AnnounceContext(), voice: .fixed).text, "A said no.")
        var r = AnnounceContext(); r.toPhase = "check-up"; r.len = 50
        XCTAssertEqual(Announce.phrase("request_approved", r, voice: .fixed).text, "Check-up, 50 s. Step away from the desk.")
    }

    func testPlanRoundTrip() throws {
        let a = s.addChild(nil, "One")!
        _ = s.addChild(a, "Two")
        let snap = s.snapshot()
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(PlanSnapshot.self, from: data)
        let t = Session()
        XCTAssertTrue(t.load(back))
        XCTAssertEqual(t.nodes.count, 3)              // the goal, One, Two
        XCTAssertEqual(t.kids(a).count, 1)
        XCTAssertEqual(t.goal().flatMap { t.title($0) }, "Today")
    }
}
