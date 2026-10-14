/* input.js: buttons, forms, the keyboard and the hash. */
"use strict";
// ----- inputs -----
$("in-form").addEventListener("submit", function (e) {
  e.preventDefault();
  var inp = $("in-text"), v = inp.value.trim(), st = UI.intake.stage;
  if (st === "name") {   // optional: Return on an empty field skips it
    if (v) { setName("b", v); ev("man", "engine", "info", "B's name: " + UI.names.b, "used wherever the screens speak of B"); }
    UI.intake.stage = "time"; render(true); return;
  }
  if (st === "time") {   // whole minutes per round, 1 to 120; empty keeps the number shown
    var mins = v === "" ? CFG.R / 60 : Math.round(+v);
    if (!(mins >= 1 && mins <= 120)) { toast("Whole minutes, 1 to 120."); inp.focus(); return; }
    if (mins * 60 !== CFG.R) { CFG = { R: mins * 60, r: CFG.r, Ls: CFG.Ls, Lb: CFG.Lb }; nextCfg = null; saveSettings(); ev("man", "engine", "info", "round length: " + fmt(CFG.R), "set at the intake; reminders at " + remTimes().map(digits).join(", ") + " left"); }
    UI.intake.stage = "ask"; render(true); return;
  }
  if (!v) return;   // empty input does nothing, no error
  var id = addChild(goal(), v);
  if (!id) return;
  inp.value = "";
  var ids = UI.intake.ids; ids.push(id);
  if (ids.length === 1) S.picks.d = id;
  else if (ids.length === 2) S.picks.n = id;
  if (ids.length >= 2) UI.intake.stage = "ready";
  ev("man", "engine", "info", "intake line " + ids.length + ": " + v, ids.length === 1 ? "will be Doing" : ids.length === 2 ? "will be Next" : "an open step");
  render(true);
  if (UI.intake.stage === "ready") setTimeout(function () { $("rd-ok").focus({ preventScroll: true }); }, 0);
});
$("in-text").addEventListener("keydown", function (e) { e.stopPropagation(); });
$("in-skip").addEventListener("click", act(function () { UI.intake.stage = "time"; setTimeout(function () { $("in-text").focus({ preventScroll: true }); }, 0); }));
$("in-cont").addEventListener("click", act(function () {
  var p = autoPair(); S.picks = { d: p.d, n: p.n };
  UI.intake.stage = "ready"; setBoard(true, "map");
  ev("man", "engine", "info", "continue where you left off", "pair preselected: " + (title(p.d) || "nothing") + ", " + (title(p.n) || "nothing"));
}));
$("rd-ok").addEventListener("click", act(okReady));
$("rd-more").addEventListener("click", act(function () {
  if (UI.intake.ids.length < 2) UI.intake.ids = [commitPair().d, commitPair().n].filter(Boolean);
  UI.intake.stage = "ask"; setTimeout(function () { $("in-text").focus({ preventScroll: true }); }, 0);
}));
$("r-phase").addEventListener("click", act(nextPhase));
$("r-board").addEventListener("click", act(function () { setBoard(!UI.board); }));
$("pl-start").addEventListener("click", act(function () { raise("work"); }));
$("bclose").addEventListener("click", act(function () { setBoard(false); closePop(); }));
Array.prototype.forEach.call($("bseg").querySelectorAll("button"), function (b) { b.addEventListener("click", act(function () { setBoard(UI.board, b.getAttribute("data-v")); closePop(); })); });
$("cv-ask").addEventListener("click", act(function () { raise("strategy"); }));
$("bandask").addEventListener("click", act(function () { raise("work"); }));
Array.prototype.forEach.call($("aseg").querySelectorAll("button"), function (b) { b.addEventListener("click", act(function () { var t = b.getAttribute("data-t"); UI.aTab = UI.aTab === t ? "" : t; placePanels(); })); });
$("adclose").addEventListener("click", act(function () { UI.aTab = ""; }));
Array.prototype.forEach.call($("adseg").querySelectorAll("button"), function (b) { b.addEventListener("click", act(function () { UI.adTab = b.getAttribute("data-t"); placePanels(); })); });
Array.prototype.forEach.call($("roletabs").querySelectorAll("button"), function (b) { b.addEventListener("click", act(function () { setRole(b.getAttribute("data-role")); })); });
$("opensettings").addEventListener("click", act(function () { openSheet(); }));
$("bend").addEventListener("click", act(function () { if (canEnd()) raise("end"); }));
Array.prototype.forEach.call($("bvoice").querySelectorAll("button"), function (b) { b.addEventListener("click", act(function () { setVoice(b.getAttribute("data-v")); })); });
$("seatmin").addEventListener("change", function () { setSeatStart(+this.value); this.value = String(seatStart / 60); });
$("seatmin").addEventListener("keydown", function (e) { e.stopPropagation(); });
$("aname").addEventListener("change", act(function () { setName("a", $("aname").value); $("aname").value = UI.names.a; ev("man", "a", "info", UI.names.a ? "A's name: " + UI.names.a : "A's name cleared", "used wherever the screens speak of A"); }));
$("aname").addEventListener("keydown", function (e) { e.stopPropagation(); if (e.key === "Enter") $("aname").blur(); });
Array.prototype.forEach.call($("aswho").querySelectorAll("button"), function (b) { b.addEventListener("click", act(function () { var v = b.getAttribute("data-auto") === "1"; if (v !== UI.auto) setAuto(v); })); });
// Space: the one thing the screen asks for. Nothing on check-up or in a break.
function primary() {
  if (UI.role !== "b") return;
  if (curCover) { var b = curCover.btns.filter(function (x) { return x[2]; })[0]; if (b) b[2](); return; }
  if (curStrip && curStrip.btns.length) { curStrip.btns[0][2](); return; }
  var v = bView();
  if (v === "intake") { $("in-text").focus({ preventScroll: true }); return; }
  if (v === "ready") { okReady(); return; }
  if (v === "round") { nextPhase(); return; }
  if (v === "plan" && S.state === "strategy") raise("work");
}
root.addEventListener("keydown", function (e) {
  var tg = e.target, typing = tg.tagName === "INPUT" || tg.tagName === "SELECT" || tg.tagName === "TEXTAREA";
  if (typing) return;
  var mod = e.metaKey || e.ctrlKey, k = e.key, sel = S.selected && S.nodes[S.selected] ? S.selected : null;
  var onBoard = UI.role === "b" && !$("board").hidden && !editBlock() && !curCover;
  var onMap = UI.role === "b" && !$("board").hidden && UI.boardView === "map" && !curCover;
  if (tg.tagName === "BUTTON" && (k === " " || k === "Enter")) return;
  if (mod && (k === "z" || k === "Z") && onBoard) { e.preventDefault(); if (e.shiftKey) redo(); else undo(); render(true); return; }
  if (mod || e.altKey) return;
  if (k === " ") { e.preventDefault(); primary(); render(true); }
  else if (k === "Escape") {
    if (UI.depFor) UI.depFor = null;
    else if (UI.pop) { closePop(); S.selected = null; }
    else if (UI.sheet) closeSheet();
    else if (UI.role === "a" && UI.aTab) UI.aTab = "";
    else if (S.selected) S.selected = null;
    render(true);
  }
  else if (k === ",") { e.preventDefault(); openSheet(); render(true); }
  else if ((k === "f" || k === "F") && onMap) bmap.fit(true);
  else if ((k === "f" || k === "F") && UI.role === "admin" && UI.adTab === "monitor") mon.fit();
  else if ((k === "n" || k === "N") && onMap && !sel) centreNow();
  else if (!onBoard) return;
  else if ((k === "d" || k === "D") && sel && canPick()) { pick("d", sel); render(true); }
  else if ((k === "n" || k === "N") && sel && canPick()) { pick("n", sel); render(true); }
  else if (k === "a" || k === "A") { var nk = addChild(sel || goal()); if (nk) { S.selected = nk; UI.renaming = nk; UI.boardView = "map"; } render(true); }
  else if (k === "Enter" && sel) { e.preventDefault(); UI.renaming = sel; UI.boardView = "map"; render(true); }
  else if ((k === "Backspace" || k === "Delete") && sel) { e.preventDefault(); crossOut(sel); render(true); }
});
// A hash opens a screen: #b, #board, #a (or #requests), #admin (or #monitor). The site's links use it.
function openFromHash() {
  var t = (location.hash || "").slice(1);
  if (!t) return;
  if (t === "admin" || t === "monitor") { setRole("admin"); UI.adTab = "monitor"; }
  else if (t === "a" || t === "requests") { setRole("a"); UI.aTab = ""; }
  else if (t === "b" || t === "board") { setRole("b"); if (t === "board") setBoard(true); }
  else return;
  placePanels(); render(true);
}
window.addEventListener("hashchange", openFromHash);
// Leaving the page mid-session: the clocks cannot follow, so the browser asks first.
window.addEventListener("beforeunload", function (e) { if (S.state) { e.preventDefault(); e.returnValue = ""; } });
