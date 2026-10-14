(function () {
  "use strict";
  var C = 2 * Math.PI * 104;
  var q = 75;                      // base unit at default settings: 10 min ÷ 2^3
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  function $(id) { return document.getElementById(id); }
  function css(name) { return "var(" + name + ")"; }
  // Clock digits (6:12) and spoken lengths (10 min, 1:15, 45 s) come from announce.js, so every
  // screen writes numbers the way the engine says them.
  var digits = Announce.digits;
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }

  /* ================= Arithmetic ================= */
  (function () {
    var z = 0, x = 1, maxAway = q * 16;
    function why(z, x, s) {
      var a = ["No snoozes", "One snooze", "Two snoozes", "Three snoozes"][z];
      var b = ["nothing finished", "one step finished", "two steps finished", "three steps finished"][x];
      var lead = a + " and " + b + ". ";
      if (s >= 180) return lead + "Long enough to count as moving: your seated time resets.";
      if (s <= 40) return lead + "You are back almost at once.";
      return lead + "Enough to stand, stretch and look out of a window.";
    }
    function calc() {
      var s = q * Math.pow(2, z + 1) / (x + 1);
      $("away").textContent = digits(s);
      $("awaybar").style.width = (100 * s / maxAway).toFixed(1) + "%";
      $("why").textContent = why(z, x, s);
      for (var i = 0; i < 4; i++) {
        $("z" + i).setAttribute("aria-pressed", String(i === z));
        $("x" + i).setAttribute("aria-pressed", String(i === x));
      }
    }
    [0, 1, 2, 3].forEach(function (n) {
      $("z" + n).addEventListener("click", function () { z = n; calc(); });
      $("x" + n).addEventListener("click", function () { x = n; calc(); });
    });
    calc();
  })();


  /* ================= Hero: a round that runs itself ================= */
  (function () {
    var D = "Fix the login bug", N = "Write onboarding copy", N2 = "Record the demo";
    var beats = [
      { k: ["work"], state: "Work", tone: "--doing", len: 600, play: 10, counts: "left in the round", seated: 26,
        doing: D, next: N, say: function (r) { return "Round " + r + ". " + D + " doing, " + N + " next. 10 min, starting now."; },
        ticks: [[300, "5 min left."], [150, "2:30 left."], [75, "1:15 left. Get ready to stop."]] },
      { k: ["timeup"], state: "Time's up", tone: "--stop", len: 600, frozen: true, play: 2.4, counts: "stopped: waiting for Go", seated: 36, doing: D, next: N, say: "Time's up. Move on to check-up? Go, or snooze." },
      { k: ["timeup", "work"], state: "Snooze", tone: "--doing", len: q, play: 2.6, counts: "more", seated: 36, doing: D, next: N, say: "Snooze 1 of 3. 1:15." },
      { k: ["away"], state: "Check-up", tone: "--ink2", len: q * 4 / 2, play: 3.4, counts: "step away", seated: 37, doing: N, next: "—",
        say: "Round over at 11:15. Check-up, 2:30. " + D + " doing → done." },
      { k: ["plan", "commit"], state: "Plan", tone: "--next", len: q, play: 3.4, counts: "to plan", seated: 40, doing: N, next: N2, say: function (r) { return "Plan round " + (r + 1) + ", 1:15. Ready when you are: Go."; } },
      { k: ["move"], state: "Break", tone: "--rest", len: 180, play: 3.4, counts: "break", seated: 41, doing: N, next: N2,
        say: "Seated 41 min. Movement break, 3 min." }
    ];
    var phases = Array.prototype.slice.call(document.querySelectorAll("#cycle .phase"));
    var idx = 0, round = 3, start = 0, paused = false, pausedAt = 0, lastSay = $("an").textContent, lastTick = -1, visible = true;
    function sayText(b) { return typeof b.say === "function" ? b.say(round) : b.say; }
    function show(b, remaining) {
      $("st").textContent = b.state;
      $("st").style.color = css(b.tone);
      $("meta").textContent = "Round " + round + " · Seated " + b.seated + " min";
      $("arc").style.stroke = css(b.tone);
      $("arc").setAttribute("stroke-dashoffset", (b.frozen ? C : C * (1 - remaining / b.len)).toFixed(2));
      $("dg").textContent = digits(b.frozen ? b.len : remaining);
      $("ct").textContent = b.counts;
      $("sd").textContent = b.doing;
      $("sn").textContent = b.next;
      phases.forEach(function (p) { p.classList.toggle("on", b.k.indexOf(p.getAttribute("data-k")) >= 0); });
    }
    function say(t) {
      if (t === lastSay) return;
      lastSay = t;
      var an = $("an");
      an.style.opacity = "0";
      setTimeout(function () { an.textContent = t; an.style.opacity = "1"; }, reduce ? 0 : 120);
    }
    function frame(now) {
      if (paused || !visible) return;
      var b = beats[idx], t = (now - start) / 1000;
      if (t >= b.play) {
        idx = (idx + 1) % beats.length; start = now; lastTick = -1;
        if (idx === 0) round += 1;
        b = beats[idx]; t = 0;
        say(sayText(b));
      }
      var remaining = b.len * (1 - t / b.play);
      show(b, remaining);
      if (b.ticks) for (var i = 0; i < b.ticks.length; i++) {
        if (remaining <= b.ticks[i][0] && lastTick < i) { lastTick = i; say(b.ticks[i][1]); }
      }
      requestAnimationFrame(frame);
    }
    phases.forEach(function (p) { p.classList.toggle("on", p.getAttribute("data-k") === "work"); });
    if (reduce) { $("pp").hidden = true; return; }
    setTimeout(function () {
      start = performance.now() - (1 - 372 / 600) * beats[0].play * 1000;
      requestAnimationFrame(frame);
    }, 1200);
    // Stop drawing while the hero is off screen; resume where it was.
    if ("IntersectionObserver" in window) {
      var hiddenAt = 0;
      new IntersectionObserver(function (es) {
        var v = es[0].isIntersecting;
        if (v === visible) return;
        visible = v;
        if (!v) hiddenAt = performance.now();
        else if (!paused) { start += performance.now() - hiddenAt; requestAnimationFrame(frame); }
      }).observe(document.querySelector(".instrument"));
    }
    $("pp").addEventListener("click", function () {
      paused = !paused;
      $("pp").textContent = paused ? "Play" : "Pause";
      $("pp").setAttribute("aria-pressed", String(paused));
      if (paused) pausedAt = performance.now();
      else { start += performance.now() - pausedAt; requestAnimationFrame(frame); }
    });
  })();

  /* ================= Try a round: app.html, embedded =================
     The app lives in app.html; this page shows it in a frame. Links here open a screen in it by hash. */
  Array.prototype.forEach.call(document.querySelectorAll("[data-open-tab]"), function (b) {
    b.addEventListener("click", function () {
      var f = $("appframe");
      f.src = "app.html#" + b.getAttribute("data-open-tab");
      $("try").scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "start" });
      setTimeout(function () { try { f.contentWindow.focus(); } catch (e) {} }, reduce ? 0 : 500);
    });
  });

  /* ================= The tour ================= */
  (function () {
    var tabs = ["graph", "grid", "menubar", "settings"];
    tabs.forEach(function (t) {
      $("tab-" + t).addEventListener("click", function () {
        tabs.forEach(function (u) { $("tab-" + u).setAttribute("aria-selected", String(u === t)); $("panel-" + u).hidden = u !== t; });
      });
    });
    var nodes = [
      { t: "Ship the beta", x: 380, y: 44, cls: "root" },
      { t: "Fix the login bug", x: 120, y: 150, cls: "doing" },
      { t: "Write onboarding copy", x: 330, y: 150, cls: "next" },
      { t: "Record the demo", x: 530, y: 150, cls: "blocked" },
      { t: "Redo pricing page", x: 680, y: 150, cls: "crossed" },
      { t: "Reproduce on Safari", x: 120, y: 260, cls: "done" },
      { t: "Write FAQ", x: 330, y: 260, cls: "ghost" },
      { t: "Brand guidelines", x: 530, y: 260, cls: "locked" }
    ];
    var g = $("tourgraph");
    var svg = '<svg viewBox="0 0 840 470" style="position:absolute;inset:0;width:100%;height:100%" aria-hidden="true">';
    [[380, 44, 120, 150], [380, 44, 330, 150], [380, 44, 530, 150], [380, 44, 680, 150], [120, 150, 120, 260], [530, 150, 530, 260]].forEach(function (e) {
      var my = (e[1] + e[3]) / 2;
      svg += '<path d="M' + e[0] + ' ' + (e[1] + 15) + ' C' + e[0] + ' ' + my + ' ' + e[2] + ' ' + my + ' ' + e[2] + ' ' + (e[3] - 15) + '" fill="none" stroke="var(--line)"/>';
    });
    svg += '<path d="M330 165 C330 212 330 212 330 245" fill="none" stroke="var(--ink2)" stroke-dasharray="4 3"/>';
    svg += '<path d="M120 167 C 220 230, 430 230, 522 168" fill="none" stroke="var(--blocked)" stroke-dasharray="4 3"/><path d="M522 166 l-7 1 l4 -6 z" fill="var(--blocked)"/>';
    svg += '</svg>';
    g.innerHTML = svg;
    nodes.forEach(function (n) {
      var p = el("div", "pill " + (n.cls === "crossed" || n.cls === "locked" ? "" : n.cls));
      p.style.left = n.x + "px"; p.style.top = n.y + "px";
      p.appendChild(el("span", "pd"));
      if (n.cls === "locked") p.insertAdjacentHTML("beforeend", '<svg width="10" height="10" viewBox="0 0 10 10" aria-label="locked"><rect x="1.5" y="4.5" width="7" height="5" rx="1" fill="var(--ink2)"/><path d="M3 4.5V3a2 2 0 0 1 4 0v1.5" fill="none" stroke="var(--ink2)" stroke-width="1.2"/></svg>');
      var t = el("span", "", n.t);
      if (n.cls === "crossed") { p.style.opacity = "0.5"; t.style.textDecoration = "line-through"; }
      p.appendChild(t);
      g.appendChild(p);
    });
    var m = el("div", "ctxmenu");
    m.style.left = "626px"; m.style.top = "176px";
    ["Rename", "Add Child", "—", "Set as Doing", "Set as Next", "Mark Done", "—", "Cross Out", "Add Dependency…", "Lock (no suggestions)"].forEach(function (s, i) {
      if (s === "—") m.appendChild(el("hr")); else m.appendChild(el("span", i === 8 ? "hl" : "", s));
    });
    g.appendChild(m);
    var fit = el("span", "", "Fit"); fit.style.cssText = "position:absolute;left:14px;top:14px;font-size:0.74rem;border:1px solid var(--line);border-radius:6px;padding:3px 9px;color:var(--ink2)";
    g.appendChild(fit);
  })();
})();

// The top bar: underline the section in view.
(function () {
  var links = Array.prototype.slice.call(document.querySelectorAll(".nav a[href^='#']"));
  if (!links.length || !("IntersectionObserver" in window)) return;
  var byId = {}, seen = {};
  links.forEach(function (a) { var s = document.getElementById(a.getAttribute("href").slice(1)); if (s) byId[s.id] = a; });
  var io = new IntersectionObserver(function (es) {
    es.forEach(function (e) { if (e.isIntersecting) seen[e.target.id] = Math.abs(e.boundingClientRect.top); else delete seen[e.target.id]; });
    var cur = null;
    Object.keys(seen).forEach(function (id) { if (cur === null || seen[id] < seen[cur]) cur = id; });
    links.forEach(function (a) { a.classList.toggle("on", cur !== null && byId[cur] === a); });
  }, { rootMargin: "-30% 0px -55% 0px" });
  Object.keys(byId).forEach(function (id) { io.observe(document.getElementById(id)); });
})();
