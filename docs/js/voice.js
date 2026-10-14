/* voice.js: what the engine says, through announce.js. */
"use strict";
// ----- the engine's voice (announce.js; variant 0 is the spec's wording) -----
function say(t, detail) { S.announce = t; ev("engine", "output", "ok", t, detail || ""); }
function ctxBase() {
  return { sessionId: S.sessionId, round: S.round, R: CFG.R, q: qU(), Lb: CFG.Lb, Ls: CFG.Ls, Zmax: zMax(), z: S.z, x: S.x,
    aName: aName(), bName: bName(), seated: S.seated, doing: title(slot("doing")), next: title(slot("next")), prevDoing: S.prevPair.d, prevNext: S.prevPair.n };
}
// voice: one of VOICES; rich is varied with a tail. The request screen's lines always pass "fixed".
function phrase(trigger, ctx, fallback, voice) {
  var A = window.Announce;
  if (!A) return { text: fallback, detail: "" };
  try {
    var c = ctxBase(); for (var k in ctx) c[k] = ctx[k];
    var v = voice || UI.voice, r = A.announce(trigger, c, { voice: v === "fixed" ? "fixed" : "varied", tail: v === "rich" });
    return { text: r.text, detail: "trigger " + trigger + ", variant " + r.variant + (r.variant === 0 ? " (the spec's wording)" : "") + (r.tail >= 0 ? "\ntail " + r.tail : "") + "\nvoice " + v };
  } catch (e) { return { text: fallback, detail: "" }; }
}
function speak(trigger, ctx, fallback, prefix) {
  var r = phrase(trigger, ctx || {}, fallback);
  say((prefix ? prefix + " " : "") + r.text, r.detail);
  return S.announce;
}
// The request screen's lines are fixed by the guide: always variant 0.
function line(trigger, ctx, fallback) { return phrase(trigger, ctx, fallback, "fixed").text; }
function setVoice(v) {
  if (VOICES.indexOf(v) < 0 || v === UI.voice) return;
  UI.voice = v; saveSettings();
  ev("man", "output", "info", "voice: " + VOICE_WORD[v].toLowerCase(), v === "fixed" ? "the spec's wording only" : v === "varied" ? "another sentence with the same facts" : "varied, with a tail on what the numbers mean");
}
