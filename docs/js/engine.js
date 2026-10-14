/* engine.js: the session engine: phases, clocks, Go, and the sit check. */
"use strict";
// ----- phases and clocks -----
var PHASE = { idle: "Idle", work: "Work", snooze: "Snooze", status: "Check-up", strategy: "Plan", "break": "Break" };
var TO_PHASE = { work: "work", snooze: "snooze", status: "check-up", strategy: "plan", "break": "break", end: "end" };
function running() { return !!S.state && S.state !== "idle" && !S.frozen; }
function phaseLen() {
  switch (S.state) { case "work": return CFG.R; case "snooze": return qU(); case "status": return S.statusLen;
    case "strategy": return qU(); case "break": return CFG.Lb; }
  return 0;
}
function left() { return running() ? Math.max(0, S.phaseEnd - S.T) : 0; }
function enter(st, len) {
  S.state = st; S.frozen = false; S.phaseStart = S.T; S.phaseEnd = S.T + (len || 0); S.lastRem = null; S.strip = null; S.halfFired = false;
  pushA("phase", { phase: PHASE[st], length: len || 0, ends_at: len ? new Date(S.W + len * 1000).toISOString() : null, doing: title(slot("doing")) || null, next: title(slot("next")) || null, seated: Math.round(S.seated) });
}
// Every timed phase gets a reminder at half its length, whatever the length: the round has it from
// the reminder arithmetic (q·2^(r−1) = R/2); the snooze, the check-up, the plan and the break get it here.
function halfLine(len) { return "half-time reminder at " + digits(len / 2) + " left"; }
function snap() { var o = {}; for (var k in S.nodes) o[k] = displayStatus(k); return o; }
function sitBreak() { return S.seated + CFG.R > CFG.Ls; }
function seatedMin() { return Math.floor(S.seated / 60) + " min"; }
// x comes from the log (§6.6.1): steps marked done between this round's Go and the Go that ended it.
function roundCleared() { var x = 0; for (var k in S.doneAt) if (S.nodes[k] && S.doneAt[k] >= S.roundStart && finished(k)) x++; return x; }

function startSession() {
  if (S.state) return;
  if (nextCfg) { CFG = nextCfg; nextCfg = null; }
  S.round = 0; S.z = 0; S.x = null; S.held = null; S.turn = null; S.nudged = false; S.diff = []; S.rounds = {};
  S.seated = seatStart; S.req = null; S.sys = null; S.prevPair = { d: null, n: null };
  S.sessionId = "s" + (++sessionSeq) + "-" + Math.floor(S.W / 1000);
  ev("man", "engine", "info", "open session", "seated " + fmt(S.seated) + ", R " + fmt(CFG.R) + ", r " + CFG.r + ", Ls " + fmt(CFG.Ls) + ", Lb " + fmt(CFG.Lb) + "\nA: " + (UI.auto ? "policy (autopilot)" : "a person"));
  enter("idle");
  say("Session open.");
  pushA("session", { event: "open", R: CFG.R, r: CFG.r, Ls: CFG.Ls, Lb: CFG.Lb, auto: UI.auto });
}
function endSession() {
  if (!S.state) return;
  closeReq(S.req, "overtaken"); closeReq(S.sys, "overtaken");
  ev("engine", "timers", "info", "cancel timers", "");
  say("Session ended.", "rounds " + S.round + ", requests " + S.requests.length);
  pushA("session", { event: "end", rounds: S.round, requests: S.requests.length });
  S.state = null; S.frozen = false; S.req = null; S.sys = null; S.held = null; S.turn = null; S.picks = { d: null, n: null };
  S.diff = []; S.lastRem = null; S.strip = null;
  UI.intake = { stage: firstStage(), ids: [] }; UI.gridRound = 0;
}
function startRound() {
  S.round += 1; S.roundStart = S.T; S.roundRun = 0; S.z = 0; S.x = null; S.remFired = 0; S.picks = { d: null, n: null }; S.diff = []; S.held = null;
  S.rounds[S.round] = { start: snap(), end: null };
  enter("work", CFG.R);
  ev("engine", "timers", "info", "schedule " + CFG.r + " reminders and the round end", "reminders at " + remTimes().map(digits).join(", ") + " left\nround end " + stamp(S.W + CFG.R * 1000));
  speak("round_start", {}, "Round " + S.round + ". " + (title(slot("doing")) || "nothing") + " doing, " + (title(slot("next")) || "nothing") + " next. " + fmt(CFG.R) + ", starting now.");
  S.prevPair = { d: title(slot("doing")), n: title(slot("next")) };
  sound("start");
}
function startSnooze() {
  S.z += 1; enter("snooze", qU());
  ev("engine", "timers", "info", "schedule snooze end", "snooze end " + stamp(S.W + qU() * 1000) + "\nthe snooze clock starts at Go, so it is always " + fmt(qU()) + "\n" + halfLine(qU()));
  speak("snooze_accepted", {}, "Snooze " + S.z + " of " + zMax() + ". " + fmt(qU()) + ".");
}
function startStatus() {
  var x = roundCleared(), diff = [];
  var base = S.rounds[S.round] ? S.rounds[S.round].start : {};
  for (var j in S.nodes) { var now = displayStatus(j), was = base[j] || "new"; if (was !== now) diff.push([S.nodes[j].title, was, now]); }
  S.x = x; S.diff = diff;
  if (S.rounds[S.round]) S.rounds[S.round].end = snap();
  var len = awayFor(S.z, x);
  S.statusLen = len;
  enter("status", len);
  ev("engine", "timers", "info", "schedule check-up end", "check-up " + fmt(len) + " = " + fmt(qU()) + " × 2^" + (S.z + 1) + " ÷ " + (x + 1) + "\nends " + stamp(S.W + len * 1000) + "\n" + halfLine(len));
  speak("checkup_start", { elapsed: S.roundRun, statusLen: len, x: x, diff: diff }, "Round over at " + fmt(S.roundRun) + ". Check-up, " + fmt(len) + ".");
  sound("stop");
  startTurn();
  // Initiative (SPEC §8.2): a nudge found while a session runs is folded into the turn, not shown.
  var stale = staleSteps();
  if (!S.nudged && stale.length) {
    S.nudged = true;
    ev("scheduler", "coordinator", "warning", "nudge deferred: session running", "rule untouched_5d, " + stale.map(title).join(", ") + "; folded into this phase's projection");
  }
}
function startStrategy() {
  if (S.turn && !S.turn.done) abandonTurn();
  enter("strategy", qU());
  ev("engine", "timers", "info", "schedule plan end", "plan end " + stamp(S.W + qU() * 1000) + "\n" + halfLine(qU()));
  S.picks = { d: null, n: null };
  if (S.held && S.held.props) {
    ev("engine", "coordinator", "info", "render held output", "", S.turn && S.turn.id);
    ev("coordinator", "output", "ok", "say and " + S.held.props.length + " proposal(s) shown", S.held.props.map(function (p) { return p.text; }).join("\n"), S.turn && S.turn.id);
    if (S.held.brief) { ev("coordinator", "a", "ok", "brief shown to A", S.held.brief.text + "\n" + S.held.brief.forA, S.turn && S.turn.id); pushA("brief", { text: S.held.brief.text, forA: S.held.brief.forA }); }
  }
  speak("plan_start", { held: S.held && S.held.props ? { say: !!S.held.say, proposals: S.held.props.length } : null }, "Plan round " + (S.round + 1) + ", " + fmt(qU()) + ".");
  UI.boardView = "map";
}
function startBreak() {
  enter("break", CFG.Lb);
  ev("engine", "timers", "info", "schedule break end", "break end " + stamp(S.W + CFG.Lb * 1000) + "\n" + halfLine(CFG.Lb));
  speak("break_start", { seated: S.seated }, "Seated " + fmt(S.seated) + ". Movement break, " + fmt(CFG.Lb) + ".");
}
function resetIfMoved(len) {
  if (len >= CFG.Lb) { S.seated = 0; ev("engine", null, "info", "seated time reset", "a check-up of " + fmt(len) + " counts as moving"); }
}
// The clock you are in stops at the instant the next one starts: at Go.
function leave() {
  if (S.frozen || !S.state || S.state === "idle") return;
  var ran = S.T - S.phaseStart;
  if (S.state === "work" || S.state === "snooze") S.roundRun += ran;
  else if (S.state === "status") resetIfMoved(ran);
  else if (S.state === "break") { S.seated = 0; ev("engine", null, "info", "seated time reset", "break"); }
  ev("engine", "timers", "info", "cancel " + PHASE[S.state].toLowerCase() + " timers", "stopped at Go after " + fmt(ran));
}
function commitNow() {
  var p = commitPair(), why = validateCommit(p.d, p.n);
  if (why) { p = autoPair(); ev("engine", null, "warning", "pair no longer valid at Go: auto-commit", why); }
  if (!p.d) return;
  ev("man", "engine", "info", "commit(doing: " + title(p.d) + ", next: " + (title(p.n) || "nothing") + ")", "at Go");
  apply("engine", pairOps(p.d, p.n), "commit");
  S.picks = { d: null, n: null };
}
function go(r) {
  var to = r.to_phase, from = S.state, wasFrozen = S.frozen;
  leave();
  switch (to) {
    case "end": endSession(); return;
    case "snooze": startSnooze(); return;
    case "status": startStatus(); return;
    case "strategy": startStrategy(); return;
    case "work": case "break":
      if ((from === "idle" || from === "strategy") && !wasFrozen) commitNow();
      if (to === "break") startBreak(); else startRound();
  }
}
// The System reaches the end of a phase: the clock stops, the session freezes, and the System
// raises the request for what comes next, approved by policy. Nothing runs until B presses Go.
function clockEnded() {
  var st = S.state, len = phaseLen();
  if (st === "work" || st === "snooze") S.roundRun += len;
  S.frozen = true; S.reading = len; S.lastRem = null; S.strip = null;
  ev("timers", "engine", "info", "tick: " + PHASE[st].toLowerCase() + " end", "the clock stops; frozen until B presses Go");
  pushA("phase", { phase: PHASE[st] + " ended", length: len, ends_at: null, reading: len });
  closeReq(S.req, "overtaken"); S.req = null;
  if (st === "work" || st === "snooze") {
    speak("time_up", {}, "Time's up."); sound("timeup");
    sysRaise("status");
  } else if (st === "status") {
    resetIfMoved(S.statusLen);
    if (S.turn && !S.turn.done) abandonTurn();
    say("Check-up over.");
    sysRaise("strategy");
  } else if (st === "strategy") {
    var p = commitPair(), chosen = !!(S.picks.d || S.picks.n);
    if (validateCommit(p.d, p.n)) { p = autoPair(); chosen = false; }
    if (!p.d) { say("No open steps left."); endSession(); return; }
    ev("engine", null, "info", chosen ? "plan over: B's pair kept" : "auto-commit", "doing " + title(p.d) + ", next " + (title(p.n) || "nothing"));
    apply("engine", pairOps(p.d, p.n), chosen ? "commit at plan end" : "auto-commit");
    S.picks = { d: null, n: null }; S.planChosen = chosen;
    speak("plan_over", { chosen: chosen, doing: title(p.d), next: title(p.n) }, "Planning over.");
    sysRaise(sitCheck() ? "break" : "work");
  } else if (st === "break") {
    S.seated = 0; speak("break_end", { round: S.round + 1 }, "Sitting clock reset.");
    sysRaise("work");
  }
}
// The sit check, before every round but the first: one more round would pass the sitting limit?
function sitCheck() {
  var b = sitBreak();
  if (b) ev("engine", null, "info", "sit check: break first", "seated " + fmt(S.seated) + " + round " + fmt(CFG.R) + " > " + fmt(CFG.Ls));
  else speak("continue", { seated: S.seated }, "Seated " + fmt(S.seated) + ". Continue.");
  return b;
}
function tick() {
  if (!running()) return;
  var st = S.state;
  if (st === "work") {
    var lf = S.phaseEnd - S.T, R = remTimes();
    while (S.remFired < R.length && lf <= R[S.remFired]) {
      var t = R[S.remFired], i = S.remFired; S.remFired++;
      ev("timers", "engine", "info", "tick: reminder " + digits(t), "");
      speak("reminder", { remaining: t, reminderIndex: i, reminderCount: R.length }, fmt(t) + " left.");
      sound("tick");
      pushA("reminder", { text: fmt(t) + " left.", remaining: Math.round(t), index: i, count: R.length, last: i === R.length - 1 });
      // The first r−1 reminders fade on their own; the last one covers the screen (default 32).
      if (i < R.length - 1) S.strip = { text: fmt(t) + " left.", until: performance.now() + 4000 };
      else { S.lastRem = { t: t }; S.strip = null; ev("engine", "output", "info", "last reminder: cover", "the clock keeps running"); }
    }
  }
  if (st !== "work" && !S.halfFired) {
    var len = phaseLen(), half = len / 2, lh = S.phaseEnd - S.T;
    if (len > 0 && lh <= half && lh > 0) {
      S.halfFired = true;
      ev("timers", "engine", "info", "tick: half-time reminder " + digits(half), PHASE[st].toLowerCase() + " of " + fmt(len) + "; not from the reminder arithmetic");
      speak("reminder", { remaining: half, reminderIndex: 0, R: len }, fmt(half) + " left, halfway.");
      sound("tick");
      pushA("reminder", { text: fmt(half) + " left, halfway.", remaining: Math.round(half), halfway: true });
      S.strip = { text: fmt(half) + " left, halfway.", until: performance.now() + 4000 };
    }
  }
  if (st === "status" && S.turn && !S.turn.done && S.turn.answerAt != null && S.T >= S.turn.answerAt) modelAnswer();
  if (S.T >= S.phaseEnd) clockEnded();
}
