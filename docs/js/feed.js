/* feed.js: A's feed: everything A's screen shows, pushed to a URL set under Admin › Feed.
   One way only: the app sends; nothing comes back and nothing is read from the reply. */
"use strict";
// Each message is one POST with a JSON body, sent as text/plain so no CORS preflight stands in the
// way, in no-cors mode so a receiver without CORS headers still gets it. The reply is never read.
var FEED_KEEP = 12;
var feedSeq = 0, feedQueue = [], feedBusy = false, feedLog = [], feedFails = 0, feedV = 0;
function feedEnvelope(kind, data) {
  return { v: 1, seq: ++feedSeq, kind: kind, at: new Date(S.W).toISOString(), session: S.sessionId || null, round: S.round,
    state: S.state, frozen: S.frozen, left: running() ? Math.round(left()) : null, names: { a: UI.names.a || null, b: UI.names.b || null }, data: data || {} };
}
function feedReq(r) {
  return { id: r.id, label: r.label, round: r.round, from_phase: r.from_phase, to_phase: r.to_phase, raised_by: r.raised_by, sent_at: Math.round(r.sent_at),
    policy: r.policy ? { verdict: r.policy[0], reason: r.policy[1] || "" } : null, verdict: r.verdict, decided_by: r.decided_by, decided_at: r.decided_at && Math.round(r.decided_at),
    reason: r.reason || "", accepted_at: r.accepted_at && Math.round(r.accepted_at), outcome: r.outcome, cannot_approve: r.verdict ? null : cannotApprove(r) };
}
// pushA: called wherever A's screen learns something. A no-op until a URL is set and the feed is on.
function pushA(kind, data) {
  if (!UI.feed.on || !UI.feed.url) return;
  feedQueue.push(feedEnvelope(kind, data));
  if (feedQueue.length > 50) feedQueue.shift();
  feedDrain();
}
function feedDrain() {
  if (feedBusy || !feedQueue.length) return;
  var m = feedQueue.shift(), url = UI.feed.url, body = JSON.stringify(m);
  feedBusy = true;
  var done = function (ok, why) {
    feedBusy = false;
    feedLog.push({ seq: m.seq, kind: m.kind, at: m.at, ok: ok, why: why || "" }); if (feedLog.length > FEED_KEEP) feedLog.shift();
    feedV++;
    if (ok) { if (feedFails) ev("feed", null, "ok", "feed delivering again", "after " + feedFails + " failed"); feedFails = 0; }
    else { feedFails++; if (feedFails === 1) ev("a", "feed", "warning", "feed: not delivered", why + "\n" + url + "\nlater failures in a row are counted, not logged"); }
    feedDrain();
  };
  try {
    if (typeof fetch !== "function") { done(false, "no fetch in this browser"); return; }
    fetch(url, { method: "POST", mode: "no-cors", keepalive: true, headers: { "Content-Type": "text/plain;charset=UTF-8" }, body: body })
      .then(function () { done(true); }, function (e) { done(false, e && e.message ? e.message : "network error"); });
  } catch (e) { done(false, e.message || "could not send"); }
}
function feedUrlOk(u) { return /^https?:\/\/\S+$/i.test(u); }
function setFeed(url, on) {
  url = (url || "").trim();
  var was = UI.feed.url + "|" + UI.feed.on;
  UI.feed = { url: url, on: !!on && feedUrlOk(url) };
  if (was === UI.feed.url + "|" + UI.feed.on) return;
  saveSettings(); feedV++;
  if (UI.feed.on) pushA("hello", { note: "A's feed from Machine Prompts Man: one POST per thing A's screen shows; nothing is read back." });
  ev("man", "feed", "info", UI.feed.on ? "feed on" : url ? "feed off" : "feed cleared", UI.feed.url || "");
}
// ----- Admin › Feed -----
var feedBuilt = false, lastFeed = "";
function renderFeed() {
  var p = $("adp-feed");
  if (!feedBuilt) {
    feedBuilt = true;
    var box = el("div", "feedbox");
    box.appendChild(el("h4", "", "A's feed"));
    box.appendChild(el("p", "muted", "Everything A's screen shows is also sent to this URL: each request as it arrives, every verdict and outcome, what " + bName() + " does, the clock at each phase change, each reminder, and the assistant's brief. One way only: the app sends and never reads a reply or takes a command."));
    var f = el("form", "feedform"), inp = el("input"); inp.type = "url"; inp.id = "feedurl"; inp.placeholder = "https://example.com/a-feed"; inp.value = UI.feed.url; inp.setAttribute("aria-label", "Feed URL"); inp.spellcheck = false; inp.autocomplete = "off";
    inp.addEventListener("keydown", function (e) { e.stopPropagation(); });
    var on = el("button", "btn primary", "Save"); on.type = "submit";
    var off = el("button", "btn", "Turn off"); off.type = "button"; off.id = "feedoff";
    off.addEventListener("click", act(function () { setFeed($("feedurl").value, false); }));
    var test = el("button", "btn", "Send a test"); test.type = "button"; test.id = "feedtest";
    test.addEventListener("click", act(function () { pushA("test", { note: "sent from Admin › Feed" }); }));
    f.addEventListener("submit", function (e) { e.preventDefault(); var u = inp.value.trim(); if (!feedUrlOk(u)) { toast("A URL starting with http:// or https://"); inp.focus(); return; } setFeed(u, true); render(true); });
    f.appendChild(inp); f.appendChild(on); f.appendChild(off); f.appendChild(test);
    box.appendChild(f);
    var stt = el("p", "fine"); stt.id = "feedstate"; box.appendChild(stt);
    var ol = el("ol", "feedlog"); ol.id = "feedlog"; box.appendChild(ol);
    box.appendChild(el("p", "fine", "Each message is one POST with a JSON body: { v, seq, kind, at, session, round, state, frozen, left, names, data }. Kinds: hello, test, session, phase, reminder, request, verdict, outcome, note, brief. The body is sent as text/plain, so a plain endpoint needs no CORS setup, and the reply is not read."));
    p.appendChild(box);
  }
  var key = UI.feed.url + "|" + UI.feed.on + "|" + feedV + "|" + feedQueue.length;
  if (key === lastFeed) return;
  lastFeed = key;
  if (document.activeElement !== $("feedurl")) $("feedurl").value = UI.feed.url;
  $("feedoff").disabled = !UI.feed.on; $("feedtest").disabled = !UI.feed.on;
  var last = feedLog[feedLog.length - 1];
  $("feedstate").textContent = !UI.feed.url ? "No URL yet. Nothing is sent." : !UI.feed.on ? "Off. Nothing is sent." : last ? (last.ok ? "On. Last sent " + stamp(Date.parse(last.at)) + " (" + last.kind + ")." : "On, but the last send failed: " + last.why + ".") + (feedFails > 1 ? " " + feedFails + " failed in a row." : "") : "On. Waiting for the first thing to send.";
  var ol2 = $("feedlog"); ol2.textContent = "";
  feedLog.slice().reverse().forEach(function (x) {
    var li = el("li", x.ok ? "ok" : "no");
    li.appendChild(el("span", "tm", stamp(Date.parse(x.at)))); li.appendChild(el("span", "k", x.kind)); li.appendChild(el("span", "w", x.ok ? "sent" : x.why));
    ol2.appendChild(li);
  });
}
