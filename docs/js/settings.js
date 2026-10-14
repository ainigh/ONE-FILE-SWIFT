/* settings.js: the Settings sheet: session, assistant, general and schedule. Saved in this browser. */
"use strict";
// ----- sheets: Settings and Schedule -----
var draft = null, sheetTab = "session", clearArmed = false;
function openSheet(tab) { UI.sheet = "settings"; draft = { cfg: JSON.parse(JSON.stringify(nextCfg || CFG)), model: UI.model, voice: UI.voice, muted: UI.muted, names: { b: UI.names.b, a: UI.names.a } }; sheetTab = tab || "session"; clearArmed = false; buildSheet(true); }
function closeSheet() { UI.sheet = null; clearArmed = false; $("sheetwrap").hidden = true; $("sheetwrap").textContent = ""; }
function opts(values, cur, label, fn) {
  var box = el("span", "opts"); box.setAttribute("role", "group"); box.setAttribute("aria-label", label);
  values.forEach(function (v) { var b = el("button", "", v[1]); b.type = "button"; b.setAttribute("aria-pressed", String(v[0] === cur)); b.addEventListener("click", function () { fn(v[0]); buildSheet(); }); box.appendChild(b); });
  return box;
}
function txt(value, label, attrs, fn) {
  var i = el("input", "txt"); i.value = value; i.setAttribute("aria-label", label);
  for (var k in attrs) i.setAttribute(k, attrs[k]);
  i.addEventListener("change", function () { fn(i.value); buildSheet(); });
  return i;
}
function kv(label, sub, right) { var d = el("div", "kv"), l = el("span", "", label); if (sub) l.appendChild(el("span", "c2", sub)); d.appendChild(l); d.appendChild(right); return d; }
function radios(name, list, cur, fn) {
  var g = el("div", "grp");
  list.forEach(function (m) {
    var lab = el("label", "ck"), r = el("input"); r.type = "radio"; r.name = name; r.checked = cur === m[0];
    r.addEventListener("change", function () { fn(m[0]); });
    var t = el("span", "", m[1]); t.appendChild(el("span", "c2", m[2])); lab.appendChild(r); lab.appendChild(t);
    var d = el("div", "kv"); d.appendChild(lab); g.appendChild(d);
  });
  return g;
}
function buildSheet(opening) {
  var w = $("sheetwrap"), hadFocus = w.contains(document.activeElement), top = w.scrollTop;
  w.textContent = ""; w.hidden = false;
  var sh = el("div", "sheet" + (opening ? " enter" : "")); sh.setAttribute("role", "dialog"); sh.setAttribute("aria-label", "Settings");
  sh.addEventListener("click", function (e) { e.stopPropagation(); });
  sh.addEventListener("keydown", function (e) { e.stopPropagation(); if (e.key === "Escape") { closeSheet(); root.focus({ preventScroll: true }); } });
  var head = el("div", "sheethead");
  head.appendChild(el("span", "sheettitle", "Settings"));
  var x = el("button", "linkish", "Close"); x.type = "button"; x.setAttribute("aria-label", "Close settings"); x.addEventListener("click", function () { closeSheet(); root.focus({ preventScroll: true }); });
  head.appendChild(x); sh.appendChild(head);
  var tabs = el("div", "tabsrow"); tabs.setAttribute("role", "tablist");
  [["session", "Session"], ["model", "Assistant"], ["general", "General"], ["schedule", "Schedule"]].forEach(function (t) { var b = el("button", "", t[1]); b.type = "button"; b.setAttribute("role", "tab"); b.setAttribute("aria-selected", String(sheetTab === t[0])); b.addEventListener("click", function () { sheetTab = t[0]; clearArmed = false; buildSheet(); }); tabs.appendChild(b); });
  sh.appendChild(tabs);
  if (sheetTab !== "schedule") {
    var c = draft.cfg;
    if (sheetTab === "session") {
      var g1 = el("div", "grp");
      g1.appendChild(kv("Round length", "Whole minutes of work before a check-up, 1 to 120. Also asked at the intake.", txt(String(c.R / 60), "Round length in minutes", { type: "number", min: "1", max: "120", step: "1", inputmode: "numeric", style: "width: 5em" }, function (v) { var m = Math.round(+v); if (m >= 1 && m <= 120) c.R = m * 60; })));
      g1.appendChild(kv("Reminders per round", "Also the number of snoozes a round allows.", opts([[2, "2"], [3, "3"], [4, "4"]], c.r, "Reminders", function (v) { c.r = v; })));
      g1.appendChild(kv("Sitting limit", "Minutes seated before a movement break is due.", opts([[1800, "30"], [2700, "45"], [3600, "60"]], c.Ls, "Sitting limit in minutes", function (v) { c.Ls = v; })));
      g1.appendChild(kv("Movement break", "Minutes away from the desk.", opts([[120, "2"], [180, "3"], [300, "5"]], c.Lb, "Break in minutes", function (v) { c.Lb = v; })));
      sh.appendChild(g1);
      var q = c.R / Math.pow(2, c.r), rems = []; for (var k = c.r - 1; k >= 0; k--) rems.push(digits(q * Math.pow(2, k)));
      var g2 = el("div", "grp"); g2.appendChild(el("h5", "", "What follows"));
      g2.appendChild(kv("Snooze and plan length", "The base unit: the round split in half, " + c.r + " times.", el("span", "val", digits(q))));
      g2.appendChild(kv("Reminders at", "Time left when each one shows. The last covers the screen.", el("span", "val", rems.join(", "))));
      var tb = "<table aria-label=\"Check-up length by snoozes (rows) and steps cleared (columns)\"><caption>Check-up length, by snoozes taken (rows) and steps cleared (columns)</caption><tr><th>snoozes \\ cleared</th><th>0</th><th>1</th><th>2</th><th>3</th></tr>";
      for (var z = 0; z <= c.r; z++) { tb += "<tr><th>" + z + "</th>"; for (var xx = 0; xx <= 3; xx++) tb += "<td>" + fmt(q * Math.pow(2, z + 1) / (xx + 1)) + "</td>"; tb += "</tr>"; }
      var st = el("div", "stable"); st.innerHTML = tb + "</table>"; g2.appendChild(st);
      sh.appendChild(g2);
      sh.appendChild(el("p", "note", "There is no grace window: at time's up the clock holds until you press Go or Snooze. " + (S.state ? "Changes apply at the next session." : "Changes apply when the next session opens.")));
    } else if (sheetTab === "model") {
      sh.appendChild(radios("mdl", [["assistant", "Built-in assistant", "At each check-up it reads your plan: a note and a few suggestions for you at planning, and a short brief for A."], ["none", "None", "Rounds run exactly the same, with no notes or suggestions."]], draft.model, function (v) { draft.model = v; buildSheet(); }));
      sh.appendChild(el("p", "note", "The assistant takes one turn per round, during the check-up, and never decides a request or starts a clock. Steps you lock are never suggested."));
    } else {
      var gv = radios("voice", [["rich", "Rich", "A different sentence now and then, and often a second one on what the numbers mean for you right now. The request screen never varies."], ["varied", "Varied", "Same facts and numbers, a different sentence now and then; one sentence at a time."], ["fixed", "Fixed", "Always the same wording, word for word."]], draft.voice, function (v) { draft.voice = v; });
      gv.insertBefore(el("h5", "", "Announcements"), gv.firstChild);
      sh.appendChild(gv);
      var g4 = el("div", "grp"); g4.appendChild(el("h5", "", "Sound"));
      var lab = el("label", "ck"), cb = el("input"); cb.type = "checkbox"; cb.checked = !!draft.muted;
      cb.addEventListener("change", function () { draft.muted = cb.checked; });
      lab.appendChild(cb); var ls = el("span", "", "Mute sounds"); ls.appendChild(el("span", "c2", "Four short tones: round start, each reminder, time's up and the check-up.")); lab.appendChild(ls);
      var d4 = el("div", "kv"); d4.appendChild(lab); g4.appendChild(d4);
      sh.appendChild(g4);
      var gn = el("div", "grp"); gn.appendChild(el("h5", "", "Names"));
      gn.appendChild(kv("B", "The one working. The screens say this instead of B.", txt(draft.names.b, "B's name", { type: "text", maxlength: "30", placeholder: "B", style: "width: 11em" }, function (v) { draft.names.b = cleanName(v); })));
      gn.appendChild(kv("A", "The one answering. The screens say this instead of A.", txt(draft.names.a, "A's name", { type: "text", maxlength: "30", placeholder: "A", style: "width: 11em" }, function (v) { draft.names.a = cleanName(v); })));
      sh.appendChild(gn);
      var g5 = el("div", "grp"); g5.appendChild(el("h5", "", "Your plan"));
      var steps = Object.keys(S.nodes).filter(function (k) { return !S.nodes[k].root; }).length;
      var right = el("span", "clearrow");
      if (S.state) right.appendChild(el("span", "fine", "End the session first."));
      else if (!steps) right.appendChild(el("span", "fine", "Nothing to clear."));
      else if (!clearArmed) { var cl = el("button", "btn small", "Clear the plan…"); cl.type = "button"; cl.addEventListener("click", function () { clearArmed = true; buildSheet(); }); right.appendChild(cl); }
      else {
        var yes = el("button", "btn small danger", "Remove " + steps + (steps === 1 ? " step" : " steps")); yes.type = "button";
        yes.addEventListener("click", act(function () { clearPlan(); clearArmed = false; resetMap(); buildSheet(); }));
        var no = el("button", "btn small", "Keep"); no.type = "button"; no.addEventListener("click", function () { clearArmed = false; buildSheet(); });
        right.appendChild(yes); right.appendChild(no);
      }
      g5.appendChild(kv("Stored in this browser", steps ? steps + (steps === 1 ? " step. " : " steps. ") + "Clearing cannot be undone." : "Your steps are kept here between visits.", right));
      sh.appendChild(g5);
    }
    var foot = el("div", "foot");
    var rv = el("button", "btn small", "Revert"); rv.type = "button"; rv.addEventListener("click", function () { openSheet(sheetTab); });
    var sv = el("button", "btn small primary", "Save"); sv.type = "button";
    sv.addEventListener("click", act(function () {
      var changed = JSON.stringify(draft.cfg) !== JSON.stringify(CFG);
      if (changed) { if (S.state) nextCfg = draft.cfg; else { CFG = draft.cfg; nextCfg = null; } }
      else nextCfg = null;
      var c2 = draft.cfg;
      UI.model = draft.model; UI.voice = draft.voice; UI.muted = draft.muted;
      if (draft.names.b !== UI.names.b) setName("b", draft.names.b);
      if (draft.names.a !== UI.names.a) setName("a", draft.names.a);
      if (UI.intake.stage === "name" && UI.names.b) UI.intake.stage = "time";
      saveSettings();
      ev("man", "engine", "info", "settings saved", "R " + fmt(c2.R) + ", r " + c2.r + ", Ls " + fmt(c2.Ls) + ", Lb " + fmt(c2.Lb) + "\nassistant " + draft.model + ", voice " + draft.voice + (draft.muted ? ", muted" : "") + (changed && S.state ? "\napplies at the next session" : ""));
      closeSheet(); root.focus({ preventScroll: true });
    }));
    foot.appendChild(rv); foot.appendChild(sv); sh.appendChild(foot);
  } else {
    sh.appendChild(el("h5", "", "Look-ins"));
    sh.appendChild(el("p", "note", "At the time set, a note shows on screen and in the log while this page is open. Entries apply at once."));
    var g = el("div", "grp");
    if (!UI.schedule.length) g.appendChild(el("div", "kv", "Nothing scheduled."));
    UI.schedule.forEach(function (s, i) {
      var rm = el("button", "btn small", "Remove"); rm.type = "button"; rm.addEventListener("click", function () { UI.schedule.splice(i, 1); saveSettings(); ev("man", "scheduler", "info", "schedule entry removed", s.at + " " + s.why); buildSheet(); });
      g.appendChild(kv(s.why, s.at, rm));
    });
    sh.appendChild(g);
    var f = el("form", "kv addrow");
    var tm = el("input", "txt"); tm.type = "time"; tm.value = "09:00"; tm.required = true; tm.setAttribute("aria-label", "Time");
    var wy = el("input", "txt"); wy.placeholder = "What to look at"; wy.maxLength = 80; wy.setAttribute("aria-label", "What to look at");
    var ad = el("button", "btn small primary", "Add"); ad.type = "submit";
    f.appendChild(tm); f.appendChild(wy); f.appendChild(ad);
    f.addEventListener("submit", function (e) { e.preventDefault(); if (!wy.value.trim() || !tm.value) { (tm.value ? wy : tm).focus(); return; } UI.schedule.push({ at: tm.value, why: wy.value.trim() }); UI.schedule.sort(function (a, b) { return a.at < b.at ? -1 : a.at > b.at ? 1 : 0; }); saveSettings(); ev("man", "scheduler", "info", "schedule entry added", tm.value + " " + wy.value.trim()); buildSheet(); });
    sh.appendChild(f);
    var ft = el("div", "foot"); var dn = el("button", "btn small", "Done"); dn.type = "button"; dn.addEventListener("click", function () { closeSheet(); root.focus({ preventScroll: true }); }); ft.appendChild(dn); sh.appendChild(ft);
  }
  w.appendChild(sh);
  w.scrollTop = top;
  w.onclick = function () { closeSheet(); };
  // A rebuild must not drop the keyboard: focus returns to the selected tab, so Escape still closes.
  if (hadFocus) { var cur = sh.querySelector('.tabsrow button[aria-selected="true"]'); if (cur) cur.focus({ preventScroll: true }); }
}
// Escape closes the sheet wherever the focus went.
document.addEventListener("keydown", function (e) { if (e.key === "Escape" && UI.sheet && !root.contains(e.target)) { closeSheet(); root.focus({ preventScroll: true }); render(true); } });
