/* log.js: the event log, shared by A's Log and Admin's Event log. */
"use strict";
// ----- the event log (A's Log, Admin's Event log: one component, moved between them) -----
var lastLogs = "";
(function () {
  var s = $("logpart"), o = el("option", "", "All parts"); o.value = ""; s.appendChild(o);
  Object.keys(PARTS).forEach(function (k) { var x = el("option", "", PARTS[k].t); x.value = k; s.appendChild(x); });
  s.addEventListener("change", function () { UI.logPart = s.value; if (s.value) S.unseen[s.value] = 0; render(true); });
  s.addEventListener("keydown", function (e) { e.stopPropagation(); });
})();
$("logprob").addEventListener("click", act(function () { UI.logProblems = !UI.logProblems; }));
$("logseen").addEventListener("click", act(function () { S.unseen = {}; }));
function renderLogs() {
  var key = logsV + "|" + UI.logPart + "|" + UI.logProblems + "|" + UI.logSel;
  if (key === lastLogs) return;
  lastLogs = key;
  $("logpart").value = UI.logPart;
  $("logprob").setAttribute("aria-pressed", String(UI.logProblems));
  var list = S.events.filter(function (e) { return (!UI.logPart || e.from === UI.logPart || e.to === UI.logPart) && (!UI.logProblems || e.outcome === "warning" || e.outcome === "error"); }).slice().reverse();
  $("logcount").textContent = list.length + (list.length === 1 ? " event" : " events");
  var ol = $("loglist"); ol.textContent = "";
  if (!list.length) ol.appendChild(el("li", "empty", S.events.length ? "Nothing matches." : "Nothing has happened yet."));
  list.slice(0, 250).forEach(function (e) {
    var li = el("li", (e.fresh ? "new" : "") + (UI.logSel === e.id ? " sel" : ""));
    e.fresh = false;
    li.appendChild(el("span", "tm", e.at));
    var d = el("span", "dot"); d.style.background = css(COLORS[e.outcome]); li.appendChild(d);
    li.appendChild(el("span", "rt", route(e)));
    var ti = el("span", "ti", e.title); if (e.outcome === "error") ti.style.color = css("--stop"); li.appendChild(ti);
    li.addEventListener("click", act(function () { UI.logSel = e.id; }));
    ol.appendChild(li);
  });
  var sel = S.events.filter(function (e) { return e.id === UI.logSel; })[0], det = $("ldetail");
  det.textContent = "";
  if (!sel) { det.appendChild(el("h4", "", "Select an event")); det.appendChild(el("p", "meta", "Select an event to see its detail. The newest are at the top.")); return; }
  det.appendChild(el("h4", "", sel.title));
  det.appendChild(el("p", "meta", [route(sel), OUTWORD[sel.outcome], sel.at].concat(sel.turn ? ["turn " + sel.turn] : []).join(" · ")));
  if (sel.detail) det.appendChild(el("pre", "", sel.detail));
}
