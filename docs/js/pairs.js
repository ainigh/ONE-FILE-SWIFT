/* pairs.js: Doing and Next: picked before a round, committed at Go. */
"use strict";
// ----- Doing and Next (SPEC §6.6): picked before a round, committed at Go -----
function canPick() { return (!S.state || S.state === "idle" || S.state === "strategy") && !S.frozen; }
// Doing and Next are exclusive: a step picked as one stops being the other; picks win over last round's pair.
function commitPair() {
  var d = S.picks.d || slot("doing"), n = S.picks.n || slot("next");
  if (d && d === n) { if (S.picks.d === d) n = S.picks.n; else d = S.picks.d; }
  return { d: d, n: n };
}
function pairNow() { return canPick() ? commitPair() : { d: slot("doing"), n: slot("next") }; }
function validateCommit(d, n) {
  if (!d || !n) return "Choose Doing and Next.";
  if (d === n) return "Doing and Next must be different steps.";
  if (N(d).root || N(n).root) return "The goal itself cannot be Doing or Next.";
  if (isClosed(d)) return title(d) + " is " + WORD[N(d).status] + ", so it cannot be Doing.";
  if (unfinishedDeps(d).length) return title(d) + " is waiting for " + title(unfinishedDeps(d)[0]) + ", so it cannot be Doing yet.";
  if (isClosed(n)) return title(n) + " is " + WORD[N(n).status] + ", so it cannot be Next.";
  var un = unfinishedDeps(n);
  if (un.length && !(un.length === 1 && un[0] === d)) return title(n) + " is waiting for " + title(un[0]) + ", so it can only be Next if that is Doing.";
  return null;
}
function pickReason(id, which) {
  if (!canPick()) return "Doing and Next are chosen before a round: on the Ready screen, or while you plan.";
  if (N(id).root) return "The goal itself cannot be picked.";
  if (isClosed(id)) return "A " + WORD[N(id).status] + " step cannot be " + (which === "d" ? "Doing." : "Next.");
  if (which === "d" && unfinishedDeps(id).length) return "Waiting for " + title(unfinishedDeps(id)[0]) + ".";
  return null;
}
function pick(which, id) {
  if (pickReason(id, which)) { toast(pickReason(id, which)); return; }
  if ((which === "d" ? S.picks.d : S.picks.n) === id) {
    if (which === "d") S.picks.d = null; else S.picks.n = null;
    ev("man", "engine", "info", "unpick " + (which === "d" ? "doing" : "next") + ": " + title(id), "view state until Go"); return;
  }
  if (which === "d") { S.picks.d = id; if (S.picks.n === id) S.picks.n = null; }
  else { S.picks.n = id; if (S.picks.d === id) S.picks.d = null; }
  ev("man", "engine", "info", "pick " + (which === "d" ? "doing" : "next") + ": " + title(id), "view state until Go");
}
function pairOps(d, n) {
  var ops = [], cd = slot("doing"), cn = slot("next");
  if (cd && cd !== d && cd !== n) ops.push({ id: cd, f: "status", to: "open" });
  if (cn && cn !== d && cn !== n) ops.push({ id: cn, f: "status", to: "open" });
  if (N(d).status !== "doing") ops.push({ id: d, f: "status", to: "doing" });
  if (n && N(n).status !== "next") ops.push({ id: n, f: "status", to: "next" });
  return ops;
}
// Auto-commit (SPEC §6.7): keep Doing if it can stay, else promote; Next is the oldest open step.
function autoPair() {
  var D = slot("doing") || slot("next") || oldestOpen(null);
  if (D && (isClosed(D) || unfinishedDeps(D).length)) D = oldestOpen(null);
  if (!D) return { d: null, n: null };
  var cn = slot("next"), Nn = (cn && cn !== D && !validateCommit(D, cn)) ? cn : oldestOpen(D);
  return { d: D, n: Nn };
}
