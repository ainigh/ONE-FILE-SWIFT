/* grid.js: the read-only grid, round by round. */
"use strict";
// The grid (addendum §7): read-only for everyone, written by the System from the store, with a
// round picker built from the snapshots the System keeps at each round's Go and end.
var lastGrid = "";
function updatedWord(ms) { var d = Math.floor((S.W - ms) / 86400000); return d <= 0 ? "today" : d === 1 ? "yesterday" : d + " days ago"; }
var SCOL = { doing: "--doing", next: "--next", blocked: "--blocked", done: "--done", open: "--ink2", crossed: "--ink2", "new": "--ink3" };
function renderGrid() {
  var rounds = Object.keys(S.rounds).map(Number).sort(function (a, b) { return a - b; });
  if (UI.gridRound && !S.rounds[UI.gridRound]) UI.gridRound = 0;
  var key = JSON.stringify(S.nodes) + "|" + JSON.stringify(S.rounds) + "|" + UI.gridRound + "|" + S.round + "|" + S.selected + "|" + UI.role;
  if (key === lastGrid) return;
  lastGrid = key;
  var pk = $("gridpick"); pk.textContent = "";
  pk.appendChild(el("span", "", "Round"));
  var seg = el("div", "seg2"); seg.setAttribute("role", "tablist"); seg.setAttribute("aria-label", "Round");
  rounds.concat([0]).forEach(function (k) {
    var b = el("button", "", k ? String(k) : "Now"); b.type = "button"; b.setAttribute("role", "tab"); b.setAttribute("aria-selected", String(UI.gridRound === k));
    b.addEventListener("click", act(function () { UI.gridRound = k; }));
    seg.appendChild(b);
  });
  pk.appendChild(seg);
  var k = UI.gridRound, info = k ? S.rounds[k] : null, live = !k || !info.end;
  var base = k ? info.start : (S.round && S.rounds[S.round] ? S.rounds[S.round].start : null);
  pk.appendChild(el("span", "fine", (k ? "Round " + k + (info.end ? ", as it ended" : ", in progress") : S.round ? "Now; changes since round " + S.round + " started" : "Now") + ". Read only: the System writes it from the plan."));
  var body = $("gridbody"); body.textContent = "";
  treeOrder().forEach(function (x) {
    var id = x[0], depth = x[1], n = S.nodes[id];
    var stt = live ? displayStatus(id) : info.end[id];
    if (!stt) return;
    var was = base ? (base[id] || "new") : stt;
    var tr = el("tr"); if (S.selected === id) tr.className = "sel"; if (stt === "crossed") tr.classList.add("crossed");
    tr.addEventListener("click", function () { if (S.selected !== id) { S.selected = id; render(true); } });
    var td = el("td", "ro t", n.title); td.style.paddingLeft = (10 + depth * 18) + "px"; if (n.root) td.style.fontWeight = "500"; if (stt === "crossed") td.style.textDecoration = "line-through";
    tr.appendChild(td);
    td = el("td", "ro", WORD[stt]); td.style.color = css(SCOL[stt]); td.style.fontSize = "0.78rem"; tr.appendChild(td);
    var chg = el("td", "chg", was !== stt ? WORD[was] + " → " + WORD[stt] : "");
    if (was !== stt) tr.classList.add("changed");
    tr.appendChild(chg);
    var waits = n.deps.filter(function (d) { return S.nodes[d]; }).map(function (d) { return title(d) + (finished(d) ? " ✓" : ""); });
    td = el("td", "ro", waits.length ? waits.join(", ") : "—"); td.style.color = css(waits.length ? "--ink2" : "--ink3"); tr.appendChild(td);
    td = el("td", "ro", updatedWord(n.updated)); td.style.color = css("--ink2"); tr.appendChild(td);
    body.appendChild(tr);
  });
}
