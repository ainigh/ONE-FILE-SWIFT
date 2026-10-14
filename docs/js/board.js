/* board.js: the Strategy board: the mind map, its hover picks, the inspector, the node menu and the quick-add field. */
"use strict";
// ----- the Strategy board: the map, the read-only grid, the quick-add field -----
function renderBoard() {
  var blk = editBlock();
  $("board").classList.toggle("locked", !!blk);
  $("lockline").hidden = !blk || S.state === "break"; if (blk) $("lockline").textContent = blk;
  Array.prototype.forEach.call($("bseg").querySelectorAll("button"), function (b) { b.setAttribute("aria-selected", String(b.getAttribute("data-v") === UI.boardView)); });
  $("bp-map").hidden = UI.boardView !== "map"; $("bp-table").hidden = UI.boardView !== "table";
  $("bclose").hidden = bView() === "plan";
  renderBTop();
  if (UI.boardView === "map") renderGraph(); else renderGrid();
  $("qlunder").textContent = "under " + (title(S.selected) || title(goal()) || "the goal");
  $("qlin").disabled = !!blk;
  $("g-nav").hidden = UI.boardView !== "map";
  $("g-hint").textContent = UI.depFor ? "Click the step " + title(UI.depFor) + " waits for. Esc cancels." :
    canPick() ? "Hover a step and pick Doing or Next. Click a step for everything else." :
    (S.state === "work" || S.state === "snooze") ? "Hover Doing or Next to mark it done. Doing and Next are chosen when you plan." : "Click a step for its actions. Double-click to rename.";
}
var lastTop = "";
// At plan start, above the board: the round's diff, once, and the assistant's note for B. The
// assistant's proposals are on the map itself, as Done? / Cross out? and Skip beside the steps they touch.
function renderBTop() {
  var box = $("btop"), planning = S.state === "strategy" && !S.frozen;
  var say = planning && S.held && !S.held.thinking && !S.held.failed && S.held.say ? S.held.say : "";
  var props = planning && S.held && S.held.props ? S.held.props.filter(function (p) { return !p.stale; }).length : 0;
  var key = planning ? JSON.stringify(S.diff) + "|" + say + "|" + props : "";
  if (key === lastTop) return;
  lastTop = key; box.textContent = "";
  if (!planning || (!S.diff.length && !say)) return;
  if (S.diff.length) {
    var d = el("div", "diff"); d.appendChild(el("span", "label", "Round " + S.round + ": what changed"));
    S.diff.forEach(function (l) { var r = el("div"); r.appendChild(el("span", "", l[0])); r.appendChild(el("span", "", WORD[l[1]] + " → " + WORD[l[2]])); d.appendChild(r); });
    box.appendChild(d);
  }
  if (say) {
    var n = el("div", "asay"); n.appendChild(el("span", "label", "From the assistant"));
    n.appendChild(el("p", "", say + (props ? " " + (props === 1 ? "One suggestion is" : props + " suggestions are") + " on the map: accept or skip each." : "")));
    box.appendChild(n);
  }
}

// The map (DESIGN §8): the plan as a mind map, drawn by mapview.js. The goal is the hub in the middle,
// with a ring for how much is done; its steps branch out right and left, and each branch can fold.
// Cards show status: Doing filled, Next outlined, waiting dashed, done faded with a check, crossed
// out struck through. Click the name of the selected step, double-click a step, or press Return to
// rename it in place.
var lastGraph = "";
// While B picks, the map previews the pair Go will commit; otherwise it shows the plan as stored.
function mapStatus(id) {
  var n = N(id);
  if (n.root) return "goal";
  if (canPick() && !isClosed(id)) { var p = commitPair(); if (p.d === id) return "doing"; if (p.n === id) return "next"; return isBlocked(id) ? "blocked" : "open"; }
  return displayStatus(id);
}
function mapProps() {
  if (S.state !== "strategy" || editBlock() || !S.held || !S.held.props) return [];
  return S.held.props.filter(function (p) { return !p.stale && S.nodes[p.targets[0]]; });
}
function leafSteps() { return Object.keys(S.nodes).filter(function (k) { return !N(k).root && !kids(k).length && N(k).status !== "crossed"; }); }
function pathOf(id) { var out = [], p = N(id).parent; while (p && S.nodes[p]) { out.unshift(title(p)); p = N(p).parent; } return out; }

var LOCK_SVG = '<svg viewBox="0 0 10 10" aria-label="locked"><rect x="1.5" y="4.5" width="7" height="5" rx="1" fill="currentColor" opacity="0.8"/><path d="M3 4.5V3a2 2 0 0 1 4 0v1.5" fill="none" stroke="currentColor" stroke-opacity="0.8" stroke-width="1.2"/></svg>';
function fillCard(c, id) {
  var n = N(id), ds = mapStatus(id), editable = !editBlock();
  c.className = "card " + ds + (S.selected === id ? " sel" : "") + (editable ? " editable" : "") + (UI.renaming === id ? " renaming" : "") + (UI.depFor && UI.depFor !== id && !n.root ? " aimable" : "");
  if (n.fresh) { c.classList.add("fresh"); n.fresh = false; }
  c.textContent = "";
  if (n.root) {
    var leaves = leafSteps(), done = leaves.filter(finished).length, pct = leaves.length ? done / leaves.length : 0, R = 2 * Math.PI * 14;
    c.appendChild(el("span", "label", "Goal"));
    c.appendChild(renameField(id) || el("span", "tt", n.title));
    var r = el("span", "ring");
    r.innerHTML = '<svg viewBox="0 0 34 34" aria-hidden="true"><circle cx="17" cy="17" r="14" stroke="var(--line)"/><circle cx="17" cy="17" r="14" stroke="var(--done)" stroke-dasharray="' + R.toFixed(1) + '" stroke-dashoffset="' + (R * (1 - pct)).toFixed(1) + '" stroke-linecap="round" transform="rotate(-90 17 17)"/></svg>';
    r.appendChild(el("span", "", done + " of " + leaves.length + " steps done"));
    c.appendChild(r);
    c.setAttribute("aria-label", "Goal: " + n.title + ", " + done + " of " + leaves.length + " steps done");
    c.title = S.selected === id && editable ? "Click the name to rename" : n.title;
    return;
  }
  var st = el("span", "st"); if (ds === "done") st.innerHTML = '<svg viewBox="0 0 10 10"><path d="M2.5 5.3 4.3 7 7.6 3.4"/></svg>';
  c.appendChild(st);
  c.appendChild(renameField(id) || el("span", "tt", n.title));
  var meta = el("span", "meta");
  if (ds === "doing" || ds === "next" || ds === "blocked") meta.appendChild(el("span", "tag", ds === "blocked" ? "waits" : ds));
  if (n.locked) meta.insertAdjacentHTML("beforeend", LOCK_SVG);
  if (meta.childNodes.length) c.appendChild(meta);
  c.setAttribute("aria-label", n.title + ", " + WORD[ds] + (n.locked ? ", locked" : ""));
  c.title = S.selected === id && editable ? "Click the name to rename" : n.title + " · updated " + updatedWord(n.updated);
}
// The rename field, in the card itself, where the name was.
function renameField(id) {
  if (UI.renaming !== id) return null;
  var inp = el("input", "tt"); inp.value = UI.renameVal != null ? UI.renameVal : N(id).title; inp.maxLength = 60;
  inp.setAttribute("aria-label", "Rename");
  inp.addEventListener("input", function () { UI.renameVal = inp.value; });
  ["click", "dblclick", "pointerdown", "contextmenu"].forEach(function (t) { inp.addEventListener(t, function (e) { e.stopPropagation(); }); });
  inp.addEventListener("keydown", function (e) {
    e.stopPropagation();
    if (e.key === "Enter") { e.preventDefault(); var v = inp.value; UI.renaming = null; UI.renameVal = null; rename(id, v); render(true); refocus(id); }
    else if (e.key === "Escape") { UI.renaming = null; UI.renameVal = null; render(true); refocus(id); }
  });
  inp.addEventListener("blur", function () { if (UI.renaming === id && inp.isConnected) { UI.renaming = null; UI.renameVal = null; rename(id, inp.value); render(true); } });
  setTimeout(function () { if (inp.isConnected) { inp.focus(); inp.select(); } }, 0);
  return inp;
}
function refocus(id) { var c = bmap.card(id); (c && c.isConnected ? c : root).focus({ preventScroll: true }); }

function renderGraph(force) {
  var key = Object.keys(S.nodes).map(function (k) { var n = S.nodes[k]; return k + n.title + mapStatus(k) + n.parent + n.deps.join("") + (n.locked ? "L" : "") + (S.selected === k ? "S" : ""); }).join(",") +
    canPick() + S.state + S.frozen + JSON.stringify(S.picks) + JSON.stringify(commitPair()) + "|" + mapProps().map(function (p) { return p.id; }).join(",") + "|" + UI.depFor + "|" + UI.renaming + "|" + JSON.stringify(UI.folded) + "|" + !!editBlock();
  if (!force && key === lastGraph) return;
  lastGraph = key;
  hidePicks();
  bmap.render();
  $("maim").hidden = !UI.depFor; $("mcanvas").classList.toggle("aim", !!UI.depFor);
  if (UI.depFor) $("maimtext").textContent = "Choose what “" + title(UI.depFor) + "” waits for";
  renderInspector();
  if (UI.pop) openPop(UI.pop.id, UI.pop.x, UI.pop.y);
  var h = bmap.hovered(); if (h && S.nodes[h]) showPicks(h);
}
// The assistant's proposals sit under the step they touch: accept or skip each.
function buildProps() {
  mapProps().forEach(function (pr) {
    var q = bmap.pos(pr.targets[0]); if (!q) return;
    var box = el("div", "mprop"); box.title = pr.text;
    box.appendChild(el("span", "", "Assistant:")); box.appendChild(el("b", "", pr.kind === "done" ? "done?" : "cross out?"));
    var a = el("button", "acc", "Accept"), s = el("button", "", "Skip"); a.type = s.type = "button";
    a.title = pr.text; s.title = "Skip: " + pr.text;
    a.addEventListener("click", act(function () { acceptProp(pr); }));
    s.addEventListener("click", act(function () { rejectProp(pr); }));
    box.appendChild(a); box.appendChild(s);
    bmap.addOverlay(box, q.x - q.w / 2 + 10, q.y + q.h / 2 + 6);
  });
}

// The inspector, beside the map on a wide board: the selected step, what it waits for and unblocks, and its menu.
var inspFor = null;
function renderInspector() {
  var box = $("minsp"), id = S.selected && S.nodes[S.selected] ? S.selected : null;
  var keep = box.querySelector("input.name");
  if (keep && document.activeElement === keep && inspFor === id) keep = keep.parentNode; else keep = null;
  inspFor = id;
  Array.prototype.slice.call(box.children).forEach(function (c) { if (c !== keep) c.remove(); });
  if (!id) {
    var e = el("div", "empty");
    e.appendChild(el("b", "", "Nothing selected"));
    e.appendChild(document.createTextNode("Click a step to see what it waits for and what you can do to it. "));
    e.appendChild(el("kbd", "", "F")); e.appendChild(document.createTextNode(" fits the map, "));
    e.appendChild(el("kbd", "", "N")); e.appendChild(document.createTextNode(" centres on Doing."));
    box.appendChild(e); return;
  }
  var n = N(id), ds = mapStatus(id);
  if (!keep) {
    var head = el("div", "sec");
    var name = el("input", "name"); name.value = n.title; name.maxLength = 60; name.setAttribute("aria-label", n.root ? "Goal title" : "Step title");
    name.disabled = !!editBlock();
    name.addEventListener("change", function () { rename(id, name.value); render(true); });
    name.addEventListener("keydown", function (e) { e.stopPropagation(); if (e.key === "Enter") name.blur(); else if (e.key === "Escape") { name.value = N(id).title; name.blur(); } });
    head.appendChild(name);
    var path = pathOf(id); if (path.length) head.appendChild(el("div", "path", path.join("  ›  ")));
    var stat = el("div", "stat"), dot = el("i");
    dot.style.background = css({ doing: "--doing", next: "--next", done: "--done", blocked: "--blocked", crossed: "--ink3", open: "--ink2", goal: "--ink3" }[ds]);
    stat.appendChild(dot); stat.appendChild(el("span", "", n.root ? "The goal" : WORD[ds].charAt(0).toUpperCase() + WORD[ds].slice(1)));
    head.appendChild(stat);
    box.appendChild(head);
  }
  var kv = el("div", "sec kv");
  function row(k, v) { kv.appendChild(el("span", "", k)); var c = el("span"); if (typeof v === "string") c.textContent = v; else c.appendChild(v); kv.appendChild(c); }
  if (!n.root) {
    var w = el("span"); if (n.deps.length) n.deps.forEach(function (d) { w.appendChild(el("span", "chip" + (finished(d) ? "" : " wait"), title(d))); }); else w.textContent = "nothing";
    row("Waits for", w);
    var by = Object.keys(S.nodes).filter(function (k) { return N(k).deps.indexOf(id) >= 0; }), bs = el("span");
    if (by.length) by.forEach(function (d) { bs.appendChild(el("span", "chip", title(d))); }); else bs.textContent = "nothing";
    row("Unblocks", bs);
    row("Updated", updatedWord(n.updated));
  }
  var ks = kids(id); if (ks.length) row("Steps", ks.filter(finished).length + " of " + ks.length + " done");
  if (kv.childNodes.length) box.appendChild(kv);
  var acts = el("div", "sec acts");
  nodeMenu(id).forEach(function (it) {
    if (it.sep) { acts.appendChild(el("hr")); return; }
    if (it.note) { acts.appendChild(el("div", "why", it.note)); return; }
    var b = el("button"); b.type = "button"; b.appendChild(el("span", "", it.label)); if (it.sc) b.appendChild(el("span", "sc", it.sc));
    if (it.dis) { b.disabled = true; acts.appendChild(b); acts.appendChild(el("div", "why", it.dis)); return; }
    b.addEventListener("click", act(function () { closePop(); it.fn(); }));
    acts.appendChild(b);
  });
  box.appendChild(acts);
}
function inspOn() { return $("minsp").offsetWidth > 0; }

// Hover a step: Doing and Next while B plans, Mark done on Doing or Next during a round.
var picksEl = null, picksFor = null, picksTimer = null;
function showPicks(id) {
  var q = bmap.pos(id);
  if (!q || !S.nodes[id] || N(id).root || editBlock() || UI.depFor || UI.renaming === id) return hidePicks();
  var items = [], pair = commitPair();
  if (canPick() && !isClosed(id)) {
    [["d", "Doing", pair.d], ["n", "Next", pair.n]].forEach(function (x) {
      var which = x[0], on = x[2] === id, kept = on && S.picks[which] !== id;
      if (!on && pickReason(id, which)) return;
      items.push([x[1], which + (on ? " on" : "") + (kept ? " kept" : ""), kept ? null : function () { pick(which, id); },
        kept ? x[1] + " from last round. Pick another step to change it." : on ? "Clear " + x[1] : "Set as " + x[1]]);
    });
  } else if ((S.state === "work" || S.state === "snooze") && (slot("doing") === id || slot("next") === id) && !isClosed(id))
    items.push(["Mark done", "done", function () { markDone(id); }, "Mark " + title(id) + " done"]);
  if (!items.length) return hidePicks();
  hidePicks(); picksFor = id;
  picksEl = el("div", "mpicks");
  items.forEach(function (it) {
    var b = el("button", it[1], it[0]); b.type = "button"; b.title = it[3];
    b.addEventListener("click", function (e) { e.stopPropagation(); if (!it[2]) return; it[2](); render(true); });
    picksEl.appendChild(b);
  });
  picksEl.addEventListener("pointerenter", function () { clearTimeout(picksTimer); });
  picksEl.addEventListener("pointerleave", function () { picksTimer = setTimeout(hidePicks, 120); });
  bmap.box.appendChild(picksEl);
  // On the card's top border, at its outer end: clear of the branch lines, the fold and the cards beside it.
  picksEl.style.left = (q.dir >= 0 ? q.x + q.w / 2 - 10 - picksEl.offsetWidth : q.x - q.w / 2 + 10).toFixed(1) + "px"; picksEl.style.top = (q.y - q.h / 2 - 11).toFixed(1) + "px";
  var shown = picksEl; requestAnimationFrame(function () { shown.classList.add("show"); });
}
function hidePicks() { if (picksEl) { picksEl.remove(); picksEl = null; picksFor = null; } }

var clickTimer = null;
function cardClick(id, e) {
  if (UI.depFor) { var f = UI.depFor; if (N(id).root) return; UI.depFor = null; if (f !== id) addDep(f, id); render(true); return; }
  clearTimeout(clickTimer);
  if (S.selected === id && UI.renaming !== id && !editBlock()) {
    // In place: click the name of the selected step, or press Return on it, to rename it.
    var onName = e.type === "click" && e.target.classList && e.target.classList.contains("tt");
    if (onName || e.key === "Enter") { closePop(); UI.renaming = id; render(true); return; }
  }
  if (e.type === "keydown") { select(id); return; }
  clickTimer = setTimeout(function () { select(id); }, 180);
}
function select(id) {
  if (S.selected === id) { S.selected = null; closePop(); }
  else { S.selected = id; if (inspOn()) closePop(); else UI.pop = { id: id, center: true }; }
  render(true);
}
function cardDbl(id) { clearTimeout(clickTimer); closePop(); S.selected = id; if (editBlock()) toast(editBlock()); else UI.renaming = id; render(true); }
function cardContext(id, e) {
  var r = $("mcanvas").getBoundingClientRect();
  S.selected = id; UI.pop = { id: id, x: e.clientX - r.left, y: e.clientY - r.top, center: false }; render(true);
}
function closePop() { var p = $("mcanvas").querySelector(".pop"); if (p) p.remove(); UI.pop = null; }
function nodeMenu(id) {
  // The op menu, shared by the inspector and the pop-up menu.
  var n = N(id), items = [], blk = editBlock();
  if (blk) return [{ note: blk }];
  if (!n.root) {
    if (canPick()) {
      items.push({ label: S.picks.d === id ? "Clear Doing" : "Set as Doing", sc: "D", fn: function () { pick("d", id); }, dis: S.picks.d === id ? null : pickReason(id, "d") });
      items.push({ label: S.picks.n === id ? "Clear Next" : "Set as Next", sc: "N", fn: function () { pick("n", id); }, dis: S.picks.n === id ? null : pickReason(id, "n") });
      items.push({ sep: true });
    }
    if (finished(id)) items.push({ label: "Mark Open", fn: function () { reopen(id); }, dis: unfinishedDeps(id).length ? "Waiting for " + title(unfinishedDeps(id)[0]) + "." : null });
    else if (n.status !== "crossed") items.push({ label: "Mark Done", fn: function () { markDone(id); } });
    if (n.status === "crossed") items.push({ label: "Restore", fn: function () { restore(id); } });
    else items.push({ label: "Cross Out", sc: "⌫", fn: function () { crossOut(id); } });
    items.push({ sep: true });
  }
  items.push({ label: "Rename", sc: "↩", fn: function () { UI.renaming = id; } });
  items.push({ label: "Add Step Under", sc: "A", fn: function () { var k = addChild(id); if (k) { S.selected = k; UI.renaming = k; } } });
  if (!n.root) {
    items.push({ label: "Add Dependency…", fn: function () { UI.depFor = id; } });
    if (n.deps.length) items.push({ label: "Remove Dependency", fn: function () { removeDep(id); } });
    items.push({ sep: true });
    items.push(n.locked ? { label: "Unlock", fn: function () { setLock(id, false); } } : { label: "Lock (no suggestions)", fn: function () { setLock(id, true); } });
    if (!canPick()) items.push({ note: "Doing and Next are chosen when you plan." });
  }
  return items;
}
// The step menu as a pop-up: on right-click, and on click when the board is too narrow for the inspector.
function openPop(id, x, y) {
  var cv = $("mcanvas"), old = cv.querySelector(".pop"); if (old) old.remove();
  var card = bmap.card(id);
  if (!S.nodes[id] || !card || card.hidden) { UI.pop = null; return; }
  var pop = el("div", "pop");
  nodeMenu(id).forEach(function (it) {
    if (it.sep) { pop.appendChild(el("hr")); return; }
    if (it.note) { pop.appendChild(el("span", "why", it.note)); return; }
    var b = el("button"); b.type = "button"; b.appendChild(el("span", "", it.label)); if (it.sc) b.appendChild(el("span", "sc", it.sc));
    if (it.dis) { b.disabled = true; pop.appendChild(b); pop.appendChild(el("span", "why", it.dis)); return; }
    b.addEventListener("click", act(function () { closePop(); it.fn(); }));
    pop.appendChild(b);
  });
  pop.addEventListener("click", function (e) { e.stopPropagation(); });
  cv.appendChild(pop);
  var w = pop.offsetWidth, h = pop.offsetHeight, W = cv.clientWidth, H = cv.clientHeight;
  if (UI.pop && UI.pop.center) {
    var cr = card.getBoundingClientRect(), r = cv.getBoundingClientRect();
    x = (cr.left + cr.right) / 2 - r.left - w / 2; y = cr.bottom - r.top + 6;
    if (y + h > H - 6) y = Math.max(6, cr.top - r.top - h - 6);
  }
  pop.style.left = Math.max(6, Math.min(W - w - 6, x)) + "px"; pop.style.top = Math.max(6, Math.min(H - h - 6, y)) + "px";
}

function centreNow() {
  var d = canPick() ? commitPair().d : slot("doing");
  if (!d) { toast("Nothing is Doing yet.", true); return; }
  bmap.unfold(d); S.selected = d; render(true); bmap.centre(d);
}
var bmap = MindMap($("mcanvas"), {
  root: goal,
  tops: function () { var hub = goal(); return kids(hub).concat(Object.keys(S.nodes).filter(function (k) { return !N(k).parent && k !== hub; })); },
  kids: kids,
  parent: function (id) { return S.nodes[id] ? N(id).parent : null; },
  ids: function () { return Object.keys(S.nodes); },
  fill: fillCard,
  below: function (id) { return mapProps().some(function (p) { return p.targets[0] === id; }) ? 34 : 0; },
  // Dependencies: dashed arrows, amber while the step waits, grey once what it waited for is done.
  links: function () {
    var out = [];
    Object.keys(S.nodes).forEach(function (id) { if (!isClosed(id)) N(id).deps.forEach(function (d) { if (S.nodes[d]) out.push({ a: d, b: id, cls: "dep" + (finished(d) ? " ok" : ""), head: true }); }); });
    return out;
  },
  edgeCls: function (id) { return isClosed(id) && descendants(id).every(isClosed) ? "done" : ""; },
  focus: function () { return S.selected; },
  folded: UI.folded,
  folds: function () { render(true); },
  overlays: buildProps,
  mmCls: mapStatus,
  click: cardClick, dblclick: cardDbl, context: cardContext,
  enter: function (id) { clearTimeout(picksTimer); if (picksFor !== id) showPicks(id); },
  leave: function () { picksTimer = setTimeout(hidePicks, 120); },
  moved: function () { if (UI.pop) closePop(); },
  // A click on the empty canvas cancels a dependency pick, closes the menu, or clears the selection.
  background: function () { if (UI.depFor) UI.depFor = null; else if (UI.pop) { closePop(); S.selected = null; } else if (S.selected) S.selected = null; else return; render(true); },
  now: centreNow,
  legend: [["--doing", "Doing"], ["--next", "Next"], ["--done", "Done"], ["dash", "Waits for"], ["--rest", "Assistant"]],
  empty: "No steps yet. Add one below."
});
$("maimcancel").addEventListener("click", act(function () { UI.depFor = null; }));
// Card heights are measured; measure again once the web fonts arrive.
if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { lastGraph = ""; });
// Settings › Clear the plan: drop every card.
function resetMap() { bmap.reset(); lastGraph = ""; }
$("quicklog").addEventListener("submit", function (e) {
  e.preventDefault(); var v = $("qlin").value.trim(); if (!v) return;
  var k = addChild(S.selected || goal(), v); if (k) $("qlin").value = "";
  render(true);
});
$("qlin").addEventListener("keydown", function (e) { e.stopPropagation(); });
