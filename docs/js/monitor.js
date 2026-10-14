/* monitor.js: host events, the Admin's Monitor that draws them, and the Admin screen. */
"use strict";
// ----- host events: what the Monitor draws and the Log lists (DESIGN §12) -----
// The parts of the app, as the Monitor draws them: the Session engine is the hub; each part hangs
// off the one it mostly hands off to, on the side of the people (left) or of the plan and the
// assistant (right). LINKS are the hand-offs that do not follow the tree.
var PARTS = {
  engine: { t: "Session engine", what: "Runs the session: holds the clocks, routes every request, and changes phase on Go." },
  timers: { t: "Timers", up: "engine", side: "l", what: "Ends each phase when its clock runs out and raises the System's request." },
  man: { t: "B", up: "engine", side: "l", what: "The person working: picks Doing and Next, edits the plan, asks to move on, presses Go." },
  a: { t: "A", up: "engine", side: "l", what: "Answers B's requests to change phase, or leaves them to the policy." },
  policy: { t: "Policy", up: "engine", side: "l", what: "Decides requests on A's behalf while autopilot is on." },
  output: { t: "B's screen", up: "engine", side: "r", what: "What B sees and hears: the screens, the strip and the cover, the voice." },
  coordinator: { t: "Turns", up: "engine", side: "r", what: "Runs the assistant's one turn per round and holds its answer until planning." },
  model: { t: "Assistant", up: "coordinator", what: "The built-in assistant: reads the plan, writes a note for B, proposals and a brief for A." },
  scheduler: { t: "Initiative", up: "coordinator", what: "Scheduled look-ins from Settings › Schedule." },
  store: { t: "Store", up: "engine", side: "r", what: "The plan: every change is a patch, logged with its round, and undoable." },
  disk: { t: "Storage", up: "store", what: "This browser's storage, where the plan is kept between visits." }
};
var LINKS = [["man", "store"], ["man", "coordinator"], ["coordinator", "store"], ["coordinator", "output"], ["coordinator", "a"]];
var COLORS = { info: "--doing", ok: "--done", warning: "--blocked", error: "--stop" };
var OUTWORD = { info: "Hand-off", ok: "Done", warning: "Warning", error: "Error" };
function pad2(n) { return String(n).padStart(2, "0"); }
function stamp(ms) { var d = new Date(ms); return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds()); }
function route(e) { return PARTS[e.from].t + (e.to ? " → " + PARTS[e.to].t : ""); }
var logsV = 0;
function ev(from, to, outcome, ttl, detail, turn) {
  var e = { id: ++S.evId, at: stamp(S.W), from: from, to: to || null, outcome: outcome, title: ttl, detail: detail || "", turn: turn || null, fresh: true };
  S.events.push(e); if (S.events.length > 600) S.events.shift();
  if (outcome === "warning" || outcome === "error") { var k = to || from; S.unseen[k] = (S.unseen[k] || 0) + 1; }
  mon.onEvent(e); logsV++;
  if (from === "man" && to !== "a" && to !== "policy") notify(e);
}
// What B does, as A sees it: a note on A's screen that fades after five seconds. A patch is told
// by its operations rather than its number; everything else by the event's own title.
var NOTE_MS = 5000;
function notify(e) {
  var text = e.title;
  if (/^patch \d+:/.test(text)) {
    var ops = e.detail.split("\n").slice(1).filter(function (l) { return l && l.indexOf("unblocked:") !== 0; }).map(function (l) { return l.replace(/^(\w+?)_(\w+) /, "$1 $2 "); });
    if (ops.length) text = ops.join(" · ");
  }
  S.notes.push({ id: e.id, text: text, warn: e.outcome === "warning" || e.outcome === "error", at: performance.now() });
  if (S.notes.length > 6) S.notes.shift();
}
// The Monitor: the parts as a mind map (mapview.js, the same map as B's board). A card says what
// the part last handled; its dot, the outcome. Working is filled (A has a request to answer, the
// assistant's turn runs, with a bar for its deadline); unseen problems are dashed, with a count.
// Every hand-off runs its line. Click a part for its latest; double-click opens it in the log.
var mon = (function () {
  var info = {}, keys = {}, sel = null, measured = false, lastSp = "";
  Object.keys(PARTS).forEach(function (k) { info[k] = { sub: "Quiet", last: null }; });
  function under(k) { return Object.keys(PARTS).filter(function (x) { return PARTS[x].up === k; }); }
  function working(k) {
    if (k === "model" && S.state === "status" && running() && S.turn && !S.turn.done) return S.turn;
    if (k === "a" && openReq() && !S.req.verdict) return { req: true };
    return null;
  }
  function phaseLine() {
    if (!S.state) return "No session";
    var w = { idle: "Idle", work: "Round " + S.round, snooze: "Snooze " + S.z, status: "Check-up", strategy: "Planning", "break": "Break" }[S.state] || S.state;
    return S.frozen ? w + " · waiting for Go" : running() ? w + " · " + digits(left()) + " left" : w;
  }
  function used(w) { return w && w.since != null ? Math.min(1, (S.T - w.since) / Math.max(1, w.deadline - w.since)) : null; }
  function cardKey(k) {
    var w = working(k), u = used(w);
    return info[k].sub + "|" + info[k].last + "|" + (S.unseen[k] || 0) + "|" + (w ? "w" : "") + (u != null ? Math.round(u * 100) : "") + "|" + (sel === k) + (k === "engine" ? "|" + phaseLine() : "");
  }
  function fill(c, k) {
    var p = PARTS[k], n = info[k], w = working(k), cnt = S.unseen[k] || 0;
    c.className = "card part" + (k === "engine" ? " goal" : "") + (w ? " doing" : cnt ? " blocked" : "") + (sel === k ? " sel" : "");
    c.textContent = "";
    c.title = p.t + ": " + p.what;
    if (k === "engine") {
      var len = running() ? phaseLen() : 0, pct = len ? 1 - left() / len : 0, R = 2 * Math.PI * 14;
      c.appendChild(el("span", "label", "Hub"));
      c.appendChild(el("span", "tt", p.t));
      var r = el("span", "ring");
      r.innerHTML = '<svg viewBox="0 0 34 34" aria-hidden="true"><circle cx="17" cy="17" r="14" stroke="var(--line)"/><circle cx="17" cy="17" r="14" stroke="var(' + tone() + ')" stroke-dasharray="' + R.toFixed(1) + '" stroke-dashoffset="' + (R * (1 - pct)).toFixed(1) + '" stroke-linecap="round" transform="rotate(-90 17 17)"/></svg>';
      r.appendChild(el("span", "", phaseLine()));
      c.appendChild(r);
      c.appendChild(el("span", "sub", n.sub));
      c.setAttribute("aria-label", p.t + ", " + phaseLine() + ", last: " + n.sub);
      return;
    }
    var st = el("span", "st"); if (n.last) st.style.background = css(COLORS[n.last]); c.appendChild(st);
    var t = el("span", "tw"); t.appendChild(el("span", "tt", p.t)); t.appendChild(el("span", "sub", n.sub)); c.appendChild(t);
    if (cnt) { var meta = el("span", "meta"); meta.appendChild(el("span", "tag", String(cnt))); c.appendChild(meta); }
    var u = used(w); if (u != null) { var bar = el("span", "bar"), i = el("i"); i.style.width = (u * 100).toFixed(1) + "%"; bar.appendChild(i); c.appendChild(bar); }
    c.setAttribute("aria-label", p.t + (w ? ", working" : "") + (cnt ? ", " + cnt + " unseen problem" + (cnt === 1 ? "" : "s") : "") + ", last: " + n.sub);
  }
  function openLog(k) { S.unseen[k] = 0; UI.logPart = k; UI.adTab = "log"; placePanels(); render(true); }
  function choose(k) { sel = sel === k ? null : k; keys = {}; map.drawEdges(); lastSp = ""; }
  var map = MindMap($("moncanvas"), {
    root: function () { return "engine"; }, tops: function () { return under("engine"); }, kids: under,
    parent: function (k) { return PARTS[k] && PARTS[k].up || null; },
    ids: function () { return Object.keys(PARTS); }, side: function (k) { return PARTS[k].side; },
    fill: fill, cardW: 196, hubW: 220,
    links: function () { return LINKS.map(function (l) { return { a: l[0], b: l[1], cls: "link" }; }); },
    focus: function () { return sel; },
    mmCls: function (k) { return working(k) ? "doing" : S.unseen[k] ? "blocked" : ""; },
    // Beside a narrow map there is no room for the inspector: a click opens the part's events instead.
    click: function (k) { if ($("monsp").offsetWidth) choose(k); else openLog(k); },
    dblclick: openLog,
    background: function () { if (sel) choose(sel); },
    legend: [["--doing", "Hand-off"], ["--done", "Done"], ["--blocked", "Warning"], ["--stop", "Error"], ["link", "Also hands off"]]
  });
  function onEvent(e) {
    info[e.from].sub = e.title;
    if (e.to) info[e.to].sub = e.title;
    if (e.outcome !== "info") { info[e.from].last = e.outcome; if (e.to) info[e.to].last = e.outcome; }
    if (e.to && UI.role === "admin" && UI.adTab === "monitor") map.pulse(e.from, e.to, COLORS[e.outcome]);
    $("mon-last").textContent = e.at + " · " + route(e) + " · " + e.title;
  }
  function reset() { Object.keys(info).forEach(function (k) { info[k].sub = "Quiet"; info[k].last = null; }); keys = {}; $("mon-last").textContent = ""; }
  // The inspector: what the part does, who it hands off to, and its latest events.
  function renderSp() {
    var box = $("monsp"), k = sel && PARTS[sel] ? sel : null;
    var key = k + "|" + logsV + "|" + (k ? (S.unseen[k] || 0) + "|" + !!working(k) + "|" + info[k].last : "");
    if (key === lastSp) return;
    lastSp = key; box.textContent = "";
    if (!k) {
      var e0 = el("div", "empty"); e0.appendChild(el("b", "", "Nothing selected"));
      e0.appendChild(document.createTextNode("Click a part for what it does and its latest hand-offs. Double-click opens its events in the log. "));
      e0.appendChild(el("kbd", "", "F")); e0.appendChild(document.createTextNode(" fits the map."));
      box.appendChild(e0); return;
    }
    var p = PARTS[k], w = working(k), cnt = S.unseen[k] || 0, head = el("div", "sec");
    head.appendChild(el("div", "pname", p.t));
    head.appendChild(el("div", "path", p.what));
    var stat = el("div", "stat"), dot = el("i");
    dot.style.background = css(w ? "--doing" : cnt ? "--blocked" : info[k].last ? COLORS[info[k].last] : "--ink3");
    stat.appendChild(dot); stat.appendChild(el("span", "", w ? (w.req ? "Has a request to answer" : "Working, on a deadline") : cnt ? cnt + " unseen problem" + (cnt === 1 ? "" : "s") : info[k].last ? OUTWORD[info[k].last] + " last" : "Quiet"));
    head.appendChild(stat); box.appendChild(head);
    var kv = el("div", "sec kv"), talks = el("span"), mine = S.events.filter(function (x) { return x.from === k || x.to === k; });
    var near = {}; if (p.up) near[p.up] = 1; under(k).forEach(function (x) { near[x] = 1; }); LINKS.forEach(function (l) { if (l[0] === k) near[l[1]] = 1; if (l[1] === k) near[l[0]] = 1; });
    Object.keys(near).forEach(function (x) { var b = el("button", "chip", PARTS[x].t); b.type = "button"; b.addEventListener("click", function () { choose(x); }); talks.appendChild(b); });
    kv.appendChild(el("span", "", "Hands off to")); kv.appendChild(talks);
    kv.appendChild(el("span", "", "Events")); kv.appendChild(el("span", "", String(mine.length)));
    box.appendChild(kv);
    var ls = el("div", "sec evs"); ls.appendChild(el("span", "label", "Latest"));
    if (!mine.length) ls.appendChild(el("span", "why", "Nothing yet."));
    mine.slice(-6).reverse().forEach(function (x) {
      var b = el("button"); b.type = "button"; b.title = route(x) + " · " + OUTWORD[x.outcome];
      var d = el("i"); d.style.background = css(COLORS[x.outcome]); b.appendChild(d);
      b.appendChild(el("span", "tm", x.at)); b.appendChild(el("span", "ti", x.title));
      b.addEventListener("click", function () { UI.logSel = x.id; openLog(k); });
      ls.appendChild(b);
    });
    box.appendChild(ls);
    var acts = el("div", "sec acts"), ob = el("button"); ob.type = "button"; ob.appendChild(el("span", "", "Open in the event log"));
    ob.addEventListener("click", function () { openLog(k); }); acts.appendChild(ob);
    if (cnt) { var sb = el("button"); sb.type = "button"; sb.appendChild(el("span", "", "Mark seen")); sb.addEventListener("click", act(function () { S.unseen[k] = 0; })); acts.appendChild(sb); }
    box.appendChild(acts);
  }
  // Cards are measured, so the map is laid out the first time it is seen, and again once the fonts arrive.
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { measured = false; });
  function draw(now) {
    if (!measured) { if (!$("moncanvas").offsetWidth) return; measured = true; keys = {}; map.render(); }
    map.tick(now);
    Object.keys(PARTS).forEach(function (k) { var key = cardKey(k); if (keys[k] !== key) { keys[k] = key; map.refill(k); } });
    renderSp();
  }
  return { onEvent: onEvent, draw: draw, reset: reset, fit: function () { map.fit(true); } };
})();

function renderAdmin() {
  Array.prototype.forEach.call($("adseg").querySelectorAll("button"), function (b) { b.setAttribute("aria-selected", String(b.getAttribute("data-t") === UI.adTab)); });
  $("adp-monitor").hidden = UI.adTab !== "monitor"; $("adp-log").hidden = UI.adTab !== "log";
  if (UI.adTab === "log") renderLogs();
}
