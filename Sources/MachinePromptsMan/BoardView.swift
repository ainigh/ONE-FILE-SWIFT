import MPMCore
import SwiftUI

/// The Strategy board (board.js): the map and its inspector, the read-only grid, the quick-add field.
struct BoardView: View {
    @EnvironmentObject var app: AppModel
    @State private var quick = ""

    var body: some View {
        let s = app.session
        let blk = s.editBlock()
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label2("Strategy board")
                Seg(items: [(BoardMode.map, "Map"), (.table, "Table")], selection: Binding(get: { app.boardView }, set: { app.setBoard(app.boardOpen, $0) }))
                Spacer()
                if s.bView() != .plan {
                    Button("Close the board ‹") { app.setBoard(false) }.buttonStyle(LinkishStyle())
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            if let b = blk, s.state != .break {
                Text(b).font(Theme.fine).foregroundStyle(Color.blocked).padding(.horizontal, 14).padding(.bottom, 6)
            }
            BoardTop()
            if app.boardView == .map {
                GeometryReader { g in
                    HStack(spacing: 0) {
                        StrategyMap()
                            .overlay(alignment: .top) {
                                if let d = app.depFor {
                                    HStack(spacing: 10) {
                                        Text("Choose what “\(s.title(d) ?? "")” waits for").font(Theme.body).foregroundStyle(Color.ink)
                                        Button("Esc · cancel") { app.depFor = nil }.buttonStyle(MPMButtonStyle(kind: .small))
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.doing.opacity(0.7)))
                                    .padding(.top, 8)
                                }
                            }
                        // The inspector needs room; narrower, the context menu carries the same actions.
                        if g.size.width >= 900 {
                            Rectangle().fill(Color.line).frame(width: 1)
                            InspectorView().frame(width: 260)
                        }
                    }
                }
            } else {
                GridTable(forA: false)
            }
            HStack(spacing: 8) {
                TextField("Add a step under the selection", text: $quick)
                    .textFieldStyle(.roundedBorder)
                    .disabled(blk != nil)
                    .onChange(of: quick) { _, v in if v.count > 60 { quick = String(v.prefix(60)) } }
                    .onSubmit {
                        let v = quick.trimmingCharacters(in: .whitespaces)
                        guard !v.isEmpty else { return }
                        if s.addChild(s.selected ?? s.goal(), v) != nil { quick = "" }
                    }
                Text("under \(s.title(s.selected) ?? s.title(s.goal()) ?? "the goal")").font(Theme.fine).foregroundStyle(Color.ink3)
                DictateButton { quick = $0 }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            HStack {
                Text(hint(s)).font(Theme.fine).foregroundStyle(Color.ink3)
                Spacer()
                if app.boardView == .map { Text("Scroll to pan · − + to zoom · F fits the map · N centres on Doing").font(Theme.fine).foregroundStyle(Color.ink3) }
            }
            .padding(.horizontal, 14).padding(.bottom, 8)
        }
        .opacity(blk != nil ? 0.6 : 1)
    }

    private func hint(_ s: Session) -> String {
        if let d = app.depFor { return "Click the step \(s.title(d) ?? "") waits for. Esc cancels." }
        if s.canPick() { return "Hover a step and pick Doing or Next. Click a step for everything else." }
        if s.state == .work || s.state == .snooze { return "Hover Doing or Next to mark it done. Doing and Next are chosen when you plan." }
        return "Click a step for its actions. Double-click to rename."
    }
}

/// At plan start, above the board: the round's diff, once, and the assistant's note for B.
struct BoardTop: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        let planning = s.state == .strategy && !s.frozen
        let say = planning ? (s.held.flatMap { !$0.thinking && !$0.failed ? $0.say : nil } ?? "") : ""
        let props = planning ? (s.held?.props.filter { !$0.stale }.count ?? 0) : 0
        if planning && (!s.diff.isEmpty || !say.isEmpty) {
            HStack(alignment: .top, spacing: 12) {
                if !s.diff.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label2("Round \(s.round): what changed")
                        ForEach(Array(s.diff.enumerated()), id: \.offset) { _, l in
                            HStack { Text(l.title).foregroundStyle(Color.ink); Spacer(); Text("\(l.from.word) → \(l.to.word)").foregroundStyle(Color.ink2) }.font(Theme.fine)
                        }
                    }
                    .padding(10).frame(maxWidth: 320, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.surface)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line))
                }
                if !say.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label2("From the assistant", color: .rest)
                        Text(say + (props > 0 ? " " + (props == 1 ? "One suggestion is" : "\(props) suggestions are") + " on the map: accept or skip each." : "")).font(Theme.body).foregroundStyle(Color.ink)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.surface)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.rest.opacity(0.5)))
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 8)
        }
    }
}

/// The plan as a mind map: the goal in the middle, steps branching out; Doing filled, Next outlined,
/// waiting dashed amber, done faded with a check, crossed out struck through.
struct StrategyMap: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        let hub = s.goal()
        let tops = hub.map { h in s.kids(h) + s.nodes.keys.filter { s.nodes[$0]?.parent == nil && $0 != h }.sorted() } ?? []
        let props = s.mapProps()
        let spec = MapSpec(root: hub, tops: tops, kids: { s.kids($0) }, parent: { s.nodes[$0]?.parent }, ids: Array(s.nodes.keys),
                           side: { _, i in i % 2 == 1 ? "l" : "r" },
                           height: { $0 == hub ? 100 : 52 },
                           below: { id in props.contains { $0.targets[0] == id } ? 34 : 0 },
                           folded: app.folded)
        var links: [MapLink] = []
        for id in s.nodes.keys.sorted() where !s.isClosed(id) {
            for d in s.nodes[id]!.deps where s.nodes[d] != nil {
                links.append(MapLink(a: d, b: id, color: .blocked, dashed: true, head: true, faded: s.finished(d)))
            }
        }
        return MapView(spec: spec, links: links, pulses: [], focus: s.selected,
                       legend: [(.doing, "Doing", false), (.next, "Next", false), (.done, "Done", false), (.blocked, "Waits for", true), (.rest, "Assistant", false)],
                       empty: "No steps yet. Add one below.",
                       onBackground: {
                           if app.depFor != nil { app.depFor = nil } else if s.selected != nil { s.selected = nil }
                       },
                       onFold: { id in if app.folded.contains(id) { app.folded.remove(id) } else { app.folded.insert(id) } },
                       now: { app.centreOnDoing() },
                       fitTick: app.mapFit, centreOn: app.mapCentre, centreTick: app.mapCentreTick,
                       card: { id, _ in StepCard(id: id) },
                       overlay: { id, _ in
                           if let p = props.first(where: { $0.targets[0] == id }) {
                               HStack(spacing: 6) {
                                   Text("Assistant:").font(Theme.fine).foregroundStyle(Color.ink2)
                                   Text(p.kind == .done ? "done?" : "cross out?").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink)
                                   Button("Accept") { s.acceptProp(p) }.buttonStyle(MPMButtonStyle(kind: .smallPrimary)).help(p.text)
                                   Button("Skip") { s.rejectProp(p) }.buttonStyle(MPMButtonStyle(kind: .small)).help("Skip: \(p.text)")
                               }
                               .padding(.horizontal, 8).padding(.vertical, 3)
                               .background(RoundedRectangle(cornerRadius: 8).fill(Color.surface)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.rest.opacity(0.6)))
                           }
                       })
    }
}

/// One step on the map.
struct StepCard: View {
    @EnvironmentObject var app: AppModel
    let id: NodeID
    @State private var hovering = false
    @State private var leave: DispatchWorkItem?
    @State private var draft = ""
    @FocusState private var renameFocus: Bool

    var body: some View {
        let s = app.session
        if let n = s.nodes[id] {
            let ds = s.mapStatus(id)
            let editable = s.editBlock() == nil
            let selected = s.selected == id
            let aimable = app.depFor != nil && app.depFor != id && !n.root
            ZStack(alignment: .top) {
                cardBody(s, n, ds, selected: selected, aimable: aimable)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if editable { s.selected = id; app.renaming = id; draft = n.title } else { app.showToast(s.editBlock() ?? "", error: true) } }
                    .onTapGesture {
                        if let f = app.depFor { if n.root { return }; app.depFor = nil; if f != id { s.addDep(f, on: id) }; return }
                        if app.renaming != nil && app.renaming != id { app.renaming = nil }
                        s.selected = selected ? nil : id
                    }
                    .contextMenu { NodeMenu(id: id) }
                if hovering || app.renaming == id, let picks = pickButtons(s, n), !picks.isEmpty, app.renaming != id, app.depFor == nil, !n.root, editable {
                    HStack(spacing: 4) {
                        ForEach(Array(picks.enumerated()), id: \.offset) { _, p in
                            Button(p.0) { p.2?() }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(p.1 ? Color.white : Color.ink)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(p.1 ? p.3 : Color.surface))
                                .overlay(Capsule().strokeBorder(p.3, lineWidth: 1))
                                .disabled(p.2 == nil)
                                .help(p.4)
                        }
                    }
                    .offset(y: -13)
                    .transition(.opacity)
                }
            }
            // The pills sit above the card's edge: the hover region is the whole stack, and leaving
            // it waits a moment, so the pointer can reach a pill without the pills vanishing.
            .onHover { inside in
                leave?.cancel()
                if inside { hovering = true } else {
                    let w = DispatchWorkItem { hovering = false }
                    leave = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
                }
            }
        }
    }

    /// Hover a step: Doing and Next while B plans; Mark done on Doing or Next during a round.
    private func pickButtons(_ s: Session, _ n: Node) -> [(String, Bool, (() -> Void)?, Color, String)]? {
        var items: [(String, Bool, (() -> Void)?, Color, String)] = []
        if s.canPick() && !s.isClosed(id) {
            let pair = s.commitPair()
            for (which, label, cur, color) in [(PickSlot.d, "Doing", pair.d, Color.doing), (.n, "Next", pair.n, Color.next)] {
                let on = cur == id
                let kept = on && (which == .d ? s.picks.d : s.picks.n) != id
                if !on && s.pickReason(id, which) != nil { continue }
                items.append((label, on, kept ? nil : { s.pick(which, id) }, color,
                              kept ? "\(label) from last round. Pick another step to change it." : on ? "Clear \(label)" : "Set as \(label)"))
            }
        } else if (s.state == .work || s.state == .snooze) && (s.slot(.doing) == id || s.slot(.next) == id) && !s.isClosed(id) {
            items.append(("Mark done", false, { s.markDone(id) }, .done, "Mark \(n.title) done"))
        }
        return items
    }

    @ViewBuilder
    private func cardBody(_ s: Session, _ n: Node, _ ds: DisplayStatus, selected: Bool, aimable: Bool) -> some View {
        let fill: Color = ds == .doing ? .doing : .surface
        let stroke: Color = selected ? .ink : ds == .next ? .next : ds == .blocked ? .blocked : aimable ? .doing : .line2
        VStack(alignment: .leading, spacing: 3) {
            if n.root {
                let leaves = s.leafSteps(), done = leaves.filter(s.finished).count
                Label2("Goal")
                if app.renaming == id { renameField(s, n) } else { Text(n.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink).lineLimit(2) }
                HStack(spacing: 6) {
                    Ring(fraction: leaves.isEmpty ? 1 : 1 - Double(done) / Double(leaves.count), color: .done, lineWidth: 3).frame(width: 18, height: 18)
                    Text("\(done) of \(leaves.count) steps done").font(Theme.fine).foregroundStyle(Color.ink2)
                }
            } else {
                HStack(spacing: 6) {
                    ZStack {
                        Circle().strokeBorder(ds == .doing ? Color.white.opacity(0.8) : Theme.status(ds), lineWidth: 1.5)
                        if ds == .done { Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(Color.done) }
                    }.frame(width: 12, height: 12)
                    if app.renaming == id { renameField(s, n) } else {
                        Text(n.title).font(.system(size: 12.5, weight: ds == .doing ? .semibold : .medium))
                            .foregroundStyle(ds == .doing ? Color.white : ds == .done || ds == .crossed ? Color.ink2 : Color.ink)
                            .strikethrough(ds == .crossed, color: .ink2)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if n.locked { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(ds == .doing ? Color.white.opacity(0.8) : Color.ink3) }
                    if ds == .doing || ds == .next || ds == .blocked {
                        Text(ds == .blocked ? "waits" : ds.rawValue).font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ds == .doing ? Color.doing : Color.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(ds == .doing ? Color.white : Theme.status(ds)))
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(stroke, style: StrokeStyle(lineWidth: selected ? 2 : 1.2, dash: ds == .blocked && !selected ? [4, 3] : [])))
        .opacity(ds == .done || ds == .crossed ? 0.6 : 1)
        .help(n.root ? n.title : "\(n.title) · updated \(Format.updatedWord(n.updated, now: s.W))")
    }

    private func renameField(_ s: Session, _ n: Node) -> some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.ink)
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.surface2))
            .focused($renameFocus)
            .onAppear { draft = n.title; renameFocus = true }
            .onChange(of: draft) { _, v in if v.count > 60 { draft = String(v.prefix(60)) } }
            .onSubmit { app.renaming = nil; s.rename(id, draft) }
            .onExitCommand { app.renaming = nil }
            // Clicking elsewhere commits too, as on the page.
            .onChange(of: renameFocus) { _, f in if !f, app.renaming == id { app.renaming = nil; s.rename(id, draft) } }
    }
}

/// The step's menu (nodeMenu), for the context menu and the inspector.
struct NodeMenu: View {
    @EnvironmentObject var app: AppModel
    let id: NodeID

    var body: some View {
        let s = app.session
        if let n = s.nodes[id] {
            if let blk = s.editBlock() {
                Text(blk)
            } else {
                if !n.root {
                    if s.canPick() {
                        let whyD = s.picks.d == id ? nil : s.pickReason(id, .d), whyN = s.picks.n == id ? nil : s.pickReason(id, .n)
                        Button((s.picks.d == id ? "Clear Doing" : "Set as Doing") + (whyD.map { " — \($0)" } ?? "")) { s.pick(.d, id) }.disabled(whyD != nil)
                        Button((s.picks.n == id ? "Clear Next" : "Set as Next") + (whyN.map { " — \($0)" } ?? "")) { s.pick(.n, id) }.disabled(whyN != nil)
                        Divider()
                    } else {
                        Text("Doing and Next are chosen when you plan.")
                        Divider()
                    }
                    if s.finished(id) {
                        let w = s.unfinishedDeps(id).first.map { "Waiting for \(s.title($0) ?? "")." }
                        Button("Mark Open" + (w.map { " — \($0)" } ?? "")) { s.reopen(id) }.disabled(w != nil)
                    }
                    else if n.status != .crossed { Button("Mark Done") { s.markDone(id) } }
                    if n.status == .crossed { Button("Restore") { s.restore(id) } } else { Button("Cross Out") { s.crossOut(id) } }
                    Divider()
                }
                Button("Rename") { app.renaming = id; s.selected = id }
                Button("Add Step Under") { if let k = s.addChild(id) { s.selected = k; app.renaming = k } }
                if !n.root {
                    Button("Add Dependency…") { app.depFor = id }
                    if !n.deps.isEmpty { Button("Remove Dependency") { s.removeDep(id) } }
                    Divider()
                    Button(n.locked ? "Unlock" : "Lock (no suggestions)") { s.setLock(id, !n.locked) }
                }
            }
        }
    }
}

/// The inspector beside the map: the selected step, what it waits for and unblocks, and its actions.
struct InspectorView: View {
    @EnvironmentObject var app: AppModel
    @State private var name = ""

    var body: some View {
        let s = app.session
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let id = s.selected, let n = s.nodes[id] {
                    let ds = s.mapStatus(id)
                    TextField(n.root ? "Goal" : "Step", text: $name)
                        .textFieldStyle(.roundedBorder).font(.system(size: 13, weight: .semibold))
                        .disabled(s.editBlock() != nil)
                        .onAppear { name = n.title }
                        .onChange(of: id) { _, _ in name = n.title }
                        .onChange(of: n.title) { _, t in name = t }
                        .onChange(of: name) { _, v in if v.count > 60 { name = String(v.prefix(60)) } }
                        .onSubmit { s.rename(id, name) }
                    let path = s.pathOf(id)
                    if !path.isEmpty { Text(path.joined(separator: "  ›  ")).font(Theme.fine).foregroundStyle(Color.ink3) }
                    HStack(spacing: 6) {
                        Circle().fill(n.root ? Color.ink3 : Theme.status(ds)).frame(width: 8, height: 8)
                        Text(n.root ? "The goal" : ds.word.prefix(1).uppercased() + ds.word.dropFirst()).font(Theme.body).foregroundStyle(Color.ink)
                    }
                    if !n.root {
                        row("Waits for") {
                            if n.deps.isEmpty { Text("nothing").foregroundStyle(Color.ink3) }
                            ForEach(n.deps, id: \.self) { d in chip(s.title(d) ?? "", warn: !s.finished(d)) }
                        }
                        let by = s.nodes.keys.filter { s.nodes[$0]!.deps.contains(id) }.sorted()
                        row("Unblocks") {
                            if by.isEmpty { Text("nothing").foregroundStyle(Color.ink3) }
                            ForEach(by, id: \.self) { d in chip(s.title(d) ?? "", warn: false) }
                        }
                        row("Updated") { Text(Format.updatedWord(n.updated, now: s.W)).foregroundStyle(Color.ink2) }
                    }
                    let ks = s.kids(id)
                    if !ks.isEmpty { row("Steps") { Text("\(ks.filter(s.finished).count) of \(ks.count) done").foregroundStyle(Color.ink2) } }
                    Rectangle().fill(Color.line).frame(height: 1)
                    InspectorActions(id: id)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing selected").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                        Text("Click a step to see what it waits for and what you can do to it. F fits the map, N centres on Doing.").font(Theme.fine).foregroundStyle(Color.ink2)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bg)
    }

    private func row<V: View>(_ k: String, @ViewBuilder _ v: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label2(k)
            // Chips wrap onto new lines when a step waits for several.
            Flow(spacing: 4) { v() }.font(Theme.fine)
        }
    }

    private func chip(_ t: String, warn: Bool) -> some View {
        Text(t).font(Theme.fine).foregroundStyle(warn ? Color.blocked : Color.ink)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.surface2)).overlay(Capsule().strokeBorder(warn ? Color.blocked.opacity(0.6) : Color.line))
    }
}

/// The inspector's actions: the same items as the menu, as buttons with why one is off.
struct InspectorActions: View {
    @EnvironmentObject var app: AppModel
    let id: NodeID

    var body: some View {
        let s = app.session
        if let n = s.nodes[id] {
            VStack(alignment: .leading, spacing: 4) {
                if let blk = s.editBlock() {
                    Text(blk).font(Theme.fine).foregroundStyle(Color.blocked)
                } else {
                    if !n.root && s.canPick() {
                        act(s.picks.d == id ? "Clear Doing" : "Set as Doing", "D", why: s.picks.d == id ? nil : s.pickReason(id, .d)) { s.pick(.d, id) }
                        act(s.picks.n == id ? "Clear Next" : "Set as Next", "N", why: s.picks.n == id ? nil : s.pickReason(id, .n)) { s.pick(.n, id) }
                        Rectangle().fill(Color.line).frame(height: 1)
                    }
                    if !n.root {
                        if s.finished(id) { act("Mark Open", nil, why: s.unfinishedDeps(id).first.map { "Waiting for \(s.title($0) ?? "")." }) { s.reopen(id) } }
                        else if n.status != .crossed { act("Mark Done", nil, why: nil) { s.markDone(id) } }
                        if n.status == .crossed { act("Restore", nil, why: nil) { s.restore(id) } } else { act("Cross Out", "⌫", why: nil) { s.crossOut(id) } }
                        Rectangle().fill(Color.line).frame(height: 1)
                    }
                    act("Rename", "↩", why: nil) { app.renaming = id }
                    act("Add Step Under", "A", why: nil) { if let k = s.addChild(id) { s.selected = k; app.renaming = k } }
                    if !n.root {
                        act("Add Dependency…", nil, why: nil) { app.depFor = id }
                        if !n.deps.isEmpty { act("Remove Dependency", nil, why: nil) { s.removeDep(id) } }
                        Rectangle().fill(Color.line).frame(height: 1)
                        act(n.locked ? "Unlock" : "Lock (no suggestions)", nil, why: nil) { s.setLock(id, !n.locked) }
                        if !s.canPick() { Text("Doing and Next are chosen when you plan.").font(Theme.fine).foregroundStyle(Color.ink3) }
                    }
                }
            }
        }
    }

    private func act(_ label: String, _ sc: String?, why: String?, _ f: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Button(action: f) {
                HStack { Text(label); Spacer(); if let sc = sc { Text(sc).font(Theme.mono(10)).foregroundStyle(Color.ink3) } }
                    .font(Theme.body).foregroundStyle(why == nil ? Color.ink : Color.ink3)
                    .padding(.vertical, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(why != nil)
            if let w = why { Text(w).font(Theme.fine).foregroundStyle(Color.ink3) }
        }
    }
}

/// The grid (grid.js, addendum §7): read-only for everyone, round by round.
struct GridTable: View {
    @EnvironmentObject var app: AppModel
    var forA: Bool

    var body: some View {
        let s = app.session
        let rounds = s.rounds.keys.sorted()
        let k = s.rounds[app.gridRound] != nil ? app.gridRound : 0
        let info = k > 0 ? s.rounds[k] : nil
        let live = k == 0 || info?.end == nil
        let base: [NodeID: DisplayStatus]? = k > 0 ? info?.start : (s.round > 0 ? s.rounds[s.round]?.start : nil)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Round").font(Theme.fine).foregroundStyle(Color.ink2)
                Seg(items: rounds.map { ($0, String($0)) } + [(0, "Now")], selection: Binding(get: { k }, set: { app.gridRound = $0 }))
                Text((k > 0 ? "Round \(k)" + (info?.end != nil ? ", as it ended" : ", in progress") : s.round > 0 ? "Now; changes since round \(s.round) started" : "Now") + ". Read only: the System writes it from the plan.")
                    .font(Theme.fine).foregroundStyle(Color.ink3)
                Spacer()
            }
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        head("Step").frame(maxWidth: .infinity, alignment: .leading)
                        head("Status").frame(width: 90, alignment: .leading)
                        head("This round").frame(width: 150, alignment: .leading)
                        head("Waits for").frame(width: 170, alignment: .leading)
                        head("Updated").frame(width: 90, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    ForEach(Array(s.treeOrder().enumerated()), id: \.offset) { _, row in
                        let id = row.id, depth = row.depth
                        if let n = s.nodes[id] {
                            let stt: DisplayStatus? = live ? s.displayStatus(id) : info?.end?[id]
                            if let stt = stt {
                                let was = base.map { $0[id] ?? .new } ?? stt
                                let waits = n.deps.filter { s.nodes[$0] != nil }.map { (s.title($0) ?? "") + (s.finished($0) ? " ✓" : "") }
                                HStack(spacing: 0) {
                                    Text(n.title).font(.system(size: 12.5, weight: n.root ? .semibold : .regular)).foregroundStyle(Color.ink).lineLimit(1)
                                        .strikethrough(stt == .crossed).padding(.leading, CGFloat(10 + depth * 18)).frame(maxWidth: .infinity, alignment: .leading).help(n.title)
                                    Text(stt.word).font(Theme.fine).foregroundStyle(Theme.status(stt)).frame(width: 90, alignment: .leading)
                                    Text(was != stt ? "\(was.word) → \(stt.word)" : "").font(Theme.fine).foregroundStyle(Color.ink2).frame(width: 150, alignment: .leading)
                                    Text(waits.isEmpty ? "—" : waits.joined(separator: ", ")).font(Theme.fine).foregroundStyle(waits.isEmpty ? Color.ink3 : .ink2).lineLimit(1).frame(width: 170, alignment: .leading).help(waits.joined(separator: ", "))
                                    Text(Format.updatedWord(n.updated, now: s.W)).font(Theme.fine).foregroundStyle(Color.ink2).frame(width: 90, alignment: .leading)
                                }
                                .padding(.vertical, 5)
                                .background(s.selected == id ? Color.doing.opacity(0.12) : was != stt ? Color.done.opacity(0.08) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { s.selected = id }
                                Rectangle().fill(Color.line).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private func head(_ t: String) -> some View { Label2(t) }
}

/// Chips in a row that wraps, as the page's inline chips do.
struct Flow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > w { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            maxW = max(maxW, x - spacing)
        }
        return CGSize(width: w == .infinity ? maxW : w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > bounds.width { x = 0; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
