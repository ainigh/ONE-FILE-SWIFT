/* state.js: the settings, the view state (UI) and the session state (S) everything reads. */
"use strict";
/* ================= The app =================
   Spec 2.1, the handshake model. One state object S drives everything: the session engine, the
   store and its patch log, the assistant's turn, the request log, and the host events the
   Monitor and the Log show. Every phase change is a Request: B asks (or the System raises one when
   a clock runs out), policy or a person in the A role decides, and B presses Go. Only two things
   change a clock: the System reaching the end of a phase, and B's Go on an approved request.
   B's screen follows the screen guide: intake, Ready?, the round, the plan, and one request
   component shown as a strip (B keeps working) or a cover (nothing underneath is reachable). */

var root = $("sim");
var DEFAULT_CFG = { R: 600, r: 3, Ls: 2700, Lb: 180 };
var CFG = { R: 600, r: 3, Ls: 2700, Lb: 180 }, nextCfg = null;
function qU() { return CFG.R / Math.pow(2, CFG.r); }
function zMax() { return CFG.r; }
function remTimes() { var a = []; for (var k = CFG.r - 1; k >= 0; k--) a.push(qU() * Math.pow(2, k)); return a; }
function awayFor(z, x) { return qU() * Math.pow(2, z + 1) / (x + 1); }

// The voice: fixed (the spec's wording only), varied (another sentence with the same facts), or rich
// (varied, plus a tail that says what the numbers mean for B right now). Rich is the default.
var VOICES = ["fixed", "varied", "rich"], VOICE_WORD = { fixed: "Fixed", varied: "Varied", rich: "Rich" };
var UI = { role: "b", voice: "rich", auto: true, board: false, boardView: "map",
  aTab: "", adTab: "monitor", gridRound: 0, intake: { stage: "name", ids: [] }, names: { b: "", a: "" },
  muted: false, model: "assistant",
  sheet: null, pop: null, depFor: null, renaming: null, renameVal: null, folded: {},
  logPart: "", logProblems: false, logSel: null, schedule: [], reason: "", reasonFor: null };
// Clocks run in real time. A developer can open app.html?speed=60 to run them faster while testing.
var speed = 1, seatStart = 0, sessionSeq = 0;
try { var sp = +(new URLSearchParams(location.search).get("speed") || 1); if (sp >= 1 && sp <= 120) speed = sp; } catch (e) {}

// ----- what the browser keeps between visits: the plan, the settings, seated time, the board -----
function readStore(key) { try { return JSON.parse(localStorage.getItem(key) || "null"); } catch (e) { return null; } }
function writeStore(key, value) { try { localStorage.setItem(key, JSON.stringify(value)); return true; } catch (e) { return false; } }

// How long B has already been sitting when a session opens: set at the foot of B's screen, kept.
var SEAT_KEY = "mpm.seated";
var seatSaved = readStore(SEAT_KEY);
if (typeof seatSaved === "number" && !isNaN(seatSaved)) seatStart = Math.max(0, Math.min(240, seatSaved)) * 60;
function setSeatStart(min) {
  seatStart = Math.max(0, Math.min(240, Math.round(min) || 0)) * 60;
  writeStore(SEAT_KEY, seatStart / 60);
}
// B's board (the mind map) stays as B left it: open or closed, Map or Table, across rounds and
// visits. Only B's own choice moves it; planning shows the board whatever the choice.
var BOARD_KEY = "mpm.board";
var boardSaved = readStore(BOARD_KEY);
if (boardSaved) { UI.board = !!boardSaved.open; if (boardSaved.view === "table") UI.boardView = "table"; }
function setBoard(open, view) {
  UI.board = open; if (view) UI.boardView = view;
  writeStore(BOARD_KEY, { open: UI.board, view: UI.boardView });
}
// Names are optional: B's and A's, used wherever the screens speak of them. Kept in this browser.
var NAMES_KEY = "mpm.names";
var namesSaved = readStore(NAMES_KEY);
if (namesSaved && typeof namesSaved === "object") { UI.names.b = cleanName(namesSaved.b); UI.names.a = cleanName(namesSaved.a); }
function cleanName(v) { return typeof v === "string" ? v.replace(/\s+/g, " ").trim().slice(0, 30) : ""; }
function setName(role, v) { UI.names[role] = cleanName(v); writeStore(NAMES_KEY, UI.names); }
function bName() { return UI.names.b || "B"; }
function aName() { return UI.names.a || "A"; }
// The intake asks for a name only until one is given; the round length, every time.
function firstStage() { return UI.names.b ? "time" : "name"; }
UI.intake.stage = firstStage();
// Settings: the session's numbers, the assistant, the voice, sound.
var SETTINGS_KEY = "mpm.settings";
var settingsSaved = readStore(SETTINGS_KEY);
if (settingsSaved) {
  var sc = settingsSaved.cfg;
  if (sc && validR(sc.R) && [2, 3, 4].indexOf(sc.r) >= 0 && [1800, 2700, 3600].indexOf(sc.Ls) >= 0 && [120, 180, 300].indexOf(sc.Lb) >= 0) CFG = { R: sc.R, r: sc.r, Ls: sc.Ls, Lb: sc.Lb };
  if (settingsSaved.model === "none" || settingsSaved.model === "assistant") UI.model = settingsSaved.model;
  if (VOICES.indexOf(settingsSaved.voice) >= 0) UI.voice = settingsSaved.voice;
  UI.muted = !!settingsSaved.muted;
  if (Array.isArray(settingsSaved.schedule)) UI.schedule = settingsSaved.schedule.filter(function (s) { return s && typeof s.at === "string" && typeof s.why === "string"; }).map(function (s) { return { at: s.at, why: s.why }; });
}
// The round length is any whole number of minutes from 1 to 120: B names it at the intake.
function validR(R) { return typeof R === "number" && R >= 60 && R <= 7200 && R % 60 === 0; }
function saveSettings() { writeStore(SETTINGS_KEY, { cfg: nextCfg || CFG, model: UI.model, voice: UI.voice, muted: UI.muted, schedule: UI.schedule }); }
var S;

function mk(title, parent, created) {
  return { title: title, parent: parent, status: "open", deps: [], created: created, root: !parent, locked: false, updated: Date.now() };
}
// A session starts from no plan at all: the first lines B types become the plan.
function fresh() {
  return {
    T: 0, W: Date.now(), state: null, frozen: false, reading: 0, round: 0, roundStart: 0, roundRun: 0,
    phaseStart: 0, phaseEnd: 0, z: 0, x: null, statusLen: 0, seated: 0, remFired: 0, lastRem: null, halfFired: false,
    picks: { d: null, n: null }, selected: null, diff: [], held: null, turn: null, announce: "",
    nodes: {},
    seq: 0, doneAt: {}, pn: 0, undo: [], redo: [], events: [], evId: 0, unseen: {}, turnSeq: 0, propSeq: 0, nudged: false,
    sessionId: "", prevPair: { d: null, n: null }, planChosen: false,
    req: null, sys: null, requests: [], reqSeq: 0, rounds: {},
    strip: null, toastUntil: 0, notes: []
  };
}
// The plan outlives the page: every patch writes it, and the next visit opens on it.
var PLAN_KEY = "mpm.plan";
function savePlan() { return writeStore(PLAN_KEY, { v: 1, nodes: S.nodes, seq: S.seq, pn: S.pn }); }
function loadPlan() {
  var p = readStore(PLAN_KEY);
  if (!p || p.v !== 1 || !p.nodes || typeof p.nodes !== "object") return false;
  var nodes = {};
  Object.keys(p.nodes).forEach(function (k) {
    var n = p.nodes[k];
    if (!n || typeof n.title !== "string") return;
    nodes[k] = { title: n.title, parent: n.parent || null, status: ["open", "doing", "next", "done", "crossed"].indexOf(n.status) >= 0 ? n.status : "open",
      deps: Array.isArray(n.deps) ? n.deps.slice() : [], created: +n.created || 0, root: !n.parent, locked: !!n.locked, updated: +n.updated || Date.now() };
  });
  Object.keys(nodes).forEach(function (k) { var n = nodes[k]; if (n.parent && !nodes[n.parent]) { n.parent = null; n.root = true; } n.deps = n.deps.filter(function (d) { return !!nodes[d]; }); });
  S.nodes = nodes; S.seq = Math.max(0, +p.seq || 0); S.pn = Math.max(0, +p.pn || 0);
  return true;
}
