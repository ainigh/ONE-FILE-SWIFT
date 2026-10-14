/* model.js: the assistant's one turn per round, and the brief it writes for A. */
"use strict";
// ----- the assistant's one turn per round: check-up entry to check-up end (SPEC §8.6) -----
// The built-in assistant reads the plan itself, in this page. It never decides a request.
function startTurn() {
  if (UI.model === "none") { S.turn = null; S.held = null; return; }
  var id = "t_" + (++S.turnSeq);
  var lat = Math.min(S.statusLen * 0.55, 2.7 * Math.max(1, speed));
  S.turn = { id: id, since: S.T, deadline: S.phaseEnd, answerAt: S.T + lat, done: false };
  S.held = { thinking: true };
  ev("engine", "coordinator", "info", "phase turn", "start assistant turn, deadline " + stamp(S.W + S.statusLen * 1000) + " (check-up end)", id);
  ev("coordinator", "model", "info", "plan sent", "projection " + Object.keys(S.nodes).length + " step(s), round " + S.round + "\nassistant: built in (reads the plan in this page)", id);
}
function abandonTurn() {
  S.turn.done = true; S.held = { failed: true };
  ev("coordinator", null, "warning", "turn abandoned: deadline missed", "no answer by " + stamp(S.W) + "; ignored, the session goes on", S.turn.id);
}
// The assistant reads B's plan so A does not have to: one plain paragraph about the round, and what,
// if anything, A might weigh. Held with the rest of the turn; shown to A only at planning.
function briefForA() {
  var base = S.rounds[S.round] ? S.rounds[S.round].start : {};
  var changed = Object.keys(S.nodes).filter(function (k) { return (base[k] || "new") !== displayStatus(k); });
  var cleared = changed.filter(function (k) { return finished(k); }).map(title);
  var bl = Object.keys(S.nodes).filter(function (k) { return isBlocked(k); });
  var D = slot("doing"), parts = [];
  parts.push(cleared.length ? "B finished " + (cleared.length === 1 ? "one step" : cleared.length + " steps") + ": " + cleared.join(", ") + "." : "B finished nothing this round.");
  if (S.z) parts.push(S.z === 1 ? "One snooze." : S.z + " snoozes.");
  if (bl.length === 1) parts.push(title(bl[0]) + " is still waiting on " + title(unfinishedDeps(bl[0])[0]) + ".");
  else if (bl.length > 1) parts.push(bl.length + " steps are still waiting on others.");
  parts.push(D ? "Doing stays " + title(D) + " unless B changes it." : "B has nothing as Doing yet.");
  var forA = !cleared.length && S.z >= 2 ? "Worth a word with B before approving round " + (S.round + 1) + ": several snoozes and nothing finished."
    : !cleared.length ? "Nothing for A to weigh now. If this repeats, ask B about it."
    : "Nothing for A to weigh. Approve round " + (S.round + 1) + " when B asks.";
  return { text: parts.join(" "), forA: forA };
}
function modelAnswer() {
  var t = S.turn; t.done = true;
  var props = modelProps(), text = modelSay(S.x);
  S.held = { thinking: false, say: text, props: props, brief: briefForA() };
  var lat = ((t.answerAt - t.since) / Math.max(1, speed)).toFixed(1);
  ev("model", "coordinator", "ok", "answer received", "say: \"" + text + "\"\npatch: " + props.length + " proposal(s)\nbrief for A: \"" + S.held.brief.text + "\"\nlatency " + lat + " s, deadline met; held until plan", t.id);
}
// What the assistant says to B at planning: the round's count, then the one thing worth knowing.
function modelSay(x) {
  var bits = [x === 0 ? "Nothing cleared this round. A smaller Doing may help." : x === 1 ? "One step cleared." : x + " steps cleared."];
  var bl = Object.keys(S.nodes).filter(function (k) { return isBlocked(k); })[0];
  var base = S.rounds[S.round] ? S.rounds[S.round].start : {};
  var freed = Object.keys(S.nodes).filter(function (k) { return base[k] === "blocked" && displayStatus(k) === "open"; })[0];
  if (bl) bits.push(title(bl) + " waits on " + title(unfinishedDeps(bl)[0]) + ", so keep that moving.");
  else if (freed) bits.push(title(freed) + " is unblocked now.");
  else if (!slot("next") && oldestOpen(slot("doing"))) bits.push("Nothing is Next yet: pick one before the round starts.");
  return bits.join(" ");
}
// Proposals, each one patch B can accept or skip on the board: finish a step under Doing that looks
// done, and cross out steps untouched for five days. Locked steps are never touched.
function modelProps() {
  var out = [], D = slot("doing");
  function free(id) { return S.nodes[id] && !N(id).locked; }
  var leaf = D ? descendants(D).filter(function (k) { return free(k) && N(k).status === "open" && !isBlocked(k); })[0] : null;
  if (leaf) out.push({ id: "p_" + (++S.propSeq), kind: "done", targets: [leaf], text: "Mark “" + title(leaf) + "” as done",
    ok: function () { return S.nodes[leaf] && N(leaf).status === "open"; }, ops: function () { return [{ id: leaf, f: "status", to: "done" }]; } });
  if (S.round >= 1) staleSteps().forEach(function (id) {
    if (id === D || id === slot("next")) return;
    out.push({ id: "p_" + (++S.propSeq), kind: "cross", targets: [id], text: "Cross out “" + title(id) + "”: untouched for " + ageDays(id) + " days",
      ok: function () { return S.nodes[id] && N(id).status === "open"; }, ops: function () { return [{ id: id, f: "status", to: "crossed" }]; } });
  });
  return out.slice(0, 3);
}
function acceptProp(p) {
  var h = S.held; if (!h || !h.props) return;
  if (!p.ok()) { p.stale = true; return; }
  ev("man", "coordinator", "info", "accept " + p.id, p.text, S.turn && S.turn.id);
  if (apply("model", p.ops(), "turn " + (S.turn ? S.turn.id : ""))) h.props = h.props.filter(function (o) { return o !== p; });
}
function rejectProp(p) {
  var h = S.held; if (!h || !h.props) return;
  ev("man", "coordinator", "info", "reject " + p.id, p.text, S.turn && S.turn.id);
  h.props = h.props.filter(function (o) { return o !== p; });
}
