import MPMCore
import SwiftUI

// The mind map both maps draw with (mapview.js): a hub in the middle, branches right and left with
// lines that taper with depth, cards that fold, links that cross the tree, hand-off pulses along
// any line, pan and zoom with Fit and Now. Each map says what its nodes are and how a card reads.

struct MapPos: Equatable {
    var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    var depth: Int
    var dir: CGFloat
    var below: CGFloat
}

struct MapResult {
    var pos: [String: MapPos] = [:]
    var bounds: CGRect = .zero
    var hub: String?
}

struct MapSpec {
    var root: String?
    var tops: [String]
    var kids: (String) -> [String]
    var parent: (String) -> String?
    var ids: [String]
    var side: (String, Int) -> String
    var height: (String) -> CGFloat
    var below: (String) -> CGFloat
    var folded: Set<String>
    var cardW: CGFloat = 208
    var hubW: CGFloat = 232
    var hgap: CGFloat = 56
    var vgap: CGFloat = 14
}

enum MapLayout {
    static func layout(_ o: MapSpec) -> MapResult {
        var r = MapResult()
        guard let hub = o.root else { return r }
        r.hub = hub
        var sides: [String: [String]] = ["r": [], "l": []]
        for (i, t) in o.tops.enumerated() { let s = o.side(t, i); sides[s == "l" ? "l" : "r", default: []].append(t) }
        var memo: [String: CGFloat] = [:]
        func own(_ id: String) -> CGFloat { o.height(id) + o.below(id) }
        func under(_ id: String) -> [String] { o.folded.contains(id) ? [] : o.kids(id) }
        func h(_ id: String) -> CGFloat {
            if let m = memo[id] { return m }
            let ks = under(id)
            var sum: CGFloat = 0
            for k in ks { sum += h(k) + o.vgap }
            let v: CGFloat = ks.isEmpty ? own(id) : max(own(id), sum - o.vgap)
            memo[id] = v
            return v
        }
        func place(_ id: String, _ depth: Int, _ y: CGFloat, _ dir: CGFloat) {
            let ks = under(id)
            let H = h(id)
            let step: CGFloat = CGFloat(depth - 1) * (o.cardW + o.hgap)
            let x: CGFloat = dir * (o.hubW / 2 + o.hgap + step + o.cardW / 2)
            let b = o.below(id)
            r.pos[id] = MapPos(x: x, y: y + H / 2 - b / 2, w: o.cardW, h: o.height(id), depth: depth, dir: dir, below: b)
            var inner: CGFloat = 0
            for k in ks { inner += h(k) + o.vgap }
            if !ks.isEmpty { inner -= o.vgap }
            var cy: CGFloat = y + (H - inner) / 2
            for k in ks {
                place(k, depth + 1, cy, dir)
                cy += h(k) + o.vgap
            }
        }
        for side in ["r", "l"] {
            let dir: CGFloat = side == "r" ? 1 : -1
            let list = sides[side] ?? []
            var total: CGFloat = 0
            for t in list { total += h(t) + o.vgap * 2 }
            total -= o.vgap * 2
            var y: CGFloat = -total / 2
            for t in list {
                place(t, 1, y, dir)
                y += h(t) + o.vgap * 2
            }
        }
        r.pos[hub] = MapPos(x: 0, y: 0, w: o.hubW, h: o.height(hub), depth: 0, dir: 0, below: 0)
        var b = CGRect(x: 0, y: 0, width: 0, height: 0)
        var x0: CGFloat = 0, y0: CGFloat = 0, x1: CGFloat = 0, y1: CGFloat = 0
        for (_, q) in r.pos {
            x0 = min(x0, q.x - q.w / 2); x1 = max(x1, q.x + q.w / 2)
            y0 = min(y0, q.y - q.h / 2); y1 = max(y1, q.y + q.h / 2 + q.below)
        }
        b = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        r.bounds = b
        return r
    }

    static func edgePath(_ a: MapPos, _ b: MapPos) -> Path {
        let dir: CGFloat = b.x > a.x ? 1 : -1
        let ax = a.x + dir * a.w / 2, bx = b.x - dir * b.w / 2, mx = (ax + bx) / 2
        var p = Path()
        p.move(to: CGPoint(x: ax, y: a.y))
        p.addCurve(to: CGPoint(x: bx, y: b.y), control1: CGPoint(x: mx, y: a.y), control2: CGPoint(x: mx, y: b.y))
        return p
    }

    static func linkPath(_ a: MapPos, _ b: MapPos) -> Path {
        let ax = a.x, ay = a.y + a.h / 2 + 2, bx = b.x, by = b.y + b.h / 2 + 2
        let c = max(40, abs(bx - ax) * 0.2) + 20
        var p = Path()
        p.move(to: CGPoint(x: ax, y: ay))
        p.addCurve(to: CGPoint(x: bx, y: by + 1), control1: CGPoint(x: ax, y: ay + c), control2: CGPoint(x: bx, y: by + c))
        return p
    }
}

struct MapLink {
    var a: String
    var b: String
    var color: Color
    var dashed: Bool
    var head: Bool
    var faded: Bool
}

struct MapPulse {
    var from: String
    var to: String
    var color: Color
    /// 0 … 1 along the line.
    var k: Double
}

/// The map: lays the cards out, draws the lines, pans and zooms. The caller draws each card.
struct MapView<CardContent: View, Overlay: View>: View {
    var spec: MapSpec
    var links: [MapLink]
    var pulses: [MapPulse]
    var focus: String?
    var legend: [(Color, String, Bool)]
    var empty: String
    var onBackground: () -> Void
    var onFold: (String) -> Void
    var now: (() -> Void)?
    /// Fit when this changes (F); scroll to `centreOn` and zoom in when `centreTick` changes (N).
    var fitTick = 0
    var centreOn: String? = nil
    var centreTick = 0
    @ViewBuilder var card: (String, MapPos) -> CardContent
    @ViewBuilder var overlay: (String, MapPos) -> Overlay

    @State private var zoom: CGFloat? = nil
    @State private var pinchStart: CGFloat? = nil
    @State private var hover: String?

    var body: some View {
        let L = MapLayout.layout(spec)
        GeometryReader { geo in
            let pad: CGFloat = 28
            let bw = L.bounds.width + pad * 2, bh = L.bounds.height + pad * 2
            let avail = CGSize(width: max(1, geo.size.width), height: max(1, geo.size.height - 68))
            let inner = CGSize(width: max(0, geo.size.width), height: max(0, geo.size.height - 68))
            let fitK = max(0.55, min(1, min(avail.width / max(bw, 1), avail.height / max(bh, 1))))
            let k = zoom ?? fitK
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onTapGesture { onBackground() }
                if L.hub == nil {
                    Text(empty).font(Theme.body).foregroundStyle(Color.ink3).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            Color.clear.contentShape(Rectangle()).onTapGesture { onBackground() }
                            Canvas { ctx, _ in
                                let ox = -L.bounds.minX + pad, oy = -L.bounds.minY + pad
                                var lit: Set<String> = []
                                if let f = hover ?? focus, f != L.hub, L.pos[f] != nil {
                                    var kk: String? = f
                                    while let q = kk, q != L.hub { lit.insert(q); kk = spec.parent(q) }
                                }
                                ctx.translateBy(x: ox, y: oy)
                                for (id, q) in L.pos {
                                    guard let parent = spec.parent(id), let a = L.pos[parent] else { continue }
                                    let w = max(1.5, 5 - CGFloat(q.depth) * 1.4)
                                    let p = MapLayout.edgePath(a, q)
                                    ctx.stroke(p, with: .color(lit.contains(id) ? Color.doing.opacity(0.9) : Color.line2), style: StrokeStyle(lineWidth: w, lineCap: .round))
                                }
                                for l in links {
                                    guard let a = L.pos[l.a], let b = L.pos[l.b] else { continue }
                                    let p = MapLayout.linkPath(a, b)
                                    let isLit = focus == l.a || focus == l.b || hover == l.a || hover == l.b
                                    let color = l.faded ? Color.ink3.opacity(0.5) : l.color.opacity(isLit ? 1 : 0.8)
                                    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: isLit ? 2.2 : 1.6, dash: l.dashed ? [5, 4] : []))
                                    if l.head {
                                        var h = Path()
                                        h.move(to: CGPoint(x: b.x, y: b.y + b.h / 2 + 1))
                                        h.addLine(to: CGPoint(x: b.x - 4, y: b.y + b.h / 2 + 8))
                                        h.addLine(to: CGPoint(x: b.x + 4, y: b.y + b.h / 2 + 8))
                                        h.closeSubpath()
                                        ctx.fill(h, with: .color(color))
                                    }
                                }
                                for pl in pulses {
                                    guard let a = L.pos[pl.from], let b = L.pos[pl.to] else { continue }
                                    let tree = spec.parent(pl.to) == pl.from || spec.parent(pl.from) == pl.to
                                    let fwd = spec.parent(pl.to) == pl.from
                                    let p = tree ? MapLayout.edgePath(fwd ? a : b, fwd ? b : a) : MapLayout.linkPath(a, b)
                                    ctx.stroke(p, with: .color(pl.color.opacity(0.6 * (1 - pl.k))), style: StrokeStyle(lineWidth: 2.5))
                                    let e = 1 - (1 - pl.k) * (1 - pl.k)
                                    let t = tree && !fwd ? 1 - e : e
                                    if let pt = p.trimmedPath(from: 0, to: max(0.001, t)).currentPoint {
                                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)), with: .color(pl.color))
                                    }
                                }
                            }
                            .frame(width: bw, height: bh)
                            .allowsHitTesting(false)
                            ForEach(Array(L.pos.keys).sorted(), id: \.self) { id in
                                if let q = L.pos[id] {
                                    card(id, q)
                                        .frame(width: q.w, height: q.h)
                                        .position(x: q.x - L.bounds.minX + pad, y: q.y - L.bounds.minY + pad)
                                        .onHover { hover = $0 ? id : (hover == id ? nil : hover) }
                                        .id(id)
                                    overlay(id, q)
                                        .position(x: q.x - L.bounds.minX + pad, y: q.y + q.h / 2 + q.below / 2 - L.bounds.minY + pad)
                                    if id != L.hub, !spec.kids(id).isEmpty {
                                        let f = spec.folded.contains(id)
                                        let n = descendants(id).count
                                        Button { onFold(id) } label: {
                                            Text(f ? "\(n)" : "–").font(.system(size: 10, weight: .bold)).foregroundStyle(f ? Color.white : Color.ink2)
                                                .frame(width: 20, height: 20)
                                                .background(Circle().fill(f ? Color.doing : Color.surface))
                                                .overlay(Circle().strokeBorder(Color.line2, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .help(f ? "Show \(n) more" : "Fold this branch")
                                        .position(x: q.x + q.dir * (q.w / 2 + 14) - L.bounds.minX + pad, y: q.y - L.bounds.minY + pad)
                                    }
                                }
                            }
                        }
                        .frame(width: bw, height: bh)
                        .scaleEffect(k, anchor: .topLeading)
                        .frame(width: bw * k, height: bh * k)
                        .frame(minWidth: inner.width, minHeight: inner.height)
                    }
                    .gesture(MagnifyGesture()
                        .onChanged { v in
                            let start = pinchStart ?? (zoom ?? fitK)
                            pinchStart = start
                            zoom = min(2.2, max(0.3, start * v.magnification))
                        }
                        .onEnded { _ in pinchStart = nil })
                    .onChange(of: fitTick) { _, _ in zoom = nil }
                    .onChange(of: centreTick) { _, _ in
                        guard let c = centreOn, L.pos[c] != nil else { return }
                        zoom = max(zoom ?? fitK, 1)
                        DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(c, anchor: .center) } }
                    }
                    }
                }
                // Zoom, Fit, Now, and the legend, along the bottom.
                VStack { Spacer(); HStack(alignment: .bottom) {
                    HStack(spacing: 10) {
                        ForEach(Array(legend.enumerated()), id: \.offset) { _, l in
                            HStack(spacing: 4) {
                                if l.2 { Rectangle().fill(Color.clear).frame(width: 14, height: 1).overlay(Rectangle().stroke(l.0, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))) }
                                else { Circle().fill(l.0).frame(width: 8, height: 8) }
                                Text(l.1).font(Theme.fine).foregroundStyle(Color.ink2)
                            }
                        }
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        zoomButton("−") { zoom = max(0.3, (zoom ?? fitK) / 1.2) }
                        Button("\(Int((k * 100).rounded()))%") { zoom = 1 }.buttonStyle(.plain).font(Theme.mono(11)).foregroundStyle(Color.ink2).frame(width: 44)
                        zoomButton("+") { zoom = min(2.2, (zoom ?? fitK) * 1.2) }
                        Rectangle().fill(Color.line).frame(width: 1, height: 14)
                        zoomButton("Fit") { zoom = nil }
                        if let now = now { zoomButton("Now") { now() } }
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
                }.padding(10) }
            }
        }
    }

    private func descendants(_ id: String) -> [String] {
        var out: [String] = []
        for k in spec.kids(id) { out.append(k); out += descendants(k) }
        return out
    }

    private func zoomButton(_ t: String, _ f: @escaping () -> Void) -> some View {
        Button(t, action: f).buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ink).padding(.horizontal, 8).padding(.vertical, 3)
    }
}
