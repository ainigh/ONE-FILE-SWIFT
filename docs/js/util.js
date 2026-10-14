/* util.js: small helpers every other file uses: elements, CSS variables, clock digits, toasts.
   The app is a set of classic scripts that share one global scope, loaded in the order app.html
   lists them; each file only declares, and main.js starts the app once everything is defined. */
"use strict";
var C = 2 * Math.PI * 104;
var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
function $(id) { return document.getElementById(id); }
function css(name) { return "var(" + name + ")"; }
// Clock digits (6:12) and spoken lengths (10 min, 1:15, 45 s) come from announce.js, so every
// screen writes numbers the way the engine says them.
var digits = Announce.digits, fmt = Announce.fmt;
function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }

// ----- small view helpers -----
var toastText = "", toastErr = true;
function toast(t, info) { toastText = t; toastErr = !info; S.toastUntil = performance.now() + Math.min(8000, 2000 + t.length * 60); }
function act(fn) { return function (e) { if (e) e.stopPropagation(); fn(); render(true); }; }
function tone() {
  if (S.frozen) return "--stop";
  switch (S.state) { case "work": case "snooze": return "--doing"; case "status": return "--ink2"; case "strategy": return "--next"; case "break": return "--rest"; }
  return "--ink2";
}
