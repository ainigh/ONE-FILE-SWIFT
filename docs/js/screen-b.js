/* screen-b.js: B's screen: intake, Ready?, the round, the plan header, and the request strip and cover. */
"use strict";
// ----- the request screen: one component, four states (screen guide §3.3) -----
function approvedLine(to) {
  var p = pairNow();
  var n = to === "work" ? S.round + 1 : to === "snooze" ? S.z + 1 : to === "strategy" ? S.round + 1 : null;
  var fb = reqLabel(to) + ".";
  return line("request_approved", { toPhase: TO_PHASE[to], n: n, doing: title(p.d), next: title(p.n), len: awayFor(S.z, roundCleared()) }, fb);
}
function reqScreen(r) {
  if (!r.verdict) return { kind: "waiting", c: "--ink3", h: "Hang tight.", l: line("request_waiting", { what: reqWhat(r) }, "Waiting for " + aName() + "."), btns: [], meta: UI.auto ? "" : "You answer as " + aName() + ": open A, at the top of the screen, to decide." };
  if (r.verdict === "approved") return { kind: "approved", c: "--done", h: "Ready when you are.", l: approvedLine(r.to_phase), btns: [["Go", "primary", function () { accept(r); }]] };
  return { kind: "refused", c: "--blocked", h: "Not yet.", l: line("request_refused", { reason: r.reason }, r.reason || aName() + " said no."), btns: [["OK", "primary", function () { ack(r); }]] };
}
function endedScreen() {
  var st = S.state, r = S.sys, m = { kind: "ended", c: "--stop", d: digits(S.reading), l: "", btns: [["Go", "primary", function () { accept(r); }]] };
  if (st === "work" || st === "snooze") {
    m.h = "Time's up."; m.q = "Move on to check-up?";
    if (S.z < zMax()) m.btns.push(["Snooze · " + fmt(qU()) + " · " + (zMax() - S.z) + " left", "", function () { raise("snooze"); }]);
    else m.btns.push(["No snoozes left", "none", null]);
  } else if (st === "status") { m.c = "--next"; m.h = "Check-up over."; m.q = "Start planning round " + (S.round + 1) + "?"; }
  else if (st === "strategy") {
    m.c = "--next"; m.h = "Planning over.";
    if (r.to_phase === "break") { m.q = "Start your movement break?"; m.l = "Seated " + seatedMin() + ". Movement break, " + fmt(CFG.Lb) + ", then round " + (S.round + 1) + "."; }
    else m.q = "Start round " + (S.round + 1) + "?";
    if (!S.planChosen) m.l = "Keeping " + title(slot("doing")) + " doing, " + (title(slot("next")) || "nothing") + " next." + (m.l ? " " + m.l : "");
  } else if (st === "break") { m.c = "--rest"; m.h = "Break over."; m.q = "Start round " + (S.round + 1) + "?"; }
  return m;
}
// Strip or cover? B keeps working under a strip during work, snooze and plan; everywhere else
// (idle, check-up, the break, every freeze) the request screen covers B's whole screen.
function stripMode() { return (S.state === "work" || S.state === "snooze" || S.state === "strategy") && !S.frozen; }
function coverModel() {
  var st = S.state, r = openReq();
  if (r && !stripMode()) {
    var m = reqScreen(r);
    if (S.frozen) m.d = digits(S.reading); else if (running()) { m.d = digits(left()); m.tick = true; }
    return m;
  }
  if (S.frozen && S.sys) return endedScreen();
  if (st === "work" && running() && S.lastRem) return { kind: "reminder", c: "--doing", h: fmt(S.lastRem.t) + " left.", d: digits(left()), tick: true, l: "", btns: [["OK", "primary", function () { S.lastRem = null; }]] };
  if (st === "status" && running()) return { kind: "checkup", c: "--ink2", h: "Check-up", d: digits(left()), tick: true, l: S.strip && performance.now() < S.strip.until ? S.strip.text : "", q: "Step away from the desk.", btns: [], ask: true };
  return null;
}

// ----- B's screen -----
function bView() {
  var st = S.state;
  if (!st || st === "idle") return UI.intake.stage === "ready" ? "ready" : "intake";
  if (st === "strategy" || st === "break") return "plan";
  return "round";
}
function hasSteps() { return Object.keys(S.nodes).some(function (k) { return !N(k).root && !isClosed(k); }); }
var lastIntake = "", lastReady = "";
// The intake asks, in turn: your name (once, optional), the minutes per round, then the steps.
function renderIntake() {
  var st = UI.intake.stage, ids = UI.intake.ids.filter(function (k) { return S.nodes[k]; });
  var q = st === "name" ? "What should we call you?" : st === "time" ? "How many minutes per round?"
    : ids.length === 0 ? "What would you like to do now?" : ids.length === 1 ? "What would you like to do next?" : "What else is on your list?";
  var key = st + "|" + q + "|" + ids.map(title).join("|") + "|" + hasSteps() + "|" + UI.names.b + "|" + CFG.R;
  if (key === lastIntake) return;
  var was = lastIntake.split("|")[0];
  lastIntake = key;
  $("in-q").textContent = q;
  var inp = $("in-text");
  if (st === "name") { inp.type = "text"; inp.maxLength = 30; inp.placeholder = "Your name"; inp.removeAttribute("min"); inp.removeAttribute("max"); inp.removeAttribute("inputmode"); }
  else if (st === "time") { inp.type = "number"; inp.min = "1"; inp.max = "120"; inp.step = "1"; inp.inputMode = "numeric"; inp.placeholder = String(CFG.R / 60); inp.removeAttribute("maxlength"); }
  else { inp.type = "text"; inp.maxLength = 60; inp.placeholder = "One step, in a few words"; inp.removeAttribute("min"); inp.removeAttribute("max"); inp.removeAttribute("inputmode"); }
  if (was !== st) inp.value = st === "time" ? String(CFG.R / 60) : "";
  $("in-hint").textContent = st === "name" ? "Optional. The screens use it where they would say B."
    : st === "time" ? "Whole minutes, 1 to 120. Reminders come at a half, a quarter and an eighth of it; " + (CFG.R / 60) + " is what you had."
    : "Press Return after each step. The first becomes Doing, the second Next.";
  $("in-skip").hidden = st !== "name";
  var said = $("in-said"); said.textContent = "";
  if (st !== "name" && UI.names.b && !ids.length) said.appendChild(el("span", "hi", "Hi, " + UI.names.b + "."));
  ids.forEach(function (k) { said.appendChild(el("span", "", title(k))); });
  $("in-cont").hidden = !(st === "ask" && ids.length === 0 && hasSteps());
}
function renderReady() {
  var p = commitPair(), extra = UI.intake.ids.slice(2).filter(function (k) { return S.nodes[k] && k !== p.d && k !== p.n; });
  var key = p.d + "|" + p.n + "|" + extra.map(title).join("|") + "|" + (p.d && title(p.d)) + (p.n && title(p.n)) + "|" + !!openReq();
  if (key === lastReady) return;
  lastReady = key;
  var ul = $("rd-list"); ul.textContent = "";
  function li(cls, a, b) { var x = el("li", cls); x.appendChild(el("span", "", a)); x.appendChild(el("span", "", b)); ul.appendChild(x); }
  li("doing", title(p.d) || "Nothing yet", "doing");
  li("next", title(p.n) || "Nothing yet", "next");
  extra.forEach(function (k) { li("step", title(k), "step"); });
  $("rd-ok").disabled = !!openReq();
}
function renderRound() {
  var st = S.state, len = phaseLen(), lf = left();
  $("r-title").textContent = st === "snooze" ? "Snooze " + S.z + " of " + zMax() : "Round " + S.round;
  $("r-seated").textContent = "Seated " + seatedMin();
  $("r-digits").textContent = digits(lf);
  $("r-digits").classList.toggle("low", st === "work" && lf > 0 && lf <= 60);
  $("r-arc").setAttribute("stroke-dashoffset", (len ? C * (1 - lf / len) : C).toFixed(2));
  $("r-arc").style.stroke = css(st === "status" ? "--ink2" : "--doing");
  $("r-doing").textContent = title(slot("doing")) || "—";
  $("r-next").textContent = title(slot("next")) || "—";
  $("r-phase").disabled = !!openReq() || !running() || (st !== "work" && st !== "snooze");
  $("r-board").textContent = UI.board ? "Close the board ‹" : "Open the board ›";
}
function renderPlanHead() {
  var st = S.state, brk = st === "break";
  $("pl-title").textContent = brk ? "Movement break" : "Plan round " + (S.round + 1);
  $("pl-digits").textContent = digits(S.frozen ? 0 : left());
  $("pl-digits").classList.toggle("low", !brk && !S.frozen && running() && left() <= 15);
  $("pl-start").hidden = brk;
  $("pl-start").textContent = "Start round " + (S.round + 1);
  $("pl-start").disabled = !!openReq() || S.frozen;
}
var lastStrip = "", curStrip = null;
function renderStrip(now) {
  var m = null, r = openReq();
  if (r && stripMode()) m = reqScreen(r);
  else if (running() && S.strip && now < S.strip.until) m = { kind: "reminder", c: tone(), h: S.strip.text, l: "", btns: [] };
  curStrip = m;
  $("bstrip").hidden = !m;
  if (!m) { lastStrip = ""; return; }
  $("bstrip").classList.toggle("fade", m.kind === "reminder" && now > S.strip.until - 700);
  var key = m.kind + "|" + m.h + "|" + m.l + "|" + (r ? r.id : "");
  if (key === lastStrip) return;
  lastStrip = key;
  $("bstrip").style.setProperty("--c", css(m.c));
  $("bs-h").textContent = m.h; $("bs-l").textContent = m.l || ""; $("bs-l").hidden = !m.l;
  var bx = $("bs-b"); bx.textContent = "";
  m.btns.forEach(function (b) { var x = el("button", "btn " + b[1], b[0]); x.type = "button"; x.addEventListener("click", act(b[2])); bx.appendChild(x); });
  if (m.kind === "reminder" && !reduce) { $("bstrip").style.animation = "none"; void $("bstrip").offsetWidth; $("bstrip").style.animation = ""; }
}
var lastCover = "", curCover = null;
function renderCover() {
  var m = UI.role === "b" ? coverModel() : null;
  curCover = m;
  $("cover").hidden = !m;
  if (!m) { lastCover = ""; return; }
  $("cv-d").textContent = m.d || "";
  var key = m.kind + "|" + m.h + "|" + m.l + "|" + (m.q || "") + "|" + m.btns.map(function (b) { return b[0]; }).join(",") + "|" + (S.req ? S.req.id : "") + "|" + (S.sys ? S.sys.id : "") + "|" + (m.meta || "") + "|" + !!openReq();
  if (key === lastCover) return;
  lastCover = key;
  var cv = $("cv");
  cv.className = "cv " + m.kind + (m.tick ? " tick" : "");
  cv.style.setProperty("--c", css(m.c));
  $("cv-h").textContent = m.h;
  $("cv-l").textContent = m.l || ""; $("cv-l").hidden = !m.l;
  $("cv-q").textContent = m.q || ""; $("cv-q").hidden = !m.q;
  $("cv-meta").textContent = m.meta || ""; $("cv-meta").hidden = !m.meta;
  $("cv-ask").hidden = !m.ask; $("cv-ask").disabled = !!openReq();
  var bx = $("cv-b"); bx.textContent = "";
  m.btns.forEach(function (b) {
    if (!b[2]) { bx.appendChild(el("span", b[1], b[0])); return; }
    var x = el("button", "btn " + b[1], b[0]); x.type = "button"; x.addEventListener("click", act(b[2])); bx.appendChild(x);
  });
  setTimeout(function () { var f = bx.querySelector("button"); if (f && document.activeElement && root.contains(document.activeElement)) f.focus({ preventScroll: true }); }, 0);
}
function renderB(now) {
  var v = bView();
  ["intake", "ready", "round", "plan"].forEach(function (k) { $("b-" + k).hidden = k !== (v === "plan" ? "plan" : v); });
  var boardOn = v === "plan" || ((v === "round" || v === "ready") && UI.board);
  var wb = $("wbody");
  wb.classList.toggle("plan", v === "plan"); wb.classList.toggle("split", boardOn && v !== "plan"); wb.classList.toggle("solo", !boardOn);
  $("board").hidden = !boardOn;
  if (v === "intake") renderIntake();
  else if (v === "ready") renderReady();
  else if (v === "round") renderRound();
  else renderPlanHead();
  renderStrip(now);
  if (boardOn) renderBoard();
}
