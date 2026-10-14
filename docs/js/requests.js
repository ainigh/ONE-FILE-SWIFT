/* requests.js: requests: raised by B or the System, decided by policy or A, accepted by B. */
"use strict";
// ----- requests (addendum §5): one record, three timestamps and a verdict -----
function openReq() { return S.req && !S.req.outcome ? S.req : null; }
function reqLabel(to) {
  switch (to) {
    case "work": return "Start round " + (S.round + 1);
    case "snooze": return "Snooze " + (S.z + 1) + " of " + zMax();
    case "status": return "Move on to check-up";
    case "strategy": return "Start planning round " + (S.round + 1);
    case "break": return "Start the movement break";
    case "end": return "End the session";
  }
  return to;
}
function reqWhat(r) {
  switch (r.to_phase) {
    case "work": return "starting round " + (S.round + 1);
    case "snooze": return "snooze " + (S.z + 1) + " of " + zMax();
    case "status": return "moving on to check-up";
    case "strategy": return "moving on to planning";
    case "break": return "the movement break";
    case "end": return "ending the session";
  }
  return "this";
}
function newReq(to, by) {
  var r = { id: "r" + (++S.reqSeq), session_id: S.sessionId, round: S.round, from_phase: (S.state || "idle") + (S.frozen ? " (ended)" : ""), to_phase: to,
    raised_by: by, sent_at: S.W, decided_at: null, decided_by: null, verdict: null, reason: "", policy: null,
    accepted_at: null, outcome: null, label: reqLabel(to) };
  S.requests.push(r);
  return r;
}
// Policy: the arithmetic made into verdicts (addendum §6).
function policyFor(to) {
  var st = S.state;
  if (to === "end") return st === "status" ? ["refused", "Finish the check-up first."] : st === "break" ? ["refused", "Finish the break first."] : ["approved", ""];
  if (to === "snooze") return S.z < zMax() ? ["approved", ""] : ["refused", "No snoozes left."];
  if (st === "status") return ["refused", "Check-up has " + fmt(left()) + " left."];
  if (st === "break") return ["refused", "Break has " + fmt(left()) + " left."];
  if (to === "work") { var p = commitPair(), why = validateCommit(p.d, p.n); return why ? ["refused", why] : ["approved", ""]; }
  return ["approved", ""];
}
// What a human A cannot approve whatever they judge: a round with no valid pair, a fourth snooze.
function cannotApprove(r) {
  if (r.to_phase === "snooze" && S.z >= zMax()) return bName() + " has no snoozes left.";
  if (r.to_phase === "work" && (S.state === "idle" || S.state === "strategy") && !S.frozen) { var p = commitPair(); return validateCommit(p.d, p.n); }
  return null;
}
function raise(to) {
  if (openReq() || !S.state) return;
  if (S.frozen && to !== "snooze") return;
  var r = newReq(to, "man");
  r.policy = policyFor(to);
  S.req = r;
  ev("man", "engine", "info", "request " + r.id + ": " + r.label, "from " + r.from_phase + ", sent " + stamp(r.sent_at) + "\npolicy default: " + (r.policy[0] === "approved" ? "approve" : "refuse, “" + r.policy[1] + "”") + "\nthe clock keeps running");
  if (UI.auto) decide(r, r.policy[0], r.policy[1], "policy");
  else ev("engine", "a", "info", "request " + r.id + " waits for A", r.label + "\npolicy default shown beside it");
}
function decide(r, verdict, reason, by) {
  if (r !== S.req || r.verdict || r.outcome) return;
  if (verdict === "approved" && cannotApprove(r)) return;
  r.decided_at = S.W; r.decided_by = by; r.verdict = verdict;
  r.reason = verdict === "refused" ? (reason || aName() + " said no.") : "";
  ev(by === "a" ? "a" : "policy", "engine", verdict === "approved" ? "ok" : "warning", "request " + r.id + " " + verdict + (by === "a" && verdict !== r.policy[0] ? " (A overrules policy)" : ""),
    r.label + (r.reason ? "\nreason: " + r.reason : "") + "\ndecided by " + by + ", after " + fmt((r.decided_at - r.sent_at) / 1000));
  // The sit check rides on the approval of the next round: the offer may be a break first.
  if (verdict === "approved" && r.to_phase === "work" && S.state === "strategy" && !S.frozen && sitCheck()) { r.to_phase = "break"; r.label += ", break first"; }
}
function sysRaise(to) {
  var r = newReq(to, "system");
  r.policy = ["approved", ""]; r.decided_at = S.W; r.decided_by = "policy"; r.verdict = "approved";
  S.sys = r;
  ev("engine", "output", "info", "System raises " + r.id + ": " + r.label, "approved by policy; frozen until B presses Go");
}
function closeReq(r, outcome) {
  if (!r || r.outcome) return;
  r.outcome = outcome;
  ev("engine", null, outcome === "overtaken" ? "warning" : "info", "request " + r.id + " " + outcome, r.label);
}
// B presses Go: the agreement. This clock stops and the next starts at the same instant.
function accept(r) {
  if (!r || r.verdict !== "approved" || r.outcome) return;
  r.accepted_at = S.W; r.outcome = "accepted";
  var gap = fmt((r.accepted_at - r.decided_at) / 1000);
  ev("man", "engine", "info", "Go: " + r.label, (r.raised_by === "system" ? "freeze " : "confirmed after ") + gap);
  if (r === S.req) S.req = null;
  if (r === S.sys) S.sys = null;
  if (S.sys) { closeReq(S.sys, "overtaken"); S.sys = null; }
  go(r);
}
function ack(r) {
  if (!r || r.outcome) return;
  r.accepted_at = S.W; r.outcome = "acknowledged";
  ev("man", "engine", "info", "OK: " + r.label + " refused", r.reason);
  S.req = null;
}
function nextPhase() {
  if (openReq() || S.frozen) return;
  var st = S.state;
  if (!st || st === "idle") { if (UI.intake.stage === "ready") okReady(); return; }
  raise(st === "work" || st === "snooze" ? "status" : st === "status" ? "strategy" : "work");
}
function okReady() {
  if (openReq()) return;
  if (!S.state) startSession();
  raise("work");
}
