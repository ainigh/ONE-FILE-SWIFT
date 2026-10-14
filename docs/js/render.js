/* render.js: render, and the clock loop that drives it. */
"use strict";
// ----- render -----
var lastAnnounce = null;
function render(force) {
  var now = performance.now(), st = S.state;
  if (force) lastGraph = "";
  if (UI.role === "b") renderB(now);
  else if (UI.role === "a") renderA();
  else renderAdmin();
  var t = $("toast");
  if (now < S.toastUntil) { t.hidden = false; t.textContent = toastText; t.classList.toggle("info", !toastErr); } else t.hidden = true;
  renderChrome();
  renderCover();
  $("band").hidden = !(UI.role === "b" && st === "break" && running());
  if (!$("band").hidden) { $("banddigits").textContent = digits(left()); $("bandask").disabled = !!openReq(); }
  if (S.announce !== lastAnnounce) { lastAnnounce = S.announce; $("s-announce").textContent = S.announce; }
}

// ----- the clock -----
// Session time follows the wall clock. When the tab is hidden, frames stop; on return the whole
// gap is applied at once, so a round that ended while the tab was away shows "Time's up" at once.
var last = 0, visible = true;
function rate() { return S.state === "strategy" && !S.frozen ? Math.min(4, speed) : speed; }
function loop(now) {
  if (!visible) { last = 0; return; }
  var real = last ? Math.max(0, (now - last) / 1000) : 0;
  if (real) {
    if (S.state) {
      var dt = real * rate();
      // Step through long gaps in chunks so every reminder and phase end fires in order.
      while (dt > 0) {
        var step = Math.min(dt, 0.5); dt -= step;
        S.T += step; S.W += step * 1000;
        // The sitting clock is not a phase clock: it runs in every state but idle and the break, freezes included.
        if (S.frozen || (S.state !== "idle" && S.state !== "break")) S.seated += step;
        tick();
        if (!S.state) { S.W += dt * 1000; break; }
      }
    } else S.W += real * 1000;
  }
  last = now;
  checkSchedule();
  render(false);
  if (UI.role === "admin" && UI.adTab === "monitor") mon.draw(now);
  requestAnimationFrame(loop);
}
document.addEventListener("visibilitychange", function () {
  if (document.hidden) { visible = false; last = 0; }
  else if (!visible) { visible = true; last = 0; requestAnimationFrame(loop); }
});
// Scheduled look-ins (Settings › Schedule): at the time set, a note on screen and in the log.
var scheduleFired = {};
function checkSchedule() {
  if (!UI.schedule.length) return;
  var d = new Date(), hm = pad2(d.getHours()) + ":" + pad2(d.getMinutes()), day = d.toDateString();
  UI.schedule.forEach(function (s) {
    var k = day + " " + s.at + " " + s.why;
    if (s.at === hm && !scheduleFired[k]) {
      scheduleFired[k] = true;
      ev("scheduler", "output", "info", "scheduled: " + s.why, "set for " + s.at);
      toast(s.at + " · " + s.why, true);
    }
  });
}
