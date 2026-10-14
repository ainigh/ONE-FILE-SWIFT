/* store.js: the plan: nodes, patches, undo and redo, and B's operations on the graph. */
"use strict";
// ----- the store (SPEC §5) -----
function N(id) { return S.nodes[id]; }
function finished(id) { return N(id).status === "done"; }
function isClosed(id) { var s = N(id).status; return s === "done" || s === "crossed"; }
function unfinishedDeps(id) { return N(id).deps.filter(function (d) { return S.nodes[d] && !finished(d); }); }
function isBlocked(id) { return !isClosed(id) && unfinishedDeps(id).length > 0; }
function slot(st) { for (var k in S.nodes) if (S.nodes[k].status === st) return k; return null; }
function title(id) { return id && S.nodes[id] ? S.nodes[id].title : null; }
function displayStatus(id) { var n = N(id); if (n.status === "open" && isBlocked(id)) return "blocked"; return n.status; }
var WORD = { open: "open", doing: "doing", next: "next", blocked: "blocked", done: "done", crossed: "crossed out", "new": "new" };
function kids(id) { return Object.keys(S.nodes).filter(function (k) { return S.nodes[k].parent === id; }).sort(function (a, b) { return S.nodes[a].created - S.nodes[b].created; }); }
function descendants(id) { var out = []; kids(id).forEach(function (k) { out.push(k); out = out.concat(descendants(k)); }); return out; }
function treeOrder() { var out = []; function walk(id, d) { out.push([id, d]); kids(id).forEach(function (k) { walk(k, d + 1); }); }
  Object.keys(S.nodes).filter(function (k) { return !S.nodes[k].parent; }).forEach(function (r) { walk(r, 0); }); return out; }
function goal() { for (var k in S.nodes) if (S.nodes[k].root) return k; return null; }
function oldestOpen(except) {
  var best = null;
  for (var k in S.nodes) {
    var n = S.nodes[k];
    if (n.root || k === except || n.status !== "open" || isBlocked(k)) continue;
    if (!best || n.created < S.nodes[best].created) best = k;
  }
  return best;
}
function dependsOn(a, b, seen) { // does a (transitively) wait for b?
  seen = seen || {}; if (seen[a]) return false; seen[a] = true;
  return N(a).deps.some(function (d) { return d === b || (S.nodes[d] && dependsOn(d, b, seen)); });
}
function clone(v) { return v == null ? v : JSON.parse(JSON.stringify(v)); }
var BY_PART = { man: "man", model: "coordinator", engine: "engine" };
// Age in whole days since a step was last touched.
function ageDays(id) { return Math.floor((S.W - N(id).updated) / 86400000); }
// A step B has not touched for five days or more: open, unlocked, not Doing or Next, not the goal.
function staleSteps() { return Object.keys(S.nodes).filter(function (k) { var n = N(k); return !n.root && !n.locked && n.status === "open" && ageDays(k) >= 5; }); }
function describe(o) {
  var t = o.f === "add" ? (o.to || o.from).title : title(o.id);
  switch (o.f) {
    case "add": return o.to ? "add_node " + t + " under " + title(o.to.parent) : "remove_node " + t;
    case "status": return (o.to === "crossed" ? "cross_out " + t : o.from === "crossed" ? "restore " + t : "set_status " + t + " → " + WORD[o.to]);
    case "title": return "rename " + o.from + " → " + o.to;
    case "deps": return (o.to.length > o.from.length ? "add_dependency " + t + " on " + title(o.to[o.to.length - 1]) : "remove_dependency " + t);
    case "locked": return (o.to ? "lock " : "unlock ") + t;
  }
  return o.f;
}
function setOp(o) {
  if (o.f === "add") { if (o.to) { S.nodes[o.id] = clone(o.to); S.nodes[o.id].fresh = true; S.nodes[o.id].updated = S.W; } else delete S.nodes[o.id]; return; }
  var n = S.nodes[o.id]; if (!n) return;
  if (o.f === "status" && (o.to === "doing" || o.to === "next")) { var cur = slot(o.to); if (cur && cur !== o.id) S.nodes[cur].status = "open"; }
  n[o.f] = clone(o.to); n.updated = S.W;
  if (o.f === "status") { if (o.to === "done") S.doneAt[o.id] = S.T; else delete S.doneAt[o.id]; }
}
// Who edits, and when (addendum §7): only B edits the graph, and only in idle, work, snooze and
// plan. Check-up, the break and every freeze are closed. Nobody types into the grid.
function editBlock() {
  if (S.frozen) return "Time has stopped. The plan opens again when you press Go.";
  if (S.state === "status") return "The plan is closed during check-up. Step away from the desk.";
  if (S.state === "break") return "The plan is locked during the movement break. It opens again in " + digits(left()) + ".";
  return null;
}
// Store.apply: every change goes through here, is logged with its round stamp, and (for B and the model) can be undone.
function apply(by, ops, why, noUndo) {
  if (!ops.length) return null;
  var blocked = by !== "engine" && editBlock();
  if (blocked) { ev(BY_PART[by], "store", "warning", "patch refused: plan closed", blocked); toast(blocked); return null; }
  var rec = { n: S.pn + 1, by: by, why: why, round: S.round, phase: S.state || "none", ops: ops.map(function (o) {
    return { id: o.id, f: o.f, from: o.f === "add" ? (S.nodes[o.id] ? clone(S.nodes[o.id]) : null) : clone(S.nodes[o.id][o.f]), to: clone(o.to) };
  }) };
  var was = {}; for (var k in S.nodes) was[k] = isBlocked(k);
  var D0 = slot("doing");
  var lines = rec.ops.map(describe);
  rec.ops.forEach(setOp);
  S.pn = rec.n;
  var unb = Object.keys(S.nodes).filter(function (k) { return was[k] && !isBlocked(k) && !isClosed(k); });
  ev(BY_PART[by], "store", "ok", "patch " + rec.n + ": " + rec.ops.length + " op(s)",
    "by " + by + (why ? " (" + why + ")" : "") + ", round " + rec.round + " · " + rec.phase + ", store version " + rec.n + "\n" + lines.join("\n") + (unb.length ? "\nunblocked: " + unb.map(title).join(", ") : ""), S.turn && by === "model" ? S.turn.id : null);
  if (savePlan()) ev("store", "disk", "ok", "plan saved", "this browser's storage, " + Object.keys(S.nodes).length + " step(s), version " + S.pn);
  else ev("store", "disk", "warning", "plan not saved", "this browser refused storage; the plan lives only on this page until it can be saved");
  if (!noUndo && by !== "engine") { S.undo.push(rec); S.redo = []; }
  // SPEC §6.5: Doing vacated during work or snooze, with no new Doing in the patch: promote Next.
  if (D0 && !slot("doing") && running() && (S.state === "work" || S.state === "snooze")) {
    var n = slot("next");
    if (n) { apply("engine", [{ id: n, f: "status", to: "doing" }], "promote next"); speak("promote_next", { doing: title(n), prevDoing: title(D0) }, "Now doing " + title(n) + "."); }
    else speak("no_doing", {}, "No doing node.");
  }
  return rec;
}
function undo() {
  var rec = S.undo.pop(); if (!rec) return;
  var orphans = rec.ops.some(function (o) { return o.f === "add" && o.to && S.nodes[o.id] && kids(o.id).length; });
  if (orphans) { S.undo.push(rec); toast("Undo would remove a step that now has steps under it. Cross it out instead."); return; }
  var inv = rec.ops.slice().reverse().map(function (o) { return { id: o.id, f: o.f, to: o.from }; });
  ev("man", "store", "info", "undo patch " + rec.n, "");
  if (apply("man", inv, "undo " + rec.n, true)) S.redo.push(rec); else S.undo.push(rec);
}
function redo() {
  var rec = S.redo.pop(); if (!rec) return;
  ev("man", "store", "info", "redo patch " + rec.n, "");
  if (apply("man", rec.ops.map(function (o) { return { id: o.id, f: o.f, to: o.to }; }), "redo " + rec.n, true)) S.undo.push(rec); else S.redo.push(rec);
}
function undoLabel(rec) { var o = rec.ops[0]; return o.f === "add" ? (o.to ? "Add Step" : "Remove Step") : o.f === "status" ? (o.to === "crossed" ? "Cross Out" : o.from === "crossed" ? "Restore" : "Status") :
  o.f === "title" ? "Rename" : o.f === "deps" ? "Dependency" : o.f === "locked" ? "Lock" : "Change"; }

// B's operations on the graph (each one patch).
function canEdit(id) { return id && S.nodes[id]; }
function markDone(id) {
  if (!canEdit(id) || N(id).root || finished(id)) return;
  if (editBlock()) { toast(editBlock()); return; }
  if (S.picks.d === id) S.picks.d = null;
  if (S.picks.n === id) S.picks.n = null;
  apply("man", [{ id: id, f: "status", to: "done" }]);
}
function reopen(id) { if (canEdit(id) && finished(id) && !unfinishedDeps(id).length) apply("man", [{ id: id, f: "status", to: "open" }]); }
function crossOut(id) {
  if (!canEdit(id) || N(id).root || N(id).status === "crossed") return;
  var ops = [{ id: id, f: "status", to: "crossed" }];
  descendants(id).forEach(function (k) { var s = N(k).status; if (s !== "done" && s !== "crossed") ops.push({ id: k, f: "status", to: "crossed" }); });
  if (apply("man", ops)) { if (S.picks.d === id) S.picks.d = null; if (S.picks.n === id) S.picks.n = null; }
}
function restore(id) { if (canEdit(id) && N(id).status === "crossed") apply("man", [{ id: id, f: "status", to: "open" }]); }
function rename(id, t) { t = (t || "").trim(); if (canEdit(id) && t && t !== N(id).title) apply("man", [{ id: id, f: "title", to: t }]); }
function addChild(parent, t) {
  parent = canEdit(parent) ? parent : goal();
  if (!parent) { var gid = "n" + (++S.seq); if (!apply("man", [{ id: gid, f: "add", to: mk("Today", null, S.seq) }])) return null; parent = gid; }
  var id = "n" + (++S.seq);
  var n = mk(t || "New step", parent, S.seq); n.updated = S.W;
  return apply("man", [{ id: id, f: "add", to: n }]) ? id : null;
}
function addDep(id, on) {
  if (!canEdit(id) || !canEdit(on)) return;
  if (id === on || N(id).deps.indexOf(on) >= 0) return;
  if (dependsOn(on, id)) {
    var m = title(on) + " already waits for " + title(id) + ". A step cannot wait for itself.";
    ev("man", "store", "error", "patch refused: dependency cycle", m); toast(m); return;
  }
  apply("man", [{ id: id, f: "deps", to: N(id).deps.concat([on]) }]);
}
function removeDep(id) { if (canEdit(id) && N(id).deps.length) apply("man", [{ id: id, f: "deps", to: N(id).deps.slice(0, -1) }]); }
function setLock(id, v) { if (canEdit(id)) apply("man", [{ id: id, f: "locked", to: v }]); }

// Clear the plan: every step goes, and the next visit starts at the intake. Only outside a session.
function clearPlan() {
  if (S.state) return false;
  var count = Object.keys(S.nodes).length;
  S.nodes = {}; S.seq = 0; S.pn = 0; S.doneAt = {}; S.undo = []; S.redo = []; S.selected = null; S.picks = { d: null, n: null };
  UI.intake = { stage: firstStage(), ids: [] }; UI.gridRound = 0; UI.depFor = null; UI.renaming = null; closePop();
  savePlan();
  ev("man", "store", "info", "plan cleared", count + " step(s) removed");
  return true;
}
