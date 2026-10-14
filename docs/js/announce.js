/* announce.js — the engine's voice.
 *
 * SPEC §6.9 fixes the wording of every announcement the engine (A, the Timekeeper) makes.
 * This module keeps that wording as variant 0 of every trigger and adds alternatives that
 * carry exactly the same facts, chosen by the context the engine already has: round, z, x,
 * seated time, the pair, the diff, which reminder this is, and everything that follows from
 * those numbers (snoozes left, how far the next break is, how the check-up was computed).
 *
 * Three rules keep it inside the spec:
 *  1. Variant 0 is always the §6.9 text, adjusted where the landing page's roles differ: there
 *     B chooses Doing and Next, only A may ask for a round to start, and B starts it from
 *     A's request, so nothing tells B to commit on their own.
 *     voice: "fixed" (the default) never leaves variant 0 and adds no tail.
 *  2. Every variant states the same numbers and names. Only the sentence around them moves.
 *     A variant may add a fact the engine already knows (snoozes left, the next break); it
 *     never drops one and never invents one.
 *  3. Selection is a hash of (session, round, trigger), never Math.random, so a replayed log
 *     speaks the same words. Invariant 12 holds: the model is never involved.
 *
 * Two layers make the voice:
 *   the sentence   one of the trigger's variants, guarded by context;
 *   the tail       an optional second sentence that says what the numbers mean for B right
 *                  now ("a break comes before the next round", "clearing two steps cut the
 *                  check-up from 5 min"). Tails are drawn from a separate table, also guarded
 *                  and also hashed, and only in the varied voice.
 *
 * Usage:
 *   announce("status_start", ctx)                        → { text, variant, tail, key }
 *   announce("status_start", ctx, { voice: "varied" })
 *   announce("status_start", ctx, { voice: "varied", tail: false })
 *   variants("status_start", ctx)                        → every applicable sentence, 0 first
 *   tails("status_start", ctx)                           → every applicable tail
 *   enrich(ctx)                                          → ctx plus the derived fields below
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.Announce = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  /* ---------- formatting, identical to the engine's ---------- */
  function pad2(n) { return String(n).padStart(2, "0"); }
  // Countdown digits: whole seconds, rounded up.
  function digits(s) { s = Math.max(0, Math.ceil(s - 1e-9)); return Math.floor(s / 60) + ":" + pad2(s % 60); }
  // Spoken-friendly lengths: 45 s, 1:30, 10 min, 1:05:00.
  function fmt(t) {
    var s = Math.round(t);
    if (s < 60) return s + " s";
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    if (h > 0) return h + ":" + pad2(m) + ":" + pad2(sec);
    if (sec === 0) return m + " min";
    return m + ":" + pad2(sec);
  }
  function n(x, one, many) { return x + " " + (x === 1 ? one : many); }
  function or(v, d) { return v == null || v === "" ? d : v; }
  var ORD = ["zeroth", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth"];
  function ordinal(i) { return ORD[i] || (i + "th"); }
  // "a, b and c" from a list of titles; the empty list reads as "nothing".
  function list(xs) {
    if (!xs || !xs.length) return "nothing";
    if (xs.length === 1) return xs[0];
    return xs.slice(0, -1).join(", ") + " and " + xs[xs.length - 1];
  }
  function num(v) { return typeof v === "number" && !isNaN(v); }

  /* ---------- deterministic choice ---------- */
  function hash(str) { // FNV-1a, 32-bit
    var h = 0x811c9dc5;
    for (var i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
    return h >>> 0;
  }

  /* ---------- the context the engine hands in ----------
   * All fields optional; each variant guards what it needs. Times in seconds.
   *   sessionId, round, R, q, G, Lb, Ls, Zmax
   *   z, x, elapsed, remaining, statusLen, seated
   *   doing, next, prevDoing, prevNext        node titles
   *   diff: [[title, from, to], ...]          this round's status changes
   *   reminderIndex, reminderCount            which reminder is firing
   *   aName, bName                            what the screens call A and B (default "A", "B")
   *   reason: "stop" | "grace"                for stop
   *   held: { say: bool, proposals: int }     for strategy_start / plan_start
   *   openCount                               for session_start
   *   message                                 for not_available
   *   chosen                                  for planning_over / plan_over: B changed the pair
   *
   * Optional extras a caller may add; nothing here needs them, every line that uses one guards it:
   *   doneCount, blockedCount, totalSteps     the plan's shape at this moment
   *   clearedTotal                            steps marked done so far this session
   *   stale: [title, ...]                     steps untouched for days (the scheduler's nudge)
   *   freeze                                  how long B took to press Go after the clock ended
   *   human                                   true when a person, not policy, is A
   *   hour                                    wall-clock hour, 0..23, for a word about the time of day
   */

  /* ---------- derived context ----------
   * Everything a variant could want that follows from the fields above, computed once so the
   * tables read as prose. Each field is null when its inputs are missing, so guards stay honest.
   */
  var STATE_WORD = { open: "open", doing: "doing", next: "next", blocked: "blocked", done: "done", crossed_out: "crossed out", crossed: "crossed out", "new": "new" };
  function enrich(c) {
    c = c || {};
    var d = {};
    for (var k in c) d[k] = c[k];
    var has = function (k) { return num(c[k]); };

    d.snoozesLeft = has("Zmax") && has("z") ? Math.max(0, c.Zmax - c.z) : null;
    d.lastSnooze = d.snoozesLeft === 0 && has("z") && c.z > 0;
    d.snoozed = has("z") && c.z > 0;
    d.firstRound = c.round === 1;
    d.nextRound = has("round") ? c.round + 1 : null;
    d.pairSet = !!c.doing;
    d.nextSet = !!c.next;
    d.pairKept = !!c.doing && c.doing === c.prevDoing;
    d.pairAdvanced = !!c.doing && !!c.prevNext && c.doing === c.prevNext;
    d.pairNew = !!c.doing && !!c.prevDoing && !d.pairKept && !d.pairAdvanced;
    d.sameNext = !!c.next && c.next === c.prevNext;

    // The round against its clock: ended early, on time, or ran long through snoozes.
    d.early = has("elapsed") && has("R") && c.elapsed < c.R - 30;
    d.veryEarly = has("elapsed") && has("R") && c.elapsed < c.R / 2;
    d.onTime = has("elapsed") && has("R") && Math.abs(c.elapsed - c.R) <= 30;
    d.ranLong = has("elapsed") && has("R") && c.elapsed > c.R + 30;
    d.overBy = d.ranLong ? c.elapsed - c.R : null;

    // Reminders: where this one sits in the run of r.
    d.lastReminder = has("reminderCount") && has("reminderIndex") && c.reminderIndex === c.reminderCount - 1;
    d.firstReminder = has("reminderIndex") && c.reminderIndex === 0;
    d.halfway = d.firstReminder && has("R") && has("remaining") && Math.abs(c.remaining - c.R / 2) < 1;
    d.remindersAfter = has("reminderCount") && has("reminderIndex") ? c.reminderCount - 1 - c.reminderIndex : null;
    d.reminderTimes = has("q") && has("Zmax") ? (function () { var a = []; for (var i = c.Zmax - 1; i >= 0; i--) a.push(c.q * Math.pow(2, i)); return a; })() : null;
    d.usedShare = has("R") && has("remaining") && c.R > 0 ? 1 - c.remaining / c.R : null;

    // The check-up formula, §6.2: q · 2^(z+1) ÷ (x+1).
    d.checkupMax = has("q") && has("z") ? c.q * Math.pow(2, c.z + 1) : null;        // with nothing cleared
    d.checkupSaved = d.checkupMax != null && has("statusLen") && has("x") && c.x > 0 ? d.checkupMax - c.statusLen : null;
    d.checkupNextSnooze = has("q") && has("z") ? c.q * Math.pow(2, c.z + 2) : null; // if B snoozes once more
    d.longCheckup = has("statusLen") && has("Lb") && c.statusLen >= c.Lb;
    d.cleared = has("x") ? c.x : null;
    d.clearedNone = d.cleared === 0;
    d.clearedMany = d.cleared != null && d.cleared >= 2;

    // The sitting clock against its limit, §6.6.2.
    d.untilBreak = has("seated") && has("Ls") ? Math.max(0, c.Ls - c.seated) : null;
    d.breakNext = has("seated") && has("Ls") && has("R") && c.seated + c.R > c.Ls;
    d.breakAfterNext = has("seated") && has("Ls") && has("R") && !d.breakNext && c.seated + 2 * c.R > c.Ls;
    d.seatedLong = has("seated") && has("Ls") && c.seated >= c.Ls / 2;
    d.seatedFresh = has("seated") && c.seated < 60;

    // The diff, grouped by what happened to each step.
    var diff = Array.isArray(c.diff) ? c.diff.filter(function (l) { return l && l.length >= 3 && l[1] !== "new"; }) : [];
    var g = { done: [], blocked: [], unblocked: [], crossed: [], moved: [] };
    diff.forEach(function (l) {
      if (l[2] === "done") g.done.push(l[0]);
      else if (l[2] === "blocked") g.blocked.push(l[0]);
      else if (l[1] === "blocked" && l[2] === "open") g.unblocked.push(l[0]);
      else if (l[2] === "crossed" || l[2] === "crossed_out") g.crossed.push(l[0]);
      else g.moved.push(l);
    });
    d.diffGroups = g;
    d.diffCount = diff.length;
    d.newBlocked = g.blocked.length;
    d.newDone = g.done.length;

    // The model's part this round.
    d.proposals = c.held && num(c.held.proposals) ? c.held.proposals : 0;
    d.modelSpoke = !!(c.held && (c.held.say || d.proposals > 0));
    d.modelSilent = c.held === null;

    // Extras, when a caller supplies them.
    d.staleCount = Array.isArray(c.stale) ? c.stale.length : null;
    d.openLeft = num(c.openCount) ? c.openCount : null;
    d.allDone = num(c.doneCount) && num(c.totalSteps) && c.totalSteps > 0 && c.doneCount === c.totalSteps;
    d.dayPart = num(c.hour) ? (c.hour < 5 ? "night" : c.hour < 12 ? "morning" : c.hour < 17 ? "afternoon" : c.hour < 22 ? "evening" : "night") : null;
    d.longFreeze = num(c.freeze) && has("R") && c.freeze > c.R;
    return d;
  }

  /* ---------- the diff, spoken ----------
   * fixed: the engine's line format, one change per clause, unchanged from before.
   * varied: the same changes grouped by outcome, names and states intact.
   */
  function diffLines(c) {
    return (c.diff || []).filter(function (l) { return l[1] !== "new"; })
      .map(function (l) { return l[0] + " " + STATE_WORD[l[1]] + " → " + STATE_WORD[l[2]]; });
  }
  function diffSpoken(d) {
    var g = d.diffGroups, out = [];
    if (g.done.length) out.push("Done: " + list(g.done) + ".");
    if (g.blocked.length) out.push((g.blocked.length === 1 ? "Newly blocked: " : "Blocked now: ") + list(g.blocked) + ".");
    if (g.unblocked.length) out.push("Unblocked: " + list(g.unblocked) + ".");
    if (g.crossed.length) out.push("Crossed out: " + list(g.crossed) + ".");
    g.moved.forEach(function (l) { out.push(l[0] + " " + STATE_WORD[l[1]] + " → " + STATE_WORD[l[2]] + "."); });
    return out.join(" ");
  }

  /* ---------- the table ----------
   * Each trigger is a list. Index 0 is the spec text and has no guard; the rest may guard
   * on the enriched context with `when`. A variant that needs a field the context lacks
   * simply does not apply. Every guard reads derived fields, so a guard is a sentence
   * about B's situation, not a null check.
   */
  function V(say, when) { return { say: say, when: when }; }
  var has = function () { var ks = arguments; return function (c) { for (var i = 0; i < ks.length; i++) if (c[ks[i]] == null || c[ks[i]] === "") return false; return true; }; };
  function all() { var fs = arguments; return function (c) { for (var i = 0; i < fs.length; i++) if (!fs[i](c)) return false; return true; }; }
  function is(k) { return function (c) { return !!c[k]; }; }
  function not(k) { return function (c) { return !c[k]; }; }

  var T = {
    session_start: [
      V(function () { return "Session open. Choose Doing and Next."; }),
      V(function (c) { return "Session open. Choose Doing and Next; " + or(c.aName, "A") + " will ask you to start round 1."; }),
      V(function (c) { return "Session open: " + n(c.openCount, "open step", "open steps") + ". Choose Doing and Next."; }, has("openCount")),
      V(function (c) { return "Session open. Nothing runs until " + or(c.aName, "A") + " asks you to start."; }),
      V(function (c) { return "Session open. Seated " + fmt(c.seated) + " already, so the first break comes early. Choose Doing and Next."; }, all(has("seated"), is("seatedLong"))),
      V(function (c) { return "Session open, one open step: " + c.doing + ". Choose it as Doing and " + or(c.aName, "A") + " will ask you to start."; }, function (c) { return c.openCount === 1 && !!c.doing; }),
      V(function (c) { return "Good " + c.dayPart + ". Session open. Choose Doing and Next."; }, all(has("dayPart"), function (c) { return c.dayPart !== "night"; }))
    ],

    round_start: [
      V(function (c) { return "Round " + c.round + ". " + or(c.doing, "nothing") + " doing, " + or(c.next, "nothing") + " next. " + fmt(c.R) + ", starting now."; }),
      V(function (c) { return "Round " + c.round + ", as planned: " + c.doing + " doing, " + or(c.next, "nothing") + " next. " + fmt(c.R) + "."; },
        all(not("firstRound"), is("pairAdvanced"))),
      V(function (c) { return "Round " + c.round + ". " + c.doing + " first, then " + c.next + ". " + fmt(c.R) + " on the clock."; }, has("doing", "next")),
      V(function (c) { return "Round " + c.round + ". " + c.doing + " doing, nothing next yet. " + fmt(c.R) + ", starting now."; },
        all(is("pairSet"), not("nextSet"))),
      V(function (c) { return "Round 1. " + c.doing + " doing, " + or(c.next, "nothing") + " next. " + fmt(c.R) + ". First reminder at " + fmt(c.R / 2) + " left."; },
        all(is("firstRound"), is("pairSet"))),
      V(function (c) { return "Round " + c.round + ". Still on " + c.doing + ", " + or(c.next, "nothing") + " next. " + fmt(c.R) + ", starting now."; },
        all(not("firstRound"), is("pairKept"))),
      V(function (c) { return "Round " + c.round + ". " + c.prevNext + " moves up: " + c.doing + " doing, " + or(c.next, "nothing") + " next. " + fmt(c.R) + "."; },
        all(not("firstRound"), is("pairAdvanced"), has("prevNext"))),
      V(function (c) { return "Round " + c.round + ", a new pair: " + c.doing + " doing, " + or(c.next, "nothing") + " next. " + fmt(c.R) + ", starting now."; },
        is("pairNew")),
      V(function (c) { return "Round " + c.round + ", the last before a break. " + c.doing + " doing, " + or(c.next, "nothing") + " next. " + fmt(c.R) + "."; },
        all(is("pairSet"), is("breakAfterNext"))),
      V(function (c) { return "Round " + c.round + ". " + c.doing + " doing, " + or(c.next, "nothing") + " next. " + fmt(c.R) + "; reminders at " + list(c.reminderTimes.map(fmt)) + " left."; },
        all(is("pairSet"), has("reminderTimes"), function (c) { return c.reminderTimes.length <= 4; })),
      V(function (c) { return "The " + ordinal(c.round) + " round. " + c.doing + " doing, " + or(c.next, "nothing") + " next. " + fmt(c.R) + ", starting now."; },
        all(is("pairSet"), function (c) { return c.round >= 2 && c.round <= 12; }))
    ],

    reminder: [
      V(function (c) { return fmt(c.remaining) + " left."; }),
      V(function (c) { return fmt(c.remaining) + " left, halfway."; }, is("halfway")),
      V(function (c) { return "Last reminder: " + fmt(c.remaining) + ". Get ready to stop."; }, is("lastReminder")),
      V(function (c) { return fmt(c.remaining) + " to go."; }, function (c) { return c.reminderCount == null || !c.lastReminder; }),
      V(function (c) { return fmt(c.remaining) + " left on " + c.doing + "."; }, all(has("doing"), not("lastReminder"))),
      V(function (c) { return fmt(c.remaining) + " left. Wrap up " + c.doing + "."; }, all(has("doing"), is("lastReminder"))),
      V(function (c) { return "Halfway: " + fmt(c.remaining) + " left, " + fmt(c.R - c.remaining) + " gone."; }, is("halfway")),
      V(function (c) { return fmt(c.remaining) + " left, " + n(c.remindersAfter, "more reminder", "more reminders") + " after this."; },
        function (c) { return c.remindersAfter != null && c.remindersAfter > 0; }),
      V(function (c) { return "Last reminder: " + fmt(c.remaining) + ". " + n(c.snoozesLeft, "snooze", "snoozes") + " at the end if you need one."; },
        all(is("lastReminder"), function (c) { return c.snoozesLeft != null && c.snoozesLeft > 0; })),
      V(function (c) { return "Last reminder: " + fmt(c.remaining) + ", and no snoozes left after this."; },
        all(is("lastReminder"), function (c) { return c.snoozesLeft === 0; }))
    ],

    time_up: [
      V(function () { return "Time's up."; }),
      V(function (c) { return "Time's up. " + n(c.Zmax - c.z, "snooze", "snoozes") + " left, " + fmt(c.G) + " to decide."; },
        all(has("Zmax", "z", "G"), function (c) { return c.snoozesLeft > 0; })),
      V(function (c) { return "Time's up. No snoozes left: stop."; }, function (c) { return c.snoozesLeft === 0; }),
      V(function (c) { return "Snooze over. Time's up."; }, is("snoozed")),
      V(function (c) { return "Time's up. Go to check-up, or snooze: " + n(c.snoozesLeft, "snooze", "snoozes") + " left, " + fmt(c.q) + " each."; },
        all(has("q"), function (c) { return c.snoozesLeft > 0; })),
      V(function (c) { return "Snooze " + c.z + " over. Time's up, " + n(c.snoozesLeft, "snooze", "snoozes") + " left."; },
        all(is("snoozed"), function (c) { return c.snoozesLeft > 0; })),
      V(function (c) { return "Time's up on round " + c.round + ". " + c.doing + " waits where it is."; }, has("round", "doing")),
      V(function (c) { return "Time's up. The last snooze is spent, so Go is the only way on."; }, is("lastSnooze")),
      V(function (c) { return "Time's up, round " + c.round + ". Seated " + fmt(c.seated) + "; the sitting clock keeps running while you decide."; },
        all(has("round", "seated"), is("seatedLong")))
    ],

    snooze_accepted: [
      V(function (c) { return "Snooze " + c.z + " of " + c.Zmax + ". " + fmt(c.q) + "."; }),
      V(function (c) { return "Snooze " + c.z + " of " + c.Zmax + ", the last one. " + fmt(c.q) + "."; }, all(has("z", "Zmax"), function (c) { return c.z === c.Zmax; })),
      V(function (c) { return "Snooze " + c.z + " of " + c.Zmax + ": " + fmt(c.q) + " more. Away time doubles."; }, all(has("z", "Zmax"), function (c) { return c.z < c.Zmax; })),
      V(function (c) { return "Snooze " + c.z + " of " + c.Zmax + ". " + fmt(c.q) + " more on " + c.doing + "."; }, has("doing")),
      V(function (c) { return "Snooze " + c.z + " of " + c.Zmax + ". " + fmt(c.q) + "; the check-up after is up to " + fmt(c.checkupMax) + ", less for every step cleared."; }, has("checkupMax")),
      V(function (c) { return "Snooze " + c.z + " of " + c.Zmax + ", " + fmt(c.q) + ". " + n(c.snoozesLeft, "snooze", "snoozes") + " after this one."; }, function (c) { return c.snoozesLeft > 0; }),
      V(function (c) { return "Last snooze, " + c.z + " of " + c.Zmax + ": " + fmt(c.q) + ", then check-up for certain."; }, all(has("z", "Zmax"), function (c) { return c.z === c.Zmax; }))
    ],

    snooze_refused: [
      V(function () { return "No snoozes left. Stop."; }),
      V(function (c) { return "All " + c.Zmax + " snoozes used. Stop."; }, has("Zmax")),
      V(function (c) { return "All " + c.Zmax + " snoozes used this round. Check-up is next."; }, has("Zmax"))
    ],

    stop: [
      V(function () { return "Stop."; }),
      V(function () { return "No answer. Stop."; }, function (c) { return c.reason === "grace"; }),
      V(function (c) { return "Stop. Round over at " + fmt(c.elapsed) + "."; }, function (c) { return c.reason !== "grace" && c.elapsed != null; }),
      V(function (c) { return "Stop. Round " + c.round + " over at " + fmt(c.elapsed) + ", " + fmt(c.overBy) + " past the clock."; },
        all(has("round"), is("ranLong"), function (c) { return c.reason !== "grace"; }))
    ],

    late_snooze: [
      V(function () { return "Too late. Stop."; }),
      V(function (c) { return "The " + fmt(c.G) + " window has passed. Stop."; }, has("G"))
    ],

    status_start: [
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Status, " + fmt(c.statusLen) + "."; }),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Nothing cleared. Status, " + fmt(c.statusLen) + "."; }, is("clearedNone")),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ", " + n(c.x, "step", "steps") + " cleared. Status, " + fmt(c.statusLen) + "."; }, is("clearedMany")),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Status, " + fmt(c.statusLen) + ": long enough to count as moving."; }, is("longCheckup")),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". " + n(c.z, "snooze", "snoozes") + ", so status is " + fmt(c.statusLen) + "."; }, is("snoozed")),
      V(function (c) { return "Round over early, at " + fmt(c.elapsed) + ". Status, " + fmt(c.statusLen) + "."; }, all(is("early"), not("snoozed"))),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ", one step cleared: " + list(c.diffGroups.done) + ". Status, " + fmt(c.statusLen) + "."; },
        function (c) { return c.cleared === 1 && c.newDone === 1; }),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Clearing " + n(c.x, "step", "steps") + " cut status from " + fmt(c.checkupMax) + " to " + fmt(c.statusLen) + "."; },
        function (c) { return c.checkupSaved != null && c.checkupSaved >= 15; })
    ],

    strategy_start: [
      V(function (c) { return "Strategy, " + fmt(c.q) + "."; }),
      V(function (c) { return "Strategy, " + fmt(c.q) + ". The model has " + n(c.held.proposals, "proposal", "proposals") + "."; }, function (c) { return c.proposals > 0; }),
      V(function (c) { return "Strategy, " + fmt(c.q) + ". The model has a note, no proposals."; }, function (c) { return c.held && c.held.say && !c.proposals; }),
      V(function (c) { return "Strategy, " + fmt(c.q) + ". Nothing from the model this round."; }, is("modelSilent")),
      V(function (c) { return "Strategy, " + fmt(c.q) + ". Choose nothing and " + c.prevDoing + " stays doing."; }, has("prevDoing")),
      V(function (c) { return "Strategy, " + fmt(c.q) + ". " + c.prevDoing + " is done; pick what comes after " + or(c.prevNext, "it") + "."; },
        function (c) { return !!c.prevDoing && c.diffGroups.done.indexOf(c.prevDoing) >= 0; }),
      V(function (c) { return "Strategy, " + fmt(c.q) + ", and a break follows it: seated " + fmt(c.seated) + "."; }, all(has("seated"), is("breakNext")))
    ],

    auto_commit: [
      V(function (c) { return "No choice made. " + or(c.doing, "nothing") + " doing, " + or(c.next, "nothing") + " next."; }),
      V(function (c) { return "No choice made. Keeping " + c.doing + " doing, " + or(c.next, "nothing") + " next."; }, is("pairKept")),
      V(function (c) { return "No choice made. " + c.doing + " moves up to doing, " + or(c.next, "nothing") + " next."; }, is("pairAdvanced")),
      V(function (c) { return "No choice made, so the plan filled it: " + c.doing + " doing, " + or(c.next, "nothing") + " next."; }, is("pairNew")),
      V(function (c) { return "No choice made. " + c.doing + " doing, " + c.next + " next, as before."; }, all(is("pairKept"), is("sameNext")))
    ],

    promote_next: [
      V(function (c) { return "Now doing " + c.doing + "."; }),
      V(function (c) { return "Now doing " + c.doing + ". Next is open."; }),
      V(function (c) { return c.prevDoing + " done. Now doing " + c.doing + "."; }, has("prevDoing")),
      V(function (c) { return c.prevDoing + " done. " + c.doing + " moves up; pick a new Next at the plan."; }, all(has("prevDoing"), not("nextSet"))),
      V(function (c) { return "Now doing " + c.doing + ", with " + c.next + " next."; }, has("next"))
    ],

    no_doing: [
      V(function () { return "No doing node."; }),
      V(function () { return "No doing node. Finish the round when you are ready."; }),
      V(function (c) { return "No doing node; " + c.next + " is next but nothing is doing. Finish the round when you are ready."; }, has("next")),
      V(function (c) { return "No doing node, " + n(c.openCount, "open step", "open steps") + " to choose from at the plan."; }, function (c) { return c.openLeft != null && c.openLeft > 0; })
    ],

    break_start: [
      V(function (c) { return "Seated " + fmt(c.seated) + ". Movement break, " + fmt(c.Lb) + "."; }),
      V(function (c) { return "Seated " + fmt(c.seated) + "; another round would pass " + fmt(c.Ls) + ". Movement break, " + fmt(c.Lb) + "."; }, has("Ls")),
      V(function (c) { return "Seated " + fmt(c.seated) + ". Stand up: " + fmt(c.Lb) + " away, the plan is locked."; }),
      V(function (c) { return "Seated " + fmt(c.seated) + ", past the " + fmt(c.Ls) + " limit. Movement break, " + fmt(c.Lb) + "."; }, all(has("Ls"), function (c) { return c.seated >= c.Ls; })),
      V(function (c) { return "Seated " + fmt(c.seated) + ". Movement break, " + fmt(c.Lb) + "; round " + c.nextRound + " waits behind it with " + c.doing + " doing."; }, has("nextRound", "doing")),
      V(function (c) { return "Seated " + fmt(c.seated) + " across " + n(c.round, "round", "rounds") + ". Movement break, " + fmt(c.Lb) + "."; }, function (c) { return c.round >= 2; })
    ],

    continue: [
      V(function (c) { return "Seated " + fmt(c.seated) + ". Continue."; }),
      V(function (c) { return "Seated " + fmt(c.seated) + ". Continue; this is the last round before a break."; }, is("breakAfterNext")),
      V(function (c) { return "Seated " + fmt(c.seated) + ", " + fmt(c.untilBreak) + " before a break. Continue."; }, all(has("R", "untilBreak"), function (c) { return c.seated + 2 * c.R <= c.Ls; })),
      V(function (c) { return "Seated " + fmt(c.seated) + ". Continue to round " + c.nextRound + "."; }, has("nextRound")),
      V(function (c) { return "Seated " + fmt(c.seated) + ". Continue; a break would be " + fmt(c.Lb) + " when it comes."; }, all(has("Lb"), is("seatedFresh"))),
      V(function (c) { return "Seated " + fmt(c.seated) + ", about " + Math.round(100 * c.seated / c.Ls) + "% of the sitting limit. Continue."; },
        all(has("Ls"), function (c) { return c.seated > 0 && c.seated < c.Ls; }))
    ],

    // Planning has run out and holds at 0:00: A asks B to start the next round.
    planning_over: [
      V(function (c) { return "Planning time is up. " + or(c.aName, "A") + " asks you to start round " + (c.round + 1) + "."; }),
      V(function (c) { return "Planning over. " + or(c.doing, "Nothing") + " doing, " + or(c.next, "nothing") + " next, unless you change it. " + or(c.aName, "A") + " asks you to start round " + (c.round + 1) + "."; }),
      V(function (c) { return "Planning over. No pair chosen: round " + (c.round + 1) + " keeps " + c.doing + " doing when you start it."; }, all(is("pairSet"), not("chosen"))),
      V(function (c) { return "Planning over. Your pair holds: " + c.doing + " doing, " + or(c.next, "nothing") + " next. " + or(c.aName, "A") + " asks you to start round " + (c.round + 1) + "."; }, all(is("pairSet"), is("chosen")))
    ],

    break_end: [
      V(function () { return "Sitting clock reset."; }),
      V(function (c) { return "Break over. Sitting clock reset. Round " + c.round + " next."; }, has("round")),
      V(function (c) { return "Break over, sitting clock at zero. Round " + c.round + ": " + c.doing + " doing when you press Go."; }, has("round", "doing")),
      V(function (c) { return "Sitting clock reset: " + fmt(c.Ls) + " of seated time ahead before the next break."; }, has("Ls"))
    ],

    not_available: [
      V(function (c) { return c.message || "Not available now."; })
    ],

    /* ---------- 2.1: the handshake model ----------
     * The request screen's lines (addendum §5, B's screen guide §3.3) and the phases the addendum
     * renames: check-up for status, plan for strategy. The request lines have only variant 0: the
     * guide fixes their wording, and they take no tail.
     *   what                      for request_waiting, e.g. "moving on to check-up"
     *   toPhase, n, len           for request_approved: work | snooze | check-up | plan | break | end
     *   reason                    for request_refused
     */
    request_waiting: [
      V(function (c) { return "Waiting for " + or(c.aName, "A") + " to approve " + or(c.what, "this") + "."; })
    ],

    request_approved: [
      V(function (c) {
        switch (c.toPhase) {
          case "work": return "Round " + c.n + ": " + or(c.doing, "nothing") + (c.next ? ", then " + c.next : "") + ". " + fmt(c.R) + ".";
          case "snooze": return "Snooze " + c.n + " of " + c.Zmax + ". " + fmt(c.q) + ".";
          case "check-up": return "Check-up, " + fmt(c.len) + ". Step away from the desk.";
          case "plan": return "Plan round " + c.n + ". " + fmt(c.q) + ".";
          case "break": return "Movement break, " + fmt(c.Lb) + ". Stand up and move.";
          default: return "End the session.";
        }
      })
    ],

    request_refused: [
      V(function (c) { return c.reason || or(c.aName, "A") + " said no."; })
    ],

    checkup_start: [
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Check-up, " + fmt(c.statusLen) + "."; }),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Nothing cleared. Check-up, " + fmt(c.statusLen) + "."; }, is("clearedNone")),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ", " + n(c.x, "step", "steps") + " cleared. Check-up, " + fmt(c.statusLen) + "."; }, is("clearedMany")),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Check-up, " + fmt(c.statusLen) + ": long enough to count as moving."; }, is("longCheckup")),
      V(function (c) { return "Round " + c.round + " over at " + fmt(c.elapsed) + ". Check-up, " + fmt(c.statusLen) + "; nothing to do in it but step away."; }, has("round")),
      V(function (c) { return "Round over early, at " + fmt(c.elapsed) + ". Check-up, " + fmt(c.statusLen) + "."; }, all(is("early"), not("snoozed"))),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + " after " + n(c.z, "snooze", "snoozes") + ". Check-up, " + fmt(c.statusLen) + "."; }, is("snoozed")),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ", one step cleared: " + list(c.diffGroups.done) + ". Check-up, " + fmt(c.statusLen) + "."; },
        function (c) { return c.cleared === 1 && c.newDone === 1; }),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Clearing " + n(c.x, "step", "steps") + " cut the check-up from " + fmt(c.checkupMax) + " to " + fmt(c.statusLen) + "."; },
        function (c) { return c.checkupSaved != null && c.checkupSaved >= 15; }),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Nothing cleared and " + n(c.z, "snooze", "snoozes") + ": check-up is " + fmt(c.statusLen) + "."; }, all(is("clearedNone"), is("snoozed"))),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Check-up, " + fmt(c.statusLen) + ", and the sitting clock resets with it."; }, is("longCheckup")),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". " + c.doing + " is still doing. Check-up, " + fmt(c.statusLen) + "."; },
        all(has("doing"), function (c) { return c.diffCount === 0; }))
    ],

    plan_start: [
      V(function (c) { return "Plan round " + (c.round + 1) + ", " + fmt(c.q) + "."; }),
      V(function (c) { return "Plan round " + (c.round + 1) + ", " + fmt(c.q) + ". The model has " + n(c.held.proposals, "proposal", "proposals") + "."; }, function (c) { return c.proposals > 0; }),
      V(function (c) { return "Plan round " + (c.round + 1) + ", " + fmt(c.q) + ". Nothing from the model this round."; }, is("modelSilent")),
      V(function (c) { return "Plan round " + (c.round + 1) + ", " + fmt(c.q) + ". The model has a note, no proposals."; }, function (c) { return c.held && c.held.say && !c.proposals; }),
      V(function (c) { return "Plan round " + (c.round + 1) + ", " + fmt(c.q) + ". Choose nothing and " + c.doing + " stays doing."; }, has("doing")),
      V(function (c) { return "Plan round " + (c.round + 1) + ", " + fmt(c.q) + ". " + c.doing + " is still doing; pick a Next or carry on with it alone."; }, all(has("doing"), not("nextSet"))),
      V(function (c) { return "Plan round " + (c.round + 1) + ", " + fmt(c.q) + ". Doing is empty: choose one, or the plan picks for you at the end."; }, not("pairSet")),
      V(function (c) { return "Plan round " + (c.round + 1) + ", " + fmt(c.q) + ", then a break: seated " + fmt(c.seated) + "."; }, all(has("seated"), is("breakNext"))),
      V(function (c) { return "Plan round " + (c.round + 1) + ", " + fmt(c.q) + ". " + n(c.staleCount, "step", "steps") + " untouched for days: " + list(c.stale) + "."; },
        function (c) { return c.staleCount != null && c.staleCount > 0 && c.staleCount <= 3; })
    ],

    plan_over: [
      V(function (c) { return "Planning over. Start round " + (c.round + 1) + "?"; }),
      V(function (c) { return "Planning over. Keeping " + c.doing + " doing, " + or(c.next, "nothing") + " next."; }, all(is("pairSet"), not("chosen"))),
      V(function (c) { return "Planning over. " + c.doing + " doing, " + or(c.next, "nothing") + " next. Start round " + (c.round + 1) + "?"; }, all(is("pairSet"), is("chosen"))),
      V(function (c) { return "Planning over, nothing chosen: the plan filled it with " + c.doing + " doing, " + or(c.next, "nothing") + " next."; }, all(is("pairSet"), not("chosen"), is("pairNew"))),
      V(function (c) { return "Planning over. " + c.doing + " doing, " + c.next + " next; a break comes before round " + (c.round + 1) + "."; }, all(has("doing", "next"), is("breakNext")))
    ]
  };

  /* ---------- the tails ----------
   * One extra sentence about what the numbers mean for B right now. Each is guarded like a
   * variant; none repeats the sentence's own facts, and none applies in the fixed voice.
   * A trigger absent here, or an empty list, takes no tail. The request lines are absent on
   * purpose: the guide fixes their wording.
   */
  var TAILS = {
    session_start: [
      V(function (c) { return "Rounds are " + fmt(c.R) + " with " + n(c.Zmax, "reminder", "reminders") + "."; }, has("R", "Zmax")),
      V(function (c) { return "Seated " + fmt(c.seated) + " already; the sitting clock runs from here."; }, all(has("seated"), function (c) { return c.seated >= 60; })),
      V(function (c) { return "The first round starts when " + or(c.aName, "A") + " asks and you press Go."; })
    ],
    round_start: [
      V(function (c) { return "A break comes after this one: seated " + fmt(c.seated) + "."; }, all(has("seated"), is("breakAfterNext"))),
      V(function (c) { return fmt(c.untilBreak) + " of sitting time left before a break."; }, all(has("untilBreak"), not("breakAfterNext"), function (c) { return c.untilBreak > 0; })),
      V(function (c) { return "Reminders at " + list(c.reminderTimes.map(fmt)) + " left; the last one covers the screen."; }, all(has("reminderTimes"), function (c) { return c.reminderTimes.length <= 4; })),
      V(function (c) { return "Next is open; choose one at the plan."; }, all(is("pairSet"), not("nextSet"))),
      V(function (c) { return n(c.Zmax, "snooze", "snoozes") + " of " + fmt(c.q) + " if you need them at the end."; }, has("Zmax", "q")),
      V(function (c) { return "Mark steps done as you clear them: each one shortens the check-up."; }, has("q")),
      V(function (c) { return c.prevDoing + " is done; this round moves on from it."; }, all(has("prevDoing"), is("pairAdvanced")))
    ],
    reminder: [
      V(function (c) { return "Then " + c.next + "."; }, all(has("next"), is("lastReminder"))),
      V(function (c) { return "The clock keeps running; Go or Snooze when it ends."; }, is("lastReminder")),
      V(function (c) { return "A good moment to mark anything finished as done."; }, is("halfway"))
    ],
    time_up: [
      V(function (c) { return "Snoozing doubles the check-up; clearing steps shortens it."; }, function (c) { return c.snoozesLeft > 0; }),
      V(function (c) { return "Check-up follows: up to " + fmt(c.checkupMax) + ", less for every step cleared."; }, has("checkupMax")),
      V(function (c) { return "Take your time; nothing runs until you press Go."; }),
      V(function (c) { return "A break comes before the next round: seated " + fmt(c.seated) + "."; }, all(has("seated"), is("breakNext"))),
      V(function (c) { return "Round " + c.round + " ran " + fmt(c.elapsed) + " with the snoozes."; }, all(has("round"), is("snoozed"), is("ranLong")))
    ],
    snooze_accepted: [
      V(function (c) { return "Finish what is in your hands on " + c.doing + "."; }, has("doing")),
      V(function (c) { return "One more snooze and the check-up would be up to " + fmt(c.checkupNextSnooze) + "."; }, all(has("checkupNextSnooze"), function (c) { return c.snoozesLeft > 0; })),
      V(function (c) { return "This is the last one; the check-up comes after it."; }, is("lastSnooze")),
      V(function () { return "Each step marked done before it ends shortens the check-up."; })
    ],
    status_start: [
      V(function () { return "Step away from the desk; the plan is locked until it ends."; }),
      V(function (c) { return "Plan round " + c.nextRound + " follows, " + fmt(c.q) + "."; }, has("nextRound", "q")),
      V(function (c) { return "Without " + n(c.x, "cleared step", "cleared steps") + " it would have been " + fmt(c.checkupMax) + "."; }, function (c) { return c.checkupSaved != null && c.checkupSaved >= 15; }),
      V(function (c) { return "Then a movement break: seated " + fmt(c.seated) + "."; }, all(has("seated"), is("breakNext"), not("longCheckup")))
    ],
    checkup_start: [
      V(function () { return "Step away from the desk; the plan is locked until it ends."; }),
      V(function (c) { return "Plan round " + c.nextRound + " follows, " + fmt(c.q) + "."; }, has("nextRound", "q")),
      V(function (c) { return "Without " + n(c.x, "cleared step", "cleared steps") + " it would have been " + fmt(c.checkupMax) + "."; }, function (c) { return c.checkupSaved != null && c.checkupSaved >= 15; }),
      V(function (c) { return "Then a movement break: seated " + fmt(c.seated) + "."; }, all(has("seated"), is("breakNext"), not("longCheckup"))),
      V(function (c) { return "It counts as moving, so the sitting clock starts again from zero."; }, is("longCheckup")),
      V(function (c) { return "Seated " + fmt(c.seated) + "; " + fmt(c.untilBreak) + " to the sitting limit."; }, all(has("seated", "untilBreak"), not("longCheckup"), not("breakNext"), is("seatedLong"))),
      V(function (c) { return "Newly blocked: " + list(c.diffGroups.blocked) + ". Worth a look at the plan."; }, function (c) { return c.newBlocked > 0 && c.newBlocked <= 3; })
    ],
    strategy_start: [
      V(function (c) { return "Choose Doing and Next, or leave " + c.prevDoing + " where it is."; }, all(has("prevDoing"), not("pairSet"))),
      V(function (c) { return "A break comes before round " + c.nextRound + "."; }, all(has("nextRound"), is("breakNext")))
    ],
    plan_start: [
      V(function (c) { return "The board shows this round's changes; set the pair there."; }, function (c) { return c.diffCount > 0; }),
      V(function (c) { return "Read the model's " + n(c.proposals, "proposal", "proposals") + ", then choose; none of it moves on its own."; }, function (c) { return c.proposals > 0; }),
      V(function (c) { return "A break comes before round " + c.nextRound + ": seated " + fmt(c.seated) + "."; }, all(has("nextRound", "seated"), is("breakNext"))),
      V(function (c) { return "Round " + c.nextRound + " is the last before a break."; }, all(has("nextRound"), is("breakAfterNext"))),
      V(function (c) { return "Done this round: " + list(c.diffGroups.done) + "."; }, function (c) { return c.newDone > 0 && c.newDone <= 3; }),
      V(function (c) { return "Nothing was marked done this round; " + c.doing + " carries over."; }, all(has("doing"), is("clearedNone"))),
      V(function (c) { return "Leave it and the plan commits " + c.doing + " doing, " + or(c.next, "nothing") + " next at the end."; }, has("doing")),
      V(function (c) { return "Press Next phase when the pair is set; the clock stops at Go."; })
    ],
    plan_over: [
      V(function (c) { return "Round " + c.nextRound + " starts at your Go, " + fmt(c.R) + "."; }, all(has("nextRound", "R"), not("breakNext"))),
      V(function (c) { return "A movement break comes first: seated " + fmt(c.seated) + "."; }, all(has("seated"), is("breakNext"))),
      V(function (c) { return "Nothing runs until you press Go."; })
    ],
    auto_commit: [
      V(function (c) { return "Change it at the next plan if that is not what you want."; }),
      V(function (c) { return "Next is still open; the plan will ask again."; }, all(is("pairSet"), not("nextSet")))
    ],
    promote_next: [
      V(function (c) { return "Next is empty now; choose one at the plan."; }, not("nextSet")),
      V(function (c) { return "Still " + fmt(c.remaining) + " left in the round."; }, all(has("remaining"), function (c) { return c.remaining >= 60; }))
    ],
    no_doing: [
      V(function (c) { return "Choose a Doing at the plan and the next round has somewhere to go."; })
    ],
    break_start: [
      V(function (c) { return "Round " + c.nextRound + " follows the break."; }, has("nextRound")),
      V(function (c) { return "The pair is set: " + c.doing + " doing, " + or(c.next, "nothing") + " next."; }, has("doing")),
      V(function () { return "The sitting clock resets when the break ends."; }),
      V(function (c) { return "It ends on its own; policy refuses an early move out."; })
    ],
    continue: [
      V(function (c) { return "Round " + c.nextRound + ": " + c.doing + " doing, " + or(c.next, "nothing") + " next."; }, has("nextRound", "doing")),
      V(function (c) { return "Seated time keeps counting through the round."; }, is("seatedLong")),
      V(function (c) { return "A break would come after the next round."; }, is("breakAfterNext"))
    ],
    break_end: [
      V(function (c) { return c.doing + " doing, " + or(c.next, "nothing") + " next, " + fmt(c.R) + "."; }, has("doing", "R")),
      V(function () { return "Press Go when you are back at the desk."; })
    ],
    snooze_refused: [
      V(function (c) { return "Check-up is up to " + fmt(c.checkupMax) + " now, less for every step cleared."; }, has("checkupMax"))
    ],
    stop: [],
    late_snooze: [],
    planning_over: [
      V(function (c) { return "Round " + c.nextRound + " starts at your Go, " + fmt(c.R) + "."; }, has("nextRound", "R"))
    ]
  };

  /* ---------- API ---------- */
  function pick(list, ctx, first) {
    return list.filter(function (v, i) { return (first && i === 0) || !v.when || v.when(ctx); });
  }
  function applicable(trigger, ctx) {
    var list = T[trigger];
    if (!list) throw new Error("announce: unknown trigger " + trigger);
    return pick(list, enrich(ctx), true);
  }
  function applicableTails(trigger, ctx) {
    return pick(TAILS[trigger] || [], enrich(ctx), false);
  }
  function variants(trigger, ctx) {
    var d = enrich(ctx);
    return applicable(trigger, ctx).map(function (v) { return v.say(d); });
  }
  function tails(trigger, ctx) {
    var d = enrich(ctx);
    return applicableTails(trigger, ctx).map(function (v) { return v.say(d); });
  }
  // opts.voice: "fixed" (spec text only) | "varied" (a variant, and a tail more often than not).
  // opts.tail: false keeps the varied voice to one sentence. opts.seed overrides the hash input.
  function announce(trigger, ctx, opts) {
    ctx = ctx || {}; opts = opts || {};
    var d = enrich(ctx), varied = opts.voice === "varied";
    var list = applicable(trigger, ctx);
    var key = opts.seed != null ? String(opts.seed) : [ctx.sessionId || "", ctx.round || 0, trigger, ctx.reminderIndex || 0, ctx.z || 0].join("|");
    var i = varied && list.length > 1 ? hash(key) % list.length : 0;
    var text = list[i].say(d), tail = -1;
    if (trigger === "status_start" || trigger === "checkup_start") {
      if (varied) { var s = diffSpoken(d); if (s) text += " " + s; }
      else { var l = diffLines(ctx); if (l.length) text += " " + l.join(", ") + "."; }
    }
    if (varied && opts.tail !== false) {
      // One slot in the draw is "no tail", so the voice keeps some short lines.
      var ts = applicableTails(trigger, ctx);
      if (ts.length) {
        var j = hash(key + "|tail") % (ts.length + 1);
        if (j < ts.length) { var extra = ts[j].say(d); if (text.indexOf(extra) < 0) { tail = j; text += " " + extra; } }
      }
    }
    return { text: text, variant: i, tail: tail, key: key };
  }

  return { announce: announce, variants: variants, tails: tails, enrich: enrich, TRIGGERS: Object.keys(T), fmt: fmt, digits: digits };
});
