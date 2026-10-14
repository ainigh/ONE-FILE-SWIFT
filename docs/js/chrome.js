/* chrome.js: the frame around the screens: the role tabs, B's foot, and who answers for A. */
"use strict";
// ----- roles: one screen, three roles, switched from the tabs in the header -----
var TITLES = { a: "A · Requests", b: "B · Work", admin: "Admin · Monitor" };
function placePanels() {
  if (UI.role === "a") { $("ap-grid").appendChild($("gridpanel")); $("ap-log").appendChild($("p-logs")); }
  else { $("bp-table").appendChild($("gridpanel")); $("adp-log").appendChild($("p-logs")); }
  lastGrid = lastLogs = "";
}
function setRole(r) {
  UI.role = r; closePop(); UI.depFor = null; UI.renaming = null;
  $("bscreen").hidden = r !== "b"; $("ascreen").hidden = r !== "a"; $("adscreen").hidden = r !== "admin";
  if (r !== "b") $("board").hidden = true;
  var wb = $("wbody"); wb.classList.toggle("role-a", r === "a"); wb.classList.toggle("role-admin", r === "admin");
  if (r !== "b") { wb.classList.remove("plan", "split"); wb.classList.add("solo"); }
  document.title = "Machine Prompts Man · " + TITLES[r];
  Array.prototype.forEach.call($("roletabs").querySelectorAll("button"), function (b) { b.setAttribute("aria-selected", String(b.getAttribute("data-role") === r)); });
  placePanels();
  lastQ = lastRQ = lastGraph = lastTop = lastIntake = lastReady = lastStrip = lastCover = "";
}
function setAuto(v) {
  UI.auto = v;
  ev("man", v ? "policy" : "a", "info", v ? "A: policy (autopilot)" : "A: a person", v ? "policy answers every request at once" : "requests wait for A; the policy's default is shown beside each");
  var r = openReq();
  if (v && r && !r.verdict) decide(r, r.policy[0], r.policy[1], "policy");
}
function canEnd() { return !!S.state && !S.frozen && !openReq(); }
function renderChrome() {
  $("abadge").hidden = !(openReq() && !S.req.verdict);
  $("opensettings").setAttribute("aria-expanded", String(UI.sheet === "settings"));
  $("bfoot").hidden = UI.role !== "b";
  $("bend").disabled = !canEnd();
  $("seatmin").disabled = !!S.state;
  $("seatnote").textContent = S.state ? "Set before a session opens." : "Counts toward the sitting limit when the session opens.";
  if (document.activeElement !== $("seatmin")) $("seatmin").value = String(seatStart / 60);
  Array.prototype.forEach.call($("bvoice").querySelectorAll("button"), function (b) { b.setAttribute("aria-selected", String(b.getAttribute("data-v") === UI.voice)); });
}
