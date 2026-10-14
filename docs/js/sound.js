/* sound.js: four short synthesized tones. */
"use strict";
// ----- sound (DESIGN §10): four short synthesized tones -----
var actx = null;
function sound(kind) {
  if (UI.muted) return;
  try { actx = actx || new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { return; }
  if (actx.state === "suspended") actx.resume();
  var seq = { tick: [[1320, 0, 0.06]], start: [[523, 0, 0.14], [784, 0.11, 0.18]], timeup: [[880, 0, 0.16], [659, 0.17, 0.22]], stop: [[196, 0, 0.34]] }[kind];
  seq.forEach(function (n) {
    var o = actx.createOscillator(), g = actx.createGain(), t0 = actx.currentTime + n[1];
    o.type = "sine"; o.frequency.value = n[0];
    g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(0.07, t0 + 0.012); g.gain.exponentialRampToValueAtTime(0.0001, t0 + n[2]);
    o.connect(g); g.connect(actx.destination); o.start(t0); o.stop(t0 + n[2] + 0.03);
  });
}
