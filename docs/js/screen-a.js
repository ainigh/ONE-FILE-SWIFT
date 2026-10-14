/* screen-a.js: A's screen: the clock box, the boxes (one per request) in a grid, and the drawer
   with the full table, the grid and the log. */
"use strict";
// ----- A: every request is a box; the newest four are full, older ones fade, past 16 they go -----
var BOX_FULL = 4, BOX_MAX = 16;
var lastQ = "", lastRQ = "";
function polWord(p) { return p[0] === "approved" ? "approve" : "refuse"; }
function whoWord(by) { return by === "a" ? "you" : "policy"; }
function boxKey(x) { return x.id + x.verdict + x.outcome + x.to_phase + (x.accepted_at ? "a" : ""); }
// The live request: the policy's default beside it, Approve, and Refuse with a reason.
function liveBox(r) {
  var c = el("div", "abox live");
  c.style.setProperty("--c", css("--next"));
  c.appendChild(el("span", "label", bName() + " asks" + (r.round ? " · round " + r.round : "") + " · sent " + stamp(r.sent_at)));
  c.appendChild(el("h4", "", r.label));
  var pol = el("p", "pol"); pol.appendChild(document.createTextNode("Policy says "));
  pol.appendChild(el("b", r.policy[0] === "approved" ? "ok" : "no", polWord(r.policy)));
  if (r.policy[1]) pol.appendChild(document.createTextNode(": “" + r.policy[1] + "”"));
  c.appendChild(pol);
  if (UI.reasonFor !== r.id) { UI.reasonFor = r.id; UI.reason = r.policy[0] === "refused" ? r.policy[1] : ""; }
  var f = el("form"), inp = el("input"); inp.placeholder = "Reason, shown to " + bName() + " (needed to refuse)"; inp.setAttribute("aria-label", "Reason"); inp.value = UI.reason;
  var ok = el("button", "btn primary", "Approve"); ok.type = "button";
  var no = el("button", "btn", "Refuse"); no.type = "submit";
  var cant = cannotApprove(r);
  if (cant) { ok.disabled = true; ok.title = cant; }
  no.disabled = !UI.reason.trim();
  inp.addEventListener("input", function () { UI.reason = inp.value; no.disabled = !inp.value.trim(); });
  inp.addEventListener("keydown", function (e) { e.stopPropagation(); });
  ok.addEventListener("click", act(function () { decide(r, "approved", "", "a"); }));
  f.addEventListener("submit", function (e) { e.preventDefault(); if (!UI.reason.trim()) { inp.focus(); return; } decide(r, "refused", UI.reason.trim(), "a"); render(true); });
  var row = el("div", "acts"); row.appendChild(ok); row.appendChild(no);
  f.appendChild(inp); f.appendChild(row);
  c.appendChild(f);
  c.appendChild(el("p", "muted", cant ? "Approve is off: " + cant : bName() + "'s clock keeps running while you decide."));
  return c;
}
// A decided or closed request: what was asked, what was answered, and where it stands.
function pastBox(x) {
  var open = !x.outcome, sys = x.raised_by === "system";
  var c = el("div", "abox" + (open ? " open" : " done"));
  c.style.setProperty("--c", css(x.verdict === "approved" ? "--done" : x.verdict === "refused" ? "--blocked" : "--ink3"));
  c.appendChild(el("span", "label", (sys ? (open ? "System · frozen" : "System") : bName() + " asked") + (x.round ? " · round " + x.round : "") + " · " + x.id));
  c.appendChild(el("h4", "", x.label));
  var v = el("p", "pol");
  if (!x.verdict) v.appendChild(el("b", "", "Waiting"));
  else {
    v.appendChild(el("b", x.verdict === "approved" ? "ok" : "no", x.verdict === "approved" ? "Approved" : "Refused"));
    v.appendChild(document.createTextNode(" by " + whoWord(x.decided_by) + (x.decided_by === "a" && x.verdict !== x.policy[0] ? ", against the policy" : "") + (x.reason ? ": “" + x.reason + "”" : "")));
  }
  c.appendChild(v);
  var st;
  if (open) st = sys ? "The clock stopped. Nothing runs until " + bName() + " presses Go." : "Waiting for " + bName() + " to press " + (x.verdict === "approved" ? "Go." : "OK.");
  else if (x.outcome === "accepted") st = bName() + (sys ? " pressed Go after " : " went after ") + fmt((x.accepted_at - x.decided_at) / 1000) + ".";
  else if (x.outcome === "acknowledged") st = bName() + " pressed OK.";
  else st = "Overtaken: the clock ran out first.";
  c.appendChild(el("p", "muted", st));
  return c;
}
// The assistant's brief for A, shown while B plans.
function briefBox(h) {
  var c = el("div", "abox brief");
  c.style.setProperty("--c", css("--next"));
  c.appendChild(el("span", "label", "From the assistant, for " + aName()));
  c.appendChild(el("p", "pol", h.brief ? h.brief.text : "No brief this round: the model did not answer in time."));
  c.appendChild(el("p", "muted", h.brief ? h.brief.forA : "The session goes on as usual."));
  return c;
}
function emptyBox() {
  var c = el("div", "abox empty");
  c.appendChild(el("h4", "", S.state ? "Nothing to decide" : "No session yet"));
  c.appendChild(el("p", "muted", !S.state ? bName() + " is on the intake screen. The first request lands here when " + bName() + " presses OK."
    : UI.auto ? "The policy answers every request at once. Switch “Who answers” to You to decide them yourself."
    : "When " + bName() + " presses Next phase, Snooze or asks to end, the request lands here with the policy's default beside it."));
  return c;
}
function renderBoxes() {
  var r = openReq(), waiting = r && !r.verdict, h = S.held, brief = S.state === "strategy" && h && (h.brief || h.failed);
  var list = S.requests.filter(function (x) { return x.session_id === S.sessionId; }).slice().reverse().slice(0, BOX_MAX);
  var key = list.map(boxKey).join(",") + "|" + UI.auto + "|" + (S.state || "") + S.frozen + "|" + (waiting ? cannotApprove(r) : "") + "|" + (brief ? "b" : "") + "|" + (S.sessionId || "") + "|" + UI.names.b + "|" + UI.names.a;
  if (key === lastQ) return;
  var fresh = lastQ === "";
  lastQ = key;
  var box = $("aboxes"); box.textContent = "";
  var cards = [];
  if (brief) cards.push(briefBox(h));
  list.forEach(function (x) { cards.push(x === r && waiting ? liveBox(x) : pastBox(x)); });
  if (!cards.length) cards.push(emptyBox());
  cards.slice(0, BOX_MAX).forEach(function (c, i) {
    c.style.setProperty("--age", String(Math.max(0, i - (BOX_FULL - 1))));
    if (i >= BOX_FULL) c.classList.add("old");
    if (fresh || i > 0) c.classList.add("still");
    box.appendChild(c);
  });
}
// The full table, in the drawer.
function renderTable() {
  var hk = S.requests.map(boxKey).join(",") + "|" + (S.sessionId || "") + "|" + UI.names.b + "|" + UI.names.a;
  if (hk === lastRQ) return;
  lastRQ = hk;
  var body = $("rqbody"); body.textContent = "";
  var list = S.requests.filter(function (x) { return x.session_id === S.sessionId; }).slice().reverse();
  if (!list.length) { var tr0 = el("tr"), td0 = el("td", "empty", "No requests yet. Every phase change is one: " + bName() + " asks, or the System raises one when a clock runs out."); td0.colSpan = 9; tr0.appendChild(td0); body.appendChild(tr0); }
  var over = 0, frz = 0;
  list.forEach(function (x) {
    var tr = el("tr");
    tr.appendChild(el("td", "m", x.id));
    tr.appendChild(el("td", "m", String(x.round)));
    tr.appendChild(el("td", "", x.label));
    tr.appendChild(el("td", "", x.raised_by === "system" ? "System" : bName()));
    tr.appendChild(el("td", x.policy[0] === "approved" ? "ok" : "no", polWord(x.policy)));
    var vd = el("td", x.verdict ? (x.verdict === "approved" ? "ok" : "no") : "", x.verdict ? x.verdict + (x.decided_by === "a" ? " by " + aName() : "") : "waiting");
    if (x.decided_by === "a" && x.verdict !== x.policy[0]) { vd.appendChild(el("span", "ov", " ≠ policy")); over++; }
    tr.appendChild(vd);
    tr.appendChild(el("td", "m", x.decided_at ? fmt((x.decided_at - x.sent_at) / 1000) : "…"));
    var bt = x.accepted_at && x.decided_at ? (x.raised_by === "system" ? "freeze " : "") + fmt((x.accepted_at - x.decided_at) / 1000) : "";
    if (x.raised_by === "system" && x.accepted_at) frz += (x.accepted_at - x.decided_at) / 1000;
    tr.appendChild(el("td", "m", bt));
    tr.appendChild(el("td", x.outcome === "overtaken" ? "ov" : "", x.outcome || "open"));
    body.appendChild(tr);
  });
  $("rqsum").textContent = list.length + (list.length === 1 ? " request" : " requests") + " · " + over + (over === 1 ? " override" : " overrides") + " · frozen " + fmt(frz);
}
// B's doings, as notes that fade: five seconds each, newest at the bottom.
var lastNotes = "";
function renderNotes(now) {
  S.notes = S.notes.filter(function (n) { return now - n.at < NOTE_MS; });
  var key = S.notes.map(function (n) { return n.id + (now - n.at > NOTE_MS - 700 ? "f" : ""); }).join(",") + "|" + UI.names.b;
  if (key === lastNotes) return;
  lastNotes = key;
  var box = $("anotes"); box.textContent = "";
  S.notes.forEach(function (n) {
    var c = el("div", "anote" + (n.warn ? " warn" : "") + (now - n.at > NOTE_MS - 700 ? " fade" : "") + (now - n.at > 300 ? " still" : ""));
    c.appendChild(el("span", "label", bName()));
    c.appendChild(el("span", "t", n.text));
    box.appendChild(c);
  });
}
var A_HINTS = { table: "Every request this session. You approve or refuse; you never start or stop a clock.", grid: bName() + "'s plan, read only, round by round", log: "Every event, newest first" };
function renderA() {
  var st = S.state, now = performance.now();
  $("a-state").textContent = st ? PHASE[st] + (S.frozen ? " ended" : "") + (S.round ? " · round " + S.round : "") : "No session yet";
  $("aclock").style.setProperty("--c", css(tone()));
  $("a-digits").textContent = running() ? digits(left()) : S.frozen ? digits(S.reading) : "—";
  $("a-digits").classList.toggle("low", st === "work" && running() && left() <= 60);
  $("a-meta").textContent = st ? (title(pairNow().d) || "—") + " doing · " + (title(pairNow().n) || "—") + " next · seated " + seatedMin() : bName() + " is on the intake screen";
  var rem = running() && S.strip && now < S.strip.until;
  $("a-rem").hidden = !rem; if (rem) $("a-rem").textContent = S.strip.text;
  if (document.activeElement !== $("aname")) $("aname").value = UI.names.a;
  Array.prototype.forEach.call($("aswho").querySelectorAll("button"), function (b) { b.setAttribute("aria-selected", String((b.getAttribute("data-auto") === "1") === UI.auto)); });
  Array.prototype.forEach.call($("aseg").querySelectorAll("button"), function (b) { b.setAttribute("aria-pressed", String(b.getAttribute("data-t") === UI.aTab)); });
  renderBoxes();
  renderNotes(now);
  $("adrawer").hidden = !UI.aTab;
  if (!UI.aTab) return;
  ["table", "grid", "log"].forEach(function (k) { $("ap-" + k).hidden = k !== UI.aTab; });
  $("a-hint").textContent = A_HINTS[UI.aTab] || "";
  if (UI.aTab === "table") renderTable(); else if (UI.aTab === "grid") renderGrid(); else renderLogs();
}
