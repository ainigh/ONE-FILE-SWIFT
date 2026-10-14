/* mapview.js: the mind map both maps draw with: B's Strategy board and Admin's Monitor.
   A hub in the middle, branches right and left with lines that taper with depth, cards that fold,
   links that cross the tree, hand-off pulses along any line, pan and zoom with Fit, Now and a
   minimap. Each map says what its nodes are and how a card reads; the map does the rest. */
"use strict";
// MindMap(canvas, o): o.root() the hub's id; o.tops() the hub's branches in order; o.kids(id);
// o.parent(id); o.ids() every node; o.fill(card, id) writes a card (its class and content).
// Optional: o.side(id, i) "r" or "l" for a top branch; o.below(id) px kept free under a card;
// o.links() [{ a, b, cls, head }] lines beside the tree; o.edgeCls(id) for the line into id;
// o.focus() the selected id; o.folded, an object the folds live in; o.overlays() after placing;
// o.mmCls(id) a minimap class; o.click/dblclick/context/enter/leave(id, e); o.moved() when B pans;
// o.now() for the Now button; o.legend [[cssVar | "dash" | "link", label]]; o.empty text.
function MindMap(canvas, o) {
  var CW = o.cardW || 208, GW = o.hubW || 232, HGAP = o.hgap || 56, VGAP = 14;
  var folded = o.folded || {}, cards = {}, heights = {}, L = null, hover = null, overlays = [], paths = {}, pulses = [];
  var view = { x: 0, y: 0, k: 1, auto: true };
  canvas.classList.add("mcanvas");
  var world = el("div", "mworld");
  world.innerHTML = '<svg class="medges" aria-hidden="true"><g></g><g></g><path class="mmeasure" d="M0 0"/></svg>';
  var svg = world.firstChild, gLines = svg.childNodes[0], gFx = svg.childNodes[1], measure = svg.childNodes[2];
  var box = el("div", "mcards"); world.appendChild(box);
  var empty = el("p", "mempty", o.empty || "Nothing here yet."); empty.hidden = true;
  var mini = el("div", "mmini"); mini.title = "Click to jump";
  mini.innerHTML = '<svg preserveAspectRatio="xMidYMid meet" aria-hidden="true"></svg>';
  var mm = mini.firstChild;
  var zoom = el("div", "mzoom"), zpct;
  function zbtn(label, tip, fn, cls) { var b = el("button", cls || "", label); b.type = "button"; b.title = tip; if (cls !== "pct") b.setAttribute("aria-label", tip); b.addEventListener("click", function (e) { e.stopPropagation(); fn(); }); zoom.appendChild(b); return b; }
  zbtn("−", "Zoom out", function () { zoomMid(1 / 1.2); });
  zpct = zbtn("100%", "Reset zoom", function () { zoomMid(1 / view.k); }, "pct");
  zbtn("+", "Zoom in", function () { zoomMid(1.2); });
  zoom.appendChild(el("span", "sep"));
  zbtn("Fit", "Fit the whole map (F)", function () { fit(true); });
  if (o.now) zbtn("Now", "Centre on Doing (N)", o.now);
  [world, empty, mini, zoom].forEach(function (x) { canvas.appendChild(x); });
  if (o.legend) {
    var lg = el("div", "mlegend"); lg.setAttribute("aria-hidden", "true");
    o.legend.forEach(function (it) { var s = el("span"), i = el("i", it[0] === "dash" || it[0] === "link" ? it[0] : ""); if (!i.className) i.style.background = css(it[0]); s.appendChild(i); s.appendChild(document.createTextNode(it[1])); lg.appendChild(s); });
    canvas.appendChild(lg);
  }

  // ----- layout: a horizontal tree each way from the hub -----
  function layout() {
    var hub = o.root(), pos = {}, b = { x0: 0, y0: 0, x1: 0, y1: 0 };
    if (!hub) return { pos: pos, bounds: b, hub: null };
    var sides = { r: [], l: [] }, memo = {};
    o.tops().forEach(function (r, i) { var s = o.side ? o.side(r, i) : (i % 2 ? "l" : "r"); sides[s === "l" ? "l" : "r"].push(r); });
    function hh(id) { return heights[id] || 44; }
    function extra(id) { return o.below ? o.below(id) : 0; }
    function own(id) { return hh(id) + extra(id); }
    function under(id) { return folded[id] ? [] : o.kids(id); }
    function h(id) {
      if (memo[id] != null) return memo[id];
      var ks = under(id), sum = 0; ks.forEach(function (k) { sum += h(k) + VGAP; });
      return (memo[id] = ks.length ? Math.max(own(id), sum - VGAP) : own(id));
    }
    function place(id, depth, y, dir) {
      var ks = under(id), H = h(id), x = dir * (GW / 2 + HGAP + (depth - 1) * (CW + HGAP) + CW / 2);
      pos[id] = { x: x, y: y + H / 2 - extra(id) / 2, w: CW, h: hh(id), depth: depth, dir: dir };
      var inner = ks.length ? ks.reduce(function (a, k) { return a + h(k) + VGAP; }, 0) - VGAP : 0, cy = y + (H - inner) / 2;
      ks.forEach(function (k) { place(k, depth + 1, cy, dir); cy += h(k) + VGAP; });
    }
    ["r", "l"].forEach(function (side) {
      var dir = side === "r" ? 1 : -1, list = sides[side];
      var y = -(list.reduce(function (a, k) { return a + h(k) + VGAP * 2; }, 0) - VGAP * 2) / 2;
      list.forEach(function (r) { place(r, 1, y, dir); y += h(r) + VGAP * 2; });
    });
    pos[hub] = { x: 0, y: 0, w: GW, h: heights[hub] || 84, depth: 0, dir: 0 };
    Object.keys(pos).forEach(function (k) { var q = pos[k]; b.x0 = Math.min(b.x0, q.x - q.w / 2); b.x1 = Math.max(b.x1, q.x + q.w / 2); b.y0 = Math.min(b.y0, q.y - q.h / 2); b.y1 = Math.max(b.y1, q.y + q.h / 2 + extra(k)); });
    return { pos: pos, bounds: b, hub: hub };
  }

  // ----- cards -----
  function bind(c, id) {
    c.addEventListener("pointerenter", function () { hover = id; drawEdges(); if (o.enter) o.enter(id); });
    c.addEventListener("pointerleave", function () { hover = null; drawEdges(); if (o.leave) o.leave(id); });
    c.addEventListener("click", function (e) { e.stopPropagation(); if (o.click) o.click(id, e); });
    c.addEventListener("dblclick", function (e) { e.stopPropagation(); if (o.dblclick) o.dblclick(id, e); });
    c.addEventListener("contextmenu", function (e) { if (!o.context) return; e.preventDefault(); e.stopPropagation(); o.context(id, e); });
    // A card is a focusable element, not a button, so a rename field inside it takes typing in every browser.
    c.addEventListener("keydown", function (e) {
      if (e.target !== c || (e.key !== "Enter" && e.key !== " ")) return;
      e.preventDefault(); e.stopPropagation(); if (o.click) o.click(id, e);
    });
  }
  function render() {
    var live = {};
    o.ids().forEach(function (id) {
      live[id] = true;
      var c = cards[id];
      if (!c) { c = cards[id] = el("div", "card"); c.tabIndex = 0; c.setAttribute("role", "button"); bind(c, id); box.appendChild(c); }
      c.hidden = false; o.fill(c, id);
    });
    Object.keys(cards).forEach(function (id) { if (!live[id]) { cards[id].remove(); delete cards[id]; delete heights[id]; } });
    // Measure, lay out, then place.
    Object.keys(cards).forEach(function (id) { heights[id] = cards[id].offsetHeight || heights[id]; });
    L = layout();
    Object.keys(cards).forEach(function (id) {
      var q = L.pos[id], c = cards[id];
      if (!q) { c.hidden = true; return; }
      c.style.left = (q.x - q.w / 2).toFixed(1) + "px"; c.style.top = (q.y - q.h / 2).toFixed(1) + "px";
    });
    overlays.forEach(function (x) { x.remove(); }); overlays = [];
    buildFolds();
    if (o.overlays) o.overlays();
    drawEdges();
    empty.hidden = !!L.hub;
    if (view.auto) fit(); else minimap();
  }
  // Rewrite one card without moving anything: for live content that keeps its height.
  function refill(id) { if (cards[id]) o.fill(cards[id], id); }
  function addOverlay(x, left, top) { x.style.left = left.toFixed(1) + "px"; x.style.top = top.toFixed(1) + "px"; box.appendChild(x); overlays.push(x); return x; }
  function buildFolds() {
    Object.keys(L.pos).forEach(function (id) {
      if (id === L.hub || !o.kids(id).length) return;
      var q = L.pos[id], f = !!folded[id], n = descendants(id).length;
      var b = el("button", "fold" + (f ? " folded" : ""), f ? String(n) : "–"); b.type = "button";
      b.title = f ? "Show " + n + " more" : "Fold this branch";
      b.addEventListener("click", function (e) { e.stopPropagation(); if (folded[id]) delete folded[id]; else folded[id] = true; if (o.folds) o.folds(); else render(); });
      addOverlay(b, q.x + q.dir * (q.w / 2 + 14) - 10, q.y - 10);  // on the line, just past the card, clear of its tags
    });
  }
  function descendants(id) { var out = []; o.kids(id).forEach(function (k) { out.push(k); out = out.concat(descendants(k)); }); return out; }
  function unfold(id) { var p = o.parent(id); while (p) { delete folded[p]; p = o.parent(p); } }

  // ----- lines: the tree, then the links beside it; the path to the hovered or selected node is lit -----
  function edgePath(a, b) {
    var dir = b.x > a.x ? 1 : -1, ax = a.x + dir * a.w / 2, bx = b.x - dir * b.w / 2, mx = (ax + bx) / 2;
    return "M" + ax + " " + a.y + " C" + mx + " " + a.y + " " + mx + " " + b.y + " " + bx + " " + b.y;
  }
  function linkPath(a, b) {
    var ax = a.x, ay = a.y + a.h / 2 + 2, bx = b.x, by = b.y + b.h / 2 + 2, c = Math.max(40, Math.abs(bx - ax) * 0.2) + 20;
    return "M" + ax + " " + ay + " C" + ax + " " + (ay + c) + " " + bx + " " + (by + c) + " " + bx + " " + (by + 1);
  }
  function drawEdges() {
    if (!L) return;
    var focus = hover || (o.focus ? o.focus() : null), lit = {}, out = "", side = "";
    paths = {};
    if (focus && L.pos[focus] && focus !== L.hub) { var k = focus; while (k && k !== L.hub) { lit[k] = true; k = o.parent(k); } }
    Object.keys(L.pos).forEach(function (id) {
      var parent = o.parent(id); if (!parent || !L.pos[parent]) return;
      var a = L.pos[parent], b = L.pos[id], w = Math.max(1.5, 5 - b.depth * 1.4), d = edgePath(a, b);
      paths[parent + "|" + id] = d;
      out += '<path class="edge' + (lit[id] ? " lit" : "") + (o.edgeCls ? " " + o.edgeCls(id) : "") + '" stroke-width="' + w + '" d="' + d + '"/>';
    });
    (o.links ? o.links() : []).forEach(function (l) {
      var a = L.pos[l.a], b = L.pos[l.b]; if (!a || !b) return;
      var d = linkPath(a, b); paths[l.a + "|" + l.b] = d;
      side += '<path class="' + l.cls + (focus === l.a || focus === l.b ? " lit" : "") + '" d="' + d + '"/>';
      if (l.head) side += '<path class="' + l.cls.replace(/\S+/, "$&head") + '" d="M' + b.x + " " + (b.y + b.h / 2 + 1) + ' l-4 7 l8 0 z"/>';
    });
    gLines.innerHTML = out + side;
  }
  // A hand-off: a dot runs the line between two nodes, either way, and the line glows as it fades.
  function pulse(from, to, color) { pulses.push({ from: from, to: to, color: color, start: performance.now() }); }
  function tick(now) {
    if (!pulses.length && !gFx.firstChild) return;
    var fx = "";
    pulses = pulses.filter(function (p) { return now - p.start < 480; });
    pulses.forEach(function (p) {
      var d = paths[p.from + "|" + p.to], back = false;
      if (!d) { d = paths[p.to + "|" + p.from]; back = true; }
      if (!d) return;
      measure.setAttribute("d", d);
      var len = measure.getTotalLength(), k = (now - p.start) / 480, e = 1 - (1 - k) * (1 - k), at = measure.getPointAtLength((back ? 1 - e : e) * len);
      fx += '<path d="' + d + '" fill="none" stroke="var(' + p.color + ')" stroke-opacity="' + (0.6 * (1 - k)).toFixed(2) + '" stroke-width="2.5"/>';
      if (!reduce) fx += '<circle cx="' + at.x.toFixed(1) + '" cy="' + at.y.toFixed(1) + '" r="4" fill="var(' + p.color + ')"/>';
    });
    gFx.innerHTML = fx;
  }

  // ----- pan and zoom: the map fits itself until someone moves it; Fit hands it back -----
  function apply() {
    world.style.transform = "translate(" + view.x.toFixed(1) + "px," + view.y.toFixed(1) + "px) scale(" + view.k + ")";
    zpct.textContent = Math.round(view.k * 100) + "%";
    minimap();
  }
  function moved() { view.auto = false; if (o.moved) o.moved(); }
  function zoomAt(f, cx, cy) { var k = Math.min(2.2, Math.max(0.3, view.k * f)); f = k / view.k; view.x = cx - (cx - view.x) * f; view.y = cy - (cy - view.y) * f; view.k = k; moved(); apply(); }
  function zoomMid(f) { var r = canvas.getBoundingClientRect(); zoomAt(f, r.width / 2, r.height / 2); }
  function fit(manual) {
    if (manual) { view.auto = true; if (o.moved) o.moved(); }
    var r = canvas.getBoundingClientRect();
    if (!L || !r.width || !r.height) return;
    var b = L.bounds, pad = 28, top = 14, bottom = 54, w = b.x1 - b.x0 + pad * 2, h = b.y1 - b.y0 + pad * 2;
    // Never shrink text past legible to fit: a big map stays centred and the rest is a pan away.
    view.k = Math.min(1, Math.max(0.55, Math.min(r.width / w, (r.height - top - bottom) / h)));
    view.x = (r.width - (b.x0 + b.x1) * view.k) / 2; view.y = top + (r.height - top - bottom - (b.y0 + b.y1) * view.k) / 2;
    apply();
  }
  function centre(id) {
    if (!L || !L.pos[id]) return;
    var r = canvas.getBoundingClientRect(), q = L.pos[id];
    view.k = Math.max(view.k, 1); view.x = r.width / 2 - q.x * view.k; view.y = r.height / 2 - q.y * view.k; moved(); apply();
  }
  function minimap() {
    if (!L) return;
    var b = L.bounds, pad = 40, r = canvas.getBoundingClientRect();
    if (!r.width) return;
    var vx0 = -view.x / view.k, vy0 = -view.y / view.k, vx1 = vx0 + r.width / view.k, vy1 = vy0 + r.height / view.k;
    var X0 = Math.min(b.x0, vx0) - pad, Y0 = Math.min(b.y0, vy0) - pad, X1 = Math.max(b.x1, vx1) + pad, Y1 = Math.max(b.y1, vy1) + pad;
    mm.setAttribute("viewBox", X0 + " " + Y0 + " " + (X1 - X0) + " " + (Y1 - Y0));
    var s = "";
    Object.keys(L.pos).forEach(function (id) { var q = L.pos[id]; s += '<rect class="n ' + (o.mmCls ? o.mmCls(id) : "") + '" x="' + (q.x - q.w / 2) + '" y="' + (q.y - q.h / 2) + '" width="' + q.w + '" height="' + q.h + '" rx="6"/>'; });
    s += '<rect class="view" x="' + vx0 + '" y="' + vy0 + '" width="' + (vx1 - vx0) + '" height="' + (vy1 - vy0) + '" rx="4"/>';
    mm.innerHTML = s;
  }
  var drag = null;
  canvas.addEventListener("pointerdown", function (e) {
    if (e.button !== 0 || e.target.closest(".card, button, input, .pop, .mprop, .mmini, .mlegend, .maim")) return;
    drag = { x: e.clientX, y: e.clientY, vx: view.x, vy: view.y, moved: false }; canvas.setPointerCapture(e.pointerId);
  });
  canvas.addEventListener("pointermove", function (e) {
    if (!drag) return;
    var dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    if (!drag.moved && Math.abs(dx) + Math.abs(dy) <= 3) return;
    if (!drag.moved) { drag.moved = true; canvas.classList.add("panning"); moved(); }
    view.x = drag.vx + dx; view.y = drag.vy + dy; apply();
  });
  canvas.addEventListener("pointerup", function () {
    if (!drag) return;
    var was = drag.moved; drag = null; canvas.classList.remove("panning");
    if (!was && o.background) o.background();
  });
  canvas.addEventListener("pointercancel", function () { drag = null; canvas.classList.remove("panning"); });
  canvas.addEventListener("wheel", function (e) {
    e.preventDefault();
    var r = canvas.getBoundingClientRect();
    if (e.ctrlKey || e.metaKey) zoomAt(Math.exp(-e.deltaY * 0.01), e.clientX - r.left, e.clientY - r.top);
    else { view.x -= e.deltaX; view.y -= e.deltaY; moved(); apply(); }
  }, { passive: false });
  mini.addEventListener("click", function (e) {
    e.stopPropagation();
    var pt = mm.createSVGPoint(); pt.x = e.clientX; pt.y = e.clientY;
    var w = pt.matrixTransform(mm.getScreenCTM().inverse()), r = canvas.getBoundingClientRect();
    view.x = r.width / 2 - w.x * view.k; view.y = r.height / 2 - w.y * view.k; moved(); apply();
  });
  // The map opens, closes and changes width with the screen around it: keep it fitted.
  if (window.ResizeObserver) new ResizeObserver(function () { if (view.auto) fit(); else minimap(); }).observe(canvas);
  function reset() {
    Object.keys(cards).forEach(function (id) { cards[id].remove(); });
    cards = {}; heights = {}; L = null; hover = null; pulses = []; view.auto = true;
    Object.keys(folded).forEach(function (k) { delete folded[k]; });
  }
  return {
    render: render, refill: refill, drawEdges: drawEdges, fit: fit, centre: centre, unfold: unfold, pulse: pulse, tick: tick, reset: reset, addOverlay: addOverlay,
    pos: function (id) { return L ? L.pos[id] : null; }, card: function (id) { return cards[id]; },
    hovered: function () { return hover; }, canvas: canvas, box: box
  };
}
