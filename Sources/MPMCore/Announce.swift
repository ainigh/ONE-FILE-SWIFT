import Foundation

// The engine's voice (announce.js). SPEC §6.9 fixes the wording of every announcement; this keeps
// that wording as variant 0 of every trigger and adds alternatives that carry exactly the same
// facts, chosen by the context the engine already has. Selection is a hash of (session, round,
// trigger), never random, so a replayed log speaks the same words. The model is never involved.

public struct DiffLine: Equatable {
    public var title: String
    public var from: DisplayStatus
    public var to: DisplayStatus
    public init(_ title: String, _ from: DisplayStatus, _ to: DisplayStatus) { self.title = title; self.from = from; self.to = to }
}

public struct HeldInfo: Equatable {
    public var say: Bool
    public var proposals: Int
    public init(say: Bool, proposals: Int) { self.say = say; self.proposals = proposals }
}

/// The context the engine hands in. All fields optional; each variant guards what it needs.
public struct AnnounceContext {
    public var sessionId: String?
    public var round: Int?
    public var R: Double?
    public var q: Double?
    public var G: Double?
    public var Lb: Double?
    public var Ls: Double?
    public var Zmax: Int?
    public var z: Int?
    public var x: Int?
    public var elapsed: Double?
    public var remaining: Double?
    public var statusLen: Double?
    public var seated: Double?
    public var doing: String?
    public var next: String?
    public var prevDoing: String?
    public var prevNext: String?
    public var diff: [DiffLine] = []
    public var reminderIndex: Int?
    public var reminderCount: Int?
    public var aName: String?
    public var bName: String?
    /// "stop" | "grace" for stop; the refusal's reason for request_refused.
    public var reason: String?
    /// For strategy_start / plan_start. `heldKnown` false means the caller said nothing about it.
    public var held: HeldInfo?
    public var heldKnown = false
    public var openCount: Int?
    public var message: String?
    public var chosen: Bool?
    public var doneCount: Int?
    public var blockedCount: Int?
    public var totalSteps: Int?
    public var clearedTotal: Int?
    public var stale: [String]?
    public var freeze: Double?
    public var human: Bool?
    public var hour: Int?
    // 2.1 request lines
    public var what: String?
    public var toPhase: String?
    public var n: Int?
    public var len: Double?

    public init() {}
    public init(doing: String?, prevDoing: String?) { self.doing = doing; self.prevDoing = prevDoing }
}

/// Everything a variant could want that follows from the context, computed once.
public struct Derived {
    public let c: AnnounceContext
    public let snoozesLeft: Int?
    public let lastSnooze: Bool
    public let snoozed: Bool
    public let firstRound: Bool
    public let nextRound: Int?
    public let pairSet: Bool
    public let nextSet: Bool
    public let pairKept: Bool
    public let pairAdvanced: Bool
    public let pairNew: Bool
    public let sameNext: Bool
    public let early: Bool
    public let veryEarly: Bool
    public let onTime: Bool
    public let ranLong: Bool
    public let overBy: Double?
    public let lastReminder: Bool
    public let firstReminder: Bool
    public let halfway: Bool
    public let remindersAfter: Int?
    public let reminderTimes: [Double]?
    public let usedShare: Double?
    public let checkupMax: Double?
    public let checkupSaved: Double?
    public let checkupNextSnooze: Double?
    public let longCheckup: Bool
    public let cleared: Int?
    public let clearedNone: Bool
    public let clearedMany: Bool
    public let untilBreak: Double?
    public let breakNext: Bool
    public let breakAfterNext: Bool
    public let seatedLong: Bool
    public let seatedFresh: Bool
    public let done: [String]
    public let blocked: [String]
    public let unblocked: [String]
    public let crossed: [String]
    public let moved: [DiffLine]
    public let diffCount: Int
    public let newBlocked: Int
    public let newDone: Int
    public let proposals: Int
    public let modelSpoke: Bool
    public let modelSilent: Bool
    public let staleCount: Int?
    public let openLeft: Int?
    public let allDone: Bool
    public let dayPart: String?
    public let longFreeze: Bool

    public init(_ c: AnnounceContext) {
        self.c = c
        snoozesLeft = (c.Zmax != nil && c.z != nil) ? max(0, c.Zmax! - c.z!) : nil
        lastSnooze = snoozesLeft == 0 && (c.z ?? 0) > 0
        snoozed = (c.z ?? 0) > 0
        firstRound = c.round == 1
        nextRound = c.round.map { $0 + 1 }
        pairSet = c.doing != nil
        nextSet = c.next != nil
        pairKept = c.doing != nil && c.doing == c.prevDoing
        pairAdvanced = c.doing != nil && c.prevNext != nil && c.doing == c.prevNext
        pairNew = c.doing != nil && c.prevDoing != nil && !pairKept && !pairAdvanced
        sameNext = c.next != nil && c.next == c.prevNext
        if let e = c.elapsed, let R = c.R {
            early = e < R - 30; veryEarly = e < R / 2; onTime = abs(e - R) <= 30; ranLong = e > R + 30
            overBy = e > R + 30 ? e - R : nil
        } else { early = false; veryEarly = false; onTime = false; ranLong = false; overBy = nil }
        lastReminder = c.reminderCount != nil && c.reminderIndex != nil && c.reminderIndex == c.reminderCount! - 1
        firstReminder = c.reminderIndex == 0
        halfway = firstReminder && c.R != nil && c.remaining != nil && abs(c.remaining! - c.R! / 2) < 1
        remindersAfter = (c.reminderCount != nil && c.reminderIndex != nil) ? c.reminderCount! - 1 - c.reminderIndex! : nil
        if let q = c.q, let Z = c.Zmax { reminderTimes = (0..<Z).reversed().map { q * pow(2, Double($0)) } } else { reminderTimes = nil }
        usedShare = (c.R != nil && c.remaining != nil && c.R! > 0) ? 1 - c.remaining! / c.R! : nil
        checkupMax = (c.q != nil && c.z != nil) ? c.q! * pow(2, Double(c.z! + 1)) : nil
        checkupSaved = (checkupMax != nil && c.statusLen != nil && (c.x ?? 0) > 0) ? checkupMax! - c.statusLen! : nil
        checkupNextSnooze = (c.q != nil && c.z != nil) ? c.q! * pow(2, Double(c.z! + 2)) : nil
        longCheckup = c.statusLen != nil && c.Lb != nil && c.statusLen! >= c.Lb!
        cleared = c.x
        clearedNone = c.x == 0
        clearedMany = (c.x ?? 0) >= 2
        untilBreak = (c.seated != nil && c.Ls != nil) ? max(0, c.Ls! - c.seated!) : nil
        let s = c.seated, Ls = c.Ls, R = c.R
        breakNext = s != nil && Ls != nil && R != nil && s! + R! > Ls!
        breakAfterNext = s != nil && Ls != nil && R != nil && !(s! + R! > Ls!) && s! + 2 * R! > Ls!
        seatedLong = s != nil && Ls != nil && s! >= Ls! / 2
        seatedFresh = s != nil && s! < 60
        let diff = c.diff.filter { $0.from != .new }
        var g = (done: [String](), blocked: [String](), unblocked: [String](), crossed: [String](), moved: [DiffLine]())
        for l in diff {
            if l.to == .done { g.done.append(l.title) }
            else if l.to == .blocked { g.blocked.append(l.title) }
            else if l.from == .blocked && l.to == .open { g.unblocked.append(l.title) }
            else if l.to == .crossed { g.crossed.append(l.title) }
            else { g.moved.append(l) }
        }
        done = g.done; blocked = g.blocked; unblocked = g.unblocked; crossed = g.crossed; moved = g.moved
        diffCount = diff.count
        newBlocked = g.blocked.count
        newDone = g.done.count
        proposals = c.held?.proposals ?? 0
        modelSpoke = c.held != nil && (c.held!.say || proposals > 0)
        modelSilent = c.heldKnown && c.held == nil
        staleCount = c.stale?.count
        openLeft = c.openCount
        allDone = c.doneCount != nil && c.totalSteps != nil && c.totalSteps! > 0 && c.doneCount == c.totalSteps
        if let h = c.hour { dayPart = h < 5 ? "night" : h < 12 ? "morning" : h < 17 ? "afternoon" : h < 22 ? "evening" : "night" } else { dayPart = nil }
        longFreeze = c.freeze != nil && c.R != nil && c.freeze! > c.R!
    }
}

public struct Announcement {
    public var text: String
    public var variant: Int
    public var tail: Int
    public var key: String
}

public enum Announce {
    typealias Say = (Derived) -> String
    typealias When = (Derived) -> Bool
    struct V {
        let say: Say
        let when: When?
        init(_ say: @escaping Say, _ when: When? = nil) { self.say = say; self.when = when }
    }

    static let fmt = Format.fmt
    static let n = Format.n
    static let list = Format.list
    static func or(_ v: String?, _ d: String) -> String { (v == nil || v!.isEmpty) ? d : v! }
    static func aName(_ d: Derived) -> String { or(d.c.aName, "A") }
    static func f(_ v: Double?) -> String { fmt(v ?? 0) }

    static func diffLines(_ c: AnnounceContext) -> [String] {
        c.diff.filter { $0.from != .new }.map { "\($0.title) \($0.from.word) → \($0.to.word)" }
    }
    static func diffSpoken(_ d: Derived) -> String {
        var out: [String] = []
        if !d.done.isEmpty { out.append("Done: " + list(d.done) + ".") }
        if !d.blocked.isEmpty { out.append((d.blocked.count == 1 ? "Newly blocked: " : "Blocked now: ") + list(d.blocked) + ".") }
        if !d.unblocked.isEmpty { out.append("Unblocked: " + list(d.unblocked) + ".") }
        if !d.crossed.isEmpty { out.append("Crossed out: " + list(d.crossed) + ".") }
        for l in d.moved { out.append("\(l.title) \(l.from.word) → \(l.to.word).") }
        return out.joined(separator: " ")
    }

    // MARK: The table. Index 0 is the spec text and has no guard.

    static let T: [String: [V]] = {
        var t: [String: [V]] = [:]
        t["session_start"] = [
            V({ _ in "Session open. Choose Doing and Next." }),
            V({ d in "Session open. Choose Doing and Next; \(aName(d)) will ask you to start round 1." }),
            V({ d in "Session open: \(n(d.c.openCount!, "open step", "open steps")). Choose Doing and Next." }, { $0.c.openCount != nil }),
            V({ d in "Session open. Nothing runs until \(aName(d)) asks you to start." }),
            V({ d in "Session open. Seated \(f(d.c.seated)) already, so the first break comes early. Choose Doing and Next." }, { $0.c.seated != nil && $0.seatedLong }),
            V({ d in "Session open, one open step: \(d.c.doing!). Choose it as Doing and \(aName(d)) will ask you to start." }, { $0.c.openCount == 1 && $0.c.doing != nil }),
            V({ d in "Good \(d.dayPart!). Session open. Choose Doing and Next." }, { $0.dayPart != nil && $0.dayPart != "night" }),
        ]
        t["round_start"] = [
            V({ d in "Round \(d.c.round ?? 0). \(or(d.c.doing, "nothing")) doing, \(or(d.c.next, "nothing")) next. \(f(d.c.R)), starting now." }),
            V({ d in "Round \(d.c.round!), as planned: \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next. \(f(d.c.R))." }, { !$0.firstRound && $0.pairAdvanced && $0.c.round != nil }),
            V({ d in "Round \(d.c.round ?? 0). \(d.c.doing!) first, then \(d.c.next!). \(f(d.c.R)) on the clock." }, { $0.c.doing != nil && $0.c.next != nil }),
            V({ d in "Round \(d.c.round ?? 0). \(d.c.doing!) doing, nothing next yet. \(f(d.c.R)), starting now." }, { $0.pairSet && !$0.nextSet }),
            V({ d in "Round 1. \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next. \(f(d.c.R)). First reminder at \(fmt((d.c.R ?? 0) / 2)) left." }, { $0.firstRound && $0.pairSet }),
            V({ d in "Round \(d.c.round ?? 0). Still on \(d.c.doing!), \(or(d.c.next, "nothing")) next. \(f(d.c.R)), starting now." }, { !$0.firstRound && $0.pairKept }),
            V({ d in "Round \(d.c.round ?? 0). \(d.c.prevNext!) moves up: \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next. \(f(d.c.R))." }, { !$0.firstRound && $0.pairAdvanced && $0.c.prevNext != nil }),
            V({ d in "Round \(d.c.round ?? 0), a new pair: \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next. \(f(d.c.R)), starting now." }, { $0.pairNew }),
            V({ d in "Round \(d.c.round ?? 0), the last before a break. \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next. \(f(d.c.R))." }, { $0.pairSet && $0.breakAfterNext }),
            V({ d in "Round \(d.c.round ?? 0). \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next. \(f(d.c.R)); reminders at \(list(d.reminderTimes!.map(fmt))) left." }, { $0.pairSet && $0.reminderTimes != nil && $0.reminderTimes!.count <= 4 }),
            V({ d in "The \(Format.ordinal(d.c.round!)) round. \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next. \(f(d.c.R)), starting now." }, { $0.pairSet && ($0.c.round ?? 0) >= 2 && ($0.c.round ?? 0) <= 12 }),
        ]
        t["reminder"] = [
            V({ d in "\(f(d.c.remaining)) left." }),
            V({ d in "\(f(d.c.remaining)) left, halfway." }, { $0.halfway }),
            V({ d in "Last reminder: \(f(d.c.remaining)). Get ready to stop." }, { $0.lastReminder }),
            V({ d in "\(f(d.c.remaining)) to go." }, { $0.c.reminderCount == nil || !$0.lastReminder }),
            V({ d in "\(f(d.c.remaining)) left on \(d.c.doing!)." }, { $0.c.doing != nil && !$0.lastReminder }),
            V({ d in "\(f(d.c.remaining)) left. Wrap up \(d.c.doing!)." }, { $0.c.doing != nil && $0.lastReminder }),
            V({ d in "Halfway: \(f(d.c.remaining)) left, \(fmt((d.c.R ?? 0) - (d.c.remaining ?? 0))) gone." }, { $0.halfway }),
            V({ d in "\(f(d.c.remaining)) left, \(n(d.remindersAfter!, "more reminder", "more reminders")) after this." }, { ($0.remindersAfter ?? 0) > 0 }),
            V({ d in "Last reminder: \(f(d.c.remaining)). \(n(d.snoozesLeft!, "snooze", "snoozes")) at the end if you need one." }, { $0.lastReminder && ($0.snoozesLeft ?? 0) > 0 }),
            V({ d in "Last reminder: \(f(d.c.remaining)), and no snoozes left after this." }, { $0.lastReminder && $0.snoozesLeft == 0 }),
        ]
        t["time_up"] = [
            V({ _ in "Time's up." }),
            V({ d in "Time's up. \(n(d.c.Zmax! - d.c.z!, "snooze", "snoozes")) left, \(f(d.c.G)) to decide." }, { $0.c.Zmax != nil && $0.c.z != nil && $0.c.G != nil && ($0.snoozesLeft ?? 0) > 0 }),
            V({ _ in "Time's up. No snoozes left: stop." }, { $0.snoozesLeft == 0 }),
            V({ _ in "Snooze over. Time's up." }, { $0.snoozed }),
            V({ d in "Time's up. Go to check-up, or snooze: \(n(d.snoozesLeft!, "snooze", "snoozes")) left, \(f(d.c.q)) each." }, { $0.c.q != nil && ($0.snoozesLeft ?? 0) > 0 }),
            V({ d in "Snooze \(d.c.z!) over. Time's up, \(n(d.snoozesLeft!, "snooze", "snoozes")) left." }, { $0.snoozed && ($0.snoozesLeft ?? 0) > 0 }),
            V({ d in "Time's up on round \(d.c.round!). \(d.c.doing!) waits where it is." }, { $0.c.round != nil && $0.c.doing != nil }),
            V({ _ in "Time's up. The last snooze is spent, so Go is the only way on." }, { $0.lastSnooze }),
            V({ d in "Time's up, round \(d.c.round!). Seated \(f(d.c.seated)); the sitting clock keeps running while you decide." }, { $0.c.round != nil && $0.c.seated != nil && $0.seatedLong }),
        ]
        t["snooze_accepted"] = [
            V({ d in "Snooze \(d.c.z ?? 0) of \(d.c.Zmax ?? 0). \(f(d.c.q))." }),
            V({ d in "Snooze \(d.c.z!) of \(d.c.Zmax!), the last one. \(f(d.c.q))." }, { $0.c.z != nil && $0.c.Zmax != nil && $0.c.z == $0.c.Zmax }),
            V({ d in "Snooze \(d.c.z!) of \(d.c.Zmax!): \(f(d.c.q)) more. Away time doubles." }, { $0.c.z != nil && $0.c.Zmax != nil && $0.c.z! < $0.c.Zmax! }),
            V({ d in "Snooze \(d.c.z ?? 0) of \(d.c.Zmax ?? 0). \(f(d.c.q)) more on \(d.c.doing!)." }, { $0.c.doing != nil }),
            V({ d in "Snooze \(d.c.z ?? 0) of \(d.c.Zmax ?? 0). \(f(d.c.q)); the check-up after is up to \(fmt(d.checkupMax!)), less for every step cleared." }, { $0.checkupMax != nil }),
            V({ d in "Snooze \(d.c.z ?? 0) of \(d.c.Zmax ?? 0), \(f(d.c.q)). \(n(d.snoozesLeft!, "snooze", "snoozes")) after this one." }, { ($0.snoozesLeft ?? 0) > 0 }),
            V({ d in "Last snooze, \(d.c.z!) of \(d.c.Zmax!): \(f(d.c.q)), then check-up for certain." }, { $0.c.z != nil && $0.c.Zmax != nil && $0.c.z == $0.c.Zmax }),
        ]
        t["snooze_refused"] = [
            V({ _ in "No snoozes left. Stop." }),
            V({ d in "All \(d.c.Zmax!) snoozes used. Stop." }, { $0.c.Zmax != nil }),
            V({ d in "All \(d.c.Zmax!) snoozes used this round. Check-up is next." }, { $0.c.Zmax != nil }),
        ]
        t["stop"] = [
            V({ _ in "Stop." }),
            V({ _ in "No answer. Stop." }, { $0.c.reason == "grace" }),
            V({ d in "Stop. Round over at \(f(d.c.elapsed))." }, { $0.c.reason != "grace" && $0.c.elapsed != nil }),
            V({ d in "Stop. Round \(d.c.round!) over at \(f(d.c.elapsed)), \(fmt(d.overBy!)) past the clock." }, { $0.c.round != nil && $0.ranLong && $0.c.reason != "grace" }),
        ]
        t["late_snooze"] = [
            V({ _ in "Too late. Stop." }),
            V({ d in "The \(f(d.c.G)) window has passed. Stop." }, { $0.c.G != nil }),
        ]
        t["status_start"] = [
            V({ d in "Round over at \(f(d.c.elapsed)). Status, \(f(d.c.statusLen))." }),
            V({ d in "Round over at \(f(d.c.elapsed)). Nothing cleared. Status, \(f(d.c.statusLen))." }, { $0.clearedNone }),
            V({ d in "Round over at \(f(d.c.elapsed)), \(n(d.c.x!, "step", "steps")) cleared. Status, \(f(d.c.statusLen))." }, { $0.clearedMany }),
            V({ d in "Round over at \(f(d.c.elapsed)). Status, \(f(d.c.statusLen)): long enough to count as moving." }, { $0.longCheckup }),
            V({ d in "Round over at \(f(d.c.elapsed)). \(n(d.c.z!, "snooze", "snoozes")), so status is \(f(d.c.statusLen))." }, { $0.snoozed }),
            V({ d in "Round over early, at \(f(d.c.elapsed)). Status, \(f(d.c.statusLen))." }, { $0.early && !$0.snoozed }),
            V({ d in "Round over at \(f(d.c.elapsed)), one step cleared: \(list(d.done)). Status, \(f(d.c.statusLen))." }, { $0.cleared == 1 && $0.newDone == 1 }),
            V({ d in "Round over at \(f(d.c.elapsed)). Clearing \(n(d.c.x!, "step", "steps")) cut status from \(fmt(d.checkupMax!)) to \(f(d.c.statusLen))." }, { ($0.checkupSaved ?? 0) >= 15 }),
        ]
        t["strategy_start"] = [
            V({ d in "Strategy, \(f(d.c.q))." }),
            V({ d in "Strategy, \(f(d.c.q)). The model has \(n(d.proposals, "proposal", "proposals"))." }, { $0.proposals > 0 }),
            V({ d in "Strategy, \(f(d.c.q)). The model has a note, no proposals." }, { $0.c.held?.say == true && $0.proposals == 0 }),
            V({ d in "Strategy, \(f(d.c.q)). Nothing from the model this round." }, { $0.modelSilent }),
            V({ d in "Strategy, \(f(d.c.q)). Choose nothing and \(d.c.prevDoing!) stays doing." }, { $0.c.prevDoing != nil }),
            V({ d in "Strategy, \(f(d.c.q)). \(d.c.prevDoing!) is done; pick what comes after \(or(d.c.prevNext, "it"))." }, { $0.c.prevDoing != nil && $0.done.contains($0.c.prevDoing!) }),
            V({ d in "Strategy, \(f(d.c.q)), and a break follows it: seated \(f(d.c.seated))." }, { $0.c.seated != nil && $0.breakNext }),
        ]
        t["auto_commit"] = [
            V({ d in "No choice made. \(or(d.c.doing, "nothing")) doing, \(or(d.c.next, "nothing")) next." }),
            V({ d in "No choice made. Keeping \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next." }, { $0.pairKept }),
            V({ d in "No choice made. \(d.c.doing!) moves up to doing, \(or(d.c.next, "nothing")) next." }, { $0.pairAdvanced }),
            V({ d in "No choice made, so the plan filled it: \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next." }, { $0.pairNew }),
            V({ d in "No choice made. \(d.c.doing!) doing, \(d.c.next!) next, as before." }, { $0.pairKept && $0.sameNext }),
        ]
        t["promote_next"] = [
            V({ d in "Now doing \(or(d.c.doing, "nothing"))." }),
            V({ d in "Now doing \(or(d.c.doing, "nothing")). Next is open." }),
            V({ d in "\(d.c.prevDoing!) done. Now doing \(or(d.c.doing, "nothing"))." }, { $0.c.prevDoing != nil }),
            V({ d in "\(d.c.prevDoing!) done. \(or(d.c.doing, "nothing")) moves up; pick a new Next at the plan." }, { $0.c.prevDoing != nil && !$0.nextSet }),
            V({ d in "Now doing \(or(d.c.doing, "nothing")), with \(d.c.next!) next." }, { $0.c.next != nil }),
        ]
        t["no_doing"] = [
            V({ _ in "No doing node." }),
            V({ _ in "No doing node. Finish the round when you are ready." }),
            V({ d in "No doing node; \(d.c.next!) is next but nothing is doing. Finish the round when you are ready." }, { $0.c.next != nil }),
            V({ d in "No doing node, \(n(d.c.openCount!, "open step", "open steps")) to choose from at the plan." }, { ($0.openLeft ?? 0) > 0 }),
        ]
        t["break_start"] = [
            V({ d in "Seated \(f(d.c.seated)). Movement break, \(f(d.c.Lb))." }),
            V({ d in "Seated \(f(d.c.seated)); another round would pass \(f(d.c.Ls)). Movement break, \(f(d.c.Lb))." }, { $0.c.Ls != nil }),
            V({ d in "Seated \(f(d.c.seated)). Stand up: \(f(d.c.Lb)) away, the plan is locked." }),
            V({ d in "Seated \(f(d.c.seated)), past the \(f(d.c.Ls)) limit. Movement break, \(f(d.c.Lb))." }, { $0.c.Ls != nil && ($0.c.seated ?? 0) >= $0.c.Ls! }),
            V({ d in "Seated \(f(d.c.seated)). Movement break, \(f(d.c.Lb)); round \(d.nextRound!) waits behind it with \(d.c.doing!) doing." }, { $0.nextRound != nil && $0.c.doing != nil }),
            V({ d in "Seated \(f(d.c.seated)) across \(n(d.c.round!, "round", "rounds")). Movement break, \(f(d.c.Lb))." }, { ($0.c.round ?? 0) >= 2 }),
        ]
        t["continue"] = [
            V({ d in "Seated \(f(d.c.seated)). Continue." }),
            V({ d in "Seated \(f(d.c.seated)). Continue; this is the last round before a break." }, { $0.breakAfterNext }),
            V({ d in "Seated \(f(d.c.seated)), \(fmt(d.untilBreak!)) before a break. Continue." }, { $0.c.R != nil && $0.untilBreak != nil && ($0.c.seated ?? 0) + 2 * $0.c.R! <= ($0.c.Ls ?? 0) }),
            V({ d in "Seated \(f(d.c.seated)). Continue to round \(d.nextRound!)." }, { $0.nextRound != nil }),
            V({ d in "Seated \(f(d.c.seated)). Continue; a break would be \(f(d.c.Lb)) when it comes." }, { $0.c.Lb != nil && $0.seatedFresh }),
            V({ d in "Seated \(f(d.c.seated)), about \(Int((100 * (d.c.seated ?? 0) / d.c.Ls!).rounded()))% of the sitting limit. Continue." }, { $0.c.Ls != nil && ($0.c.seated ?? 0) > 0 && ($0.c.seated ?? 0) < $0.c.Ls! }),
        ]
        t["planning_over"] = [
            V({ d in "Planning time is up. \(aName(d)) asks you to start round \((d.c.round ?? 0) + 1)." }),
            V({ d in "Planning over. \(or(d.c.doing, "Nothing")) doing, \(or(d.c.next, "nothing")) next, unless you change it. \(aName(d)) asks you to start round \((d.c.round ?? 0) + 1)." }),
            V({ d in "Planning over. No pair chosen: round \((d.c.round ?? 0) + 1) keeps \(d.c.doing!) doing when you start it." }, { $0.pairSet && $0.c.chosen != true }),
            V({ d in "Planning over. Your pair holds: \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next. \(aName(d)) asks you to start round \((d.c.round ?? 0) + 1)." }, { $0.pairSet && $0.c.chosen == true }),
        ]
        t["break_end"] = [
            V({ _ in "Sitting clock reset." }),
            V({ d in "Break over. Sitting clock reset. Round \(d.c.round!) next." }, { $0.c.round != nil }),
            V({ d in "Break over, sitting clock at zero. Round \(d.c.round!): \(d.c.doing!) doing when you press Go." }, { $0.c.round != nil && $0.c.doing != nil }),
            V({ d in "Sitting clock reset: \(f(d.c.Ls)) of seated time ahead before the next break." }, { $0.c.Ls != nil }),
        ]
        t["not_available"] = [
            V({ d in d.c.message ?? "Not available now." }),
        ]
        t["request_waiting"] = [
            V({ d in "Waiting for \(aName(d)) to approve \(or(d.c.what, "this"))." }),
        ]
        t["request_approved"] = [
            V({ d in
                let c = d.c
                switch c.toPhase {
                case "work": return "Round \(c.n ?? 0): \(or(c.doing, "nothing"))\(c.next != nil ? ", then \(c.next!)" : ""). \(f(c.R))."
                case "snooze": return "Snooze \(c.n ?? 0) of \(c.Zmax ?? 0). \(f(c.q))."
                case "check-up": return "Check-up, \(f(c.len)). Step away from the desk."
                case "plan": return "Plan round \(c.n ?? 0). \(f(c.q))."
                case "break": return "Movement break, \(f(c.Lb)). Stand up and move."
                default: return "End the session."
                }
            }),
        ]
        t["request_refused"] = [
            V({ d in or(d.c.reason, "\(aName(d)) said no.") }),
        ]
        t["checkup_start"] = [
            V({ d in "Round over at \(f(d.c.elapsed)). Check-up, \(f(d.c.statusLen))." }),
            V({ d in "Round over at \(f(d.c.elapsed)). Nothing cleared. Check-up, \(f(d.c.statusLen))." }, { $0.clearedNone }),
            V({ d in "Round over at \(f(d.c.elapsed)), \(n(d.c.x!, "step", "steps")) cleared. Check-up, \(f(d.c.statusLen))." }, { $0.clearedMany }),
            V({ d in "Round over at \(f(d.c.elapsed)). Check-up, \(f(d.c.statusLen)): long enough to count as moving." }, { $0.longCheckup }),
            V({ d in "Round \(d.c.round!) over at \(f(d.c.elapsed)). Check-up, \(f(d.c.statusLen)); nothing to do in it but step away." }, { $0.c.round != nil }),
            V({ d in "Round over early, at \(f(d.c.elapsed)). Check-up, \(f(d.c.statusLen))." }, { $0.early && !$0.snoozed }),
            V({ d in "Round over at \(f(d.c.elapsed)) after \(n(d.c.z!, "snooze", "snoozes")). Check-up, \(f(d.c.statusLen))." }, { $0.snoozed }),
            V({ d in "Round over at \(f(d.c.elapsed)), one step cleared: \(list(d.done)). Check-up, \(f(d.c.statusLen))." }, { $0.cleared == 1 && $0.newDone == 1 }),
            V({ d in "Round over at \(f(d.c.elapsed)). Clearing \(n(d.c.x!, "step", "steps")) cut the check-up from \(fmt(d.checkupMax!)) to \(f(d.c.statusLen))." }, { ($0.checkupSaved ?? 0) >= 15 }),
            V({ d in "Round over at \(f(d.c.elapsed)). Nothing cleared and \(n(d.c.z!, "snooze", "snoozes")): check-up is \(f(d.c.statusLen))." }, { $0.clearedNone && $0.snoozed }),
            V({ d in "Round over at \(f(d.c.elapsed)). Check-up, \(f(d.c.statusLen)), and the sitting clock resets with it." }, { $0.longCheckup }),
            V({ d in "Round over at \(f(d.c.elapsed)). \(d.c.doing!) is still doing. Check-up, \(f(d.c.statusLen))." }, { $0.c.doing != nil && $0.diffCount == 0 }),
        ]
        t["plan_start"] = [
            V({ d in "Plan round \((d.c.round ?? 0) + 1), \(f(d.c.q))." }),
            V({ d in "Plan round \((d.c.round ?? 0) + 1), \(f(d.c.q)). The model has \(n(d.proposals, "proposal", "proposals"))." }, { $0.proposals > 0 }),
            V({ d in "Plan round \((d.c.round ?? 0) + 1), \(f(d.c.q)). Nothing from the model this round." }, { $0.modelSilent }),
            V({ d in "Plan round \((d.c.round ?? 0) + 1), \(f(d.c.q)). The model has a note, no proposals." }, { $0.c.held?.say == true && $0.proposals == 0 }),
            V({ d in "Plan round \((d.c.round ?? 0) + 1), \(f(d.c.q)). Choose nothing and \(d.c.doing!) stays doing." }, { $0.c.doing != nil }),
            V({ d in "Plan round \((d.c.round ?? 0) + 1), \(f(d.c.q)). \(d.c.doing!) is still doing; pick a Next or carry on with it alone." }, { $0.c.doing != nil && !$0.nextSet }),
            V({ d in "Plan round \((d.c.round ?? 0) + 1), \(f(d.c.q)). Doing is empty: choose one, or the plan picks for you at the end." }, { !$0.pairSet }),
            V({ d in "Plan round \((d.c.round ?? 0) + 1), \(f(d.c.q)), then a break: seated \(f(d.c.seated))." }, { $0.c.seated != nil && $0.breakNext }),
            V({ d in "Plan round \((d.c.round ?? 0) + 1), \(f(d.c.q)). \(n(d.staleCount!, "step", "steps")) untouched for days: \(list(d.c.stale ?? []))." }, { ($0.staleCount ?? 0) > 0 && ($0.staleCount ?? 0) <= 3 }),
        ]
        t["plan_over"] = [
            V({ d in "Planning over. Start round \((d.c.round ?? 0) + 1)?" }),
            V({ d in "Planning over. Keeping \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next." }, { $0.pairSet && $0.c.chosen != true }),
            V({ d in "Planning over. \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next. Start round \((d.c.round ?? 0) + 1)?" }, { $0.pairSet && $0.c.chosen == true }),
            V({ d in "Planning over, nothing chosen: the plan filled it with \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next." }, { $0.pairSet && $0.c.chosen != true && $0.pairNew }),
            V({ d in "Planning over. \(d.c.doing!) doing, \(d.c.next!) next; a break comes before round \((d.c.round ?? 0) + 1)." }, { $0.c.doing != nil && $0.c.next != nil && $0.breakNext }),
        ]
        return t
    }()

    // MARK: The tails: one extra sentence about what the numbers mean for B right now.

    static let TAILS: [String: [V]] = {
        var t: [String: [V]] = [:]
        t["session_start"] = [
            V({ d in "Rounds are \(f(d.c.R)) with \(n(d.c.Zmax!, "reminder", "reminders"))." }, { $0.c.R != nil && $0.c.Zmax != nil }),
            V({ d in "Seated \(f(d.c.seated)) already; the sitting clock runs from here." }, { ($0.c.seated ?? 0) >= 60 }),
            V({ d in "The first round starts when \(aName(d)) asks and you press Go." }),
        ]
        t["round_start"] = [
            V({ d in "A break comes after this one: seated \(f(d.c.seated))." }, { $0.c.seated != nil && $0.breakAfterNext }),
            V({ d in "\(fmt(d.untilBreak!)) of sitting time left before a break." }, { $0.untilBreak != nil && !$0.breakAfterNext && $0.untilBreak! > 0 }),
            V({ d in "Reminders at \(list(d.reminderTimes!.map(fmt))) left; the last one covers the screen." }, { $0.reminderTimes != nil && $0.reminderTimes!.count <= 4 }),
            V({ _ in "Next is open; choose one at the plan." }, { $0.pairSet && !$0.nextSet }),
            V({ d in "\(n(d.c.Zmax!, "snooze", "snoozes")) of \(f(d.c.q)) if you need them at the end." }, { $0.c.Zmax != nil && $0.c.q != nil }),
            V({ _ in "Mark steps done as you clear them: each one shortens the check-up." }, { $0.c.q != nil }),
            V({ d in "\(d.c.prevDoing!) is done; this round moves on from it." }, { $0.c.prevDoing != nil && $0.pairAdvanced }),
        ]
        t["reminder"] = [
            V({ d in "Then \(d.c.next!)." }, { $0.c.next != nil && $0.lastReminder }),
            V({ _ in "The clock keeps running; Go or Snooze when it ends." }, { $0.lastReminder }),
            V({ _ in "A good moment to mark anything finished as done." }, { $0.halfway }),
        ]
        t["time_up"] = [
            V({ _ in "Snoozing doubles the check-up; clearing steps shortens it." }, { ($0.snoozesLeft ?? 0) > 0 }),
            V({ d in "Check-up follows: up to \(fmt(d.checkupMax!)), less for every step cleared." }, { $0.checkupMax != nil }),
            V({ _ in "Take your time; nothing runs until you press Go." }),
            V({ d in "A break comes before the next round: seated \(f(d.c.seated))." }, { $0.c.seated != nil && $0.breakNext }),
            V({ d in "Round \(d.c.round!) ran \(f(d.c.elapsed)) with the snoozes." }, { $0.c.round != nil && $0.snoozed && $0.ranLong }),
        ]
        t["snooze_accepted"] = [
            V({ d in "Finish what is in your hands on \(d.c.doing!)." }, { $0.c.doing != nil }),
            V({ d in "One more snooze and the check-up would be up to \(fmt(d.checkupNextSnooze!))." }, { $0.checkupNextSnooze != nil && ($0.snoozesLeft ?? 0) > 0 }),
            V({ _ in "This is the last one; the check-up comes after it." }, { $0.lastSnooze }),
            V({ _ in "Each step marked done before it ends shortens the check-up." }),
        ]
        t["status_start"] = [
            V({ _ in "Step away from the desk; the plan is locked until it ends." }),
            V({ d in "Plan round \(d.nextRound!) follows, \(f(d.c.q))." }, { $0.nextRound != nil && $0.c.q != nil }),
            V({ d in "Without \(n(d.c.x!, "cleared step", "cleared steps")) it would have been \(fmt(d.checkupMax!))." }, { ($0.checkupSaved ?? 0) >= 15 }),
            V({ d in "Then a movement break: seated \(f(d.c.seated))." }, { $0.c.seated != nil && $0.breakNext && !$0.longCheckup }),
        ]
        t["checkup_start"] = [
            V({ _ in "Step away from the desk; the plan is locked until it ends." }),
            V({ d in "Plan round \(d.nextRound!) follows, \(f(d.c.q))." }, { $0.nextRound != nil && $0.c.q != nil }),
            V({ d in "Without \(n(d.c.x!, "cleared step", "cleared steps")) it would have been \(fmt(d.checkupMax!))." }, { ($0.checkupSaved ?? 0) >= 15 }),
            V({ d in "Then a movement break: seated \(f(d.c.seated))." }, { $0.c.seated != nil && $0.breakNext && !$0.longCheckup }),
            V({ _ in "It counts as moving, so the sitting clock starts again from zero." }, { $0.longCheckup }),
            V({ d in "Seated \(f(d.c.seated)); \(fmt(d.untilBreak!)) to the sitting limit." }, { $0.c.seated != nil && $0.untilBreak != nil && !$0.longCheckup && !$0.breakNext && $0.seatedLong }),
            V({ d in "Newly blocked: \(list(d.blocked)). Worth a look at the plan." }, { $0.newBlocked > 0 && $0.newBlocked <= 3 }),
        ]
        t["strategy_start"] = [
            V({ d in "Choose Doing and Next, or leave \(d.c.prevDoing!) where it is." }, { $0.c.prevDoing != nil && !$0.pairSet }),
            V({ d in "A break comes before round \(d.nextRound!)." }, { $0.nextRound != nil && $0.breakNext }),
        ]
        t["plan_start"] = [
            V({ _ in "The board shows this round's changes; set the pair there." }, { $0.diffCount > 0 }),
            V({ d in "Read the model's \(n(d.proposals, "proposal", "proposals")), then choose; none of it moves on its own." }, { $0.proposals > 0 }),
            V({ d in "A break comes before round \(d.nextRound!): seated \(f(d.c.seated))." }, { $0.nextRound != nil && $0.c.seated != nil && $0.breakNext }),
            V({ d in "Round \(d.nextRound!) is the last before a break." }, { $0.nextRound != nil && $0.breakAfterNext }),
            V({ d in "Done this round: \(list(d.done))." }, { $0.newDone > 0 && $0.newDone <= 3 }),
            V({ d in "Nothing was marked done this round; \(d.c.doing!) carries over." }, { $0.c.doing != nil && $0.clearedNone }),
            V({ d in "Leave it and the plan commits \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next at the end." }, { $0.c.doing != nil }),
            V({ _ in "Press Next phase when the pair is set; the clock stops at Go." }),
        ]
        t["plan_over"] = [
            V({ d in "Round \(d.nextRound!) starts at your Go, \(f(d.c.R))." }, { $0.nextRound != nil && $0.c.R != nil && !$0.breakNext }),
            V({ d in "A movement break comes first: seated \(f(d.c.seated))." }, { $0.c.seated != nil && $0.breakNext }),
            V({ _ in "Nothing runs until you press Go." }),
        ]
        t["auto_commit"] = [
            V({ _ in "Change it at the next plan if that is not what you want." }),
            V({ _ in "Next is still open; the plan will ask again." }, { $0.pairSet && !$0.nextSet }),
        ]
        t["promote_next"] = [
            V({ _ in "Next is empty now; choose one at the plan." }, { !$0.nextSet }),
            V({ d in "Still \(f(d.c.remaining)) left in the round." }, { ($0.c.remaining ?? 0) >= 60 }),
        ]
        t["no_doing"] = [
            V({ _ in "Choose a Doing at the plan and the next round has somewhere to go." }),
        ]
        t["break_start"] = [
            V({ d in "Round \(d.nextRound!) follows the break." }, { $0.nextRound != nil }),
            V({ d in "The pair is set: \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next." }, { $0.c.doing != nil }),
            V({ _ in "The sitting clock resets when the break ends." }),
            V({ _ in "It ends on its own; policy refuses an early move out." }),
        ]
        t["continue"] = [
            V({ d in "Round \(d.nextRound!): \(d.c.doing!) doing, \(or(d.c.next, "nothing")) next." }, { $0.nextRound != nil && $0.c.doing != nil }),
            V({ _ in "Seated time keeps counting through the round." }, { $0.seatedLong }),
            V({ _ in "A break would come after the next round." }, { $0.breakAfterNext }),
        ]
        t["break_end"] = [
            V({ d in "\(d.c.doing!) doing, \(or(d.c.next, "nothing")) next, \(f(d.c.R))." }, { $0.c.doing != nil && $0.c.R != nil }),
            V({ _ in "Press Go when you are back at the desk." }),
        ]
        t["snooze_refused"] = [
            V({ d in "Check-up is up to \(fmt(d.checkupMax!)) now, less for every step cleared." }, { $0.checkupMax != nil }),
        ]
        t["planning_over"] = [
            V({ d in "Round \(d.nextRound!) starts at your Go, \(f(d.c.R))." }, { $0.nextRound != nil && $0.c.R != nil }),
        ]
        return t
    }()

    // MARK: API

    public static var triggers: [String] { Array(T.keys).sorted() }

    static func applicable(_ trigger: String, _ d: Derived) -> [V] {
        guard let list = T[trigger] else { return [V({ _ in trigger })] }
        return list.enumerated().filter { i, v in i == 0 || v.when == nil || v.when!(d) }.map { $0.element }
    }
    static func applicableTails(_ trigger: String, _ d: Derived) -> [V] {
        (TAILS[trigger] ?? []).filter { $0.when == nil || $0.when!(d) }
    }

    /// Every applicable sentence, the spec's first.
    public static func variants(_ trigger: String, _ ctx: AnnounceContext) -> [String] {
        let d = Derived(ctx)
        return applicable(trigger, d).map { $0.say(d) }
    }
    public static func tails(_ trigger: String, _ ctx: AnnounceContext) -> [String] {
        let d = Derived(ctx)
        return applicableTails(trigger, d).map { $0.say(d) }
    }

    /// varied: a variant (and the diff spoken); tail: a second sentence more often than not.
    public static func announce(_ trigger: String, _ ctx: AnnounceContext, varied: Bool, tail: Bool, seed: String? = nil) -> Announcement {
        let d = Derived(ctx)
        let list = applicable(trigger, d)
        let key = seed ?? [ctx.sessionId ?? "", String(ctx.round ?? 0), trigger, String(ctx.reminderIndex ?? 0), String(ctx.z ?? 0)].joined(separator: "|")
        let i = varied && list.count > 1 ? Int(Format.fnv1a(key) % UInt32(list.count)) : 0
        var text = list[i].say(d)
        var tailIndex = -1
        if trigger == "status_start" || trigger == "checkup_start" {
            if varied { let s = diffSpoken(d); if !s.isEmpty { text += " " + s } }
            else { let l = diffLines(ctx); if !l.isEmpty { text += " " + l.joined(separator: ", ") + "." } }
        }
        if varied && tail {
            let ts = applicableTails(trigger, d)
            if !ts.isEmpty {
                let j = Int(Format.fnv1a(key + "|tail") % UInt32(ts.count + 1))
                if j < ts.count {
                    let extra = ts[j].say(d)
                    if !text.contains(extra) { tailIndex = j; text += " " + extra }
                }
            }
        }
        return Announcement(text: text, variant: i, tail: tailIndex, key: key)
    }

    /// As voice.js uses it: fixed never leaves variant 0; varied picks; rich adds a tail.
    public static func phrase(_ trigger: String, _ ctx: AnnounceContext, voice: VoiceStyle) -> Announcement {
        announce(trigger, ctx, varied: voice != .fixed, tail: voice == .rich)
    }
}
