import MPMCore
import SwiftUI

/// A's screen (screen-a.js): the clock in a box at the top, who answers at the top left, every
/// request as a box in a grid at the centre; the table, the grid and the log open in a drawer.
struct AScreen: View {
    @EnvironmentObject var app: AppModel
    @State private var aname = ""

    var body: some View {
        let s = app.session
        let st = s.state
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Who answers").font(Theme.fine).foregroundStyle(Color.ink2)
                    Seg(items: [(true, "Policy"), (false, "You")], selection: Binding(get: { s.auto }, set: { if $0 != s.auto { s.setAuto($0); app.saveSettings() } }))
                        .help("Policy: the policy table answers every request at once. You: requests wait here for you.")
                    TextField("Your name (optional)", text: $aname)
                        .textFieldStyle(.roundedBorder).frame(width: 170)
                        .onAppear { aname = s.names.a }
                        .onSubmit { s.setName(.a, aname); aname = s.names.a; s.logEvent(.man, .a, .info, s.names.a.isEmpty ? "A's name cleared" : "A's name: \(s.names.a)", "used wherever the screens speak of A") }
                }
                Spacer()
                VStack(spacing: 4) {
                    Label2(st.map { $0.title + (s.frozen ? " ended" : "") + (s.round > 0 ? " · round \(s.round)" : "") } ?? "No session yet")
                    Text(s.running() ? Format.digits(s.left()) : s.frozen ? Format.digits(s.reading) : "—")
                        .font(Theme.mono(40)).foregroundStyle(st == .work && s.running() && s.left() <= 60 ? Color.stop : Theme.color(s.tone()))
                    Text(st != nil ? "\(s.title(s.pairNow().d) ?? "—") doing · \(s.title(s.pairNow().n) ?? "—") next · seated \(Format.seatedMin(s.seated))" : "\(s.bName) is on the intake screen")
                        .font(Theme.fine).foregroundStyle(Color.ink2)
                    if s.running(), let strip = s.strip, s.mono() < strip.until { Text(strip.text).font(Theme.fine).foregroundStyle(Theme.color(s.tone())) }
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.color(s.tone()).opacity(0.5)))
                Spacer()
                HStack(spacing: 2) {
                    ForEach([(ATab.table, "Table", "Every request this session"), (.grid, "Grid", "\(s.bName)'s plan, read only"), (.log, "Log", "Every event")], id: \.0) { t in
                        Button(t.1) { app.aTab = app.aTab == t.0 ? nil : t.0 }
                            .buttonStyle(MPMButtonStyle(kind: app.aTab == t.0 ? .smallPrimary : .small)).help(t.2)
                    }
                }
            }
            .padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ABoxes()
                    ANotes()
                }
                .padding(.horizontal, 16)
            }
            if let tab = app.aTab {
                Rectangle().fill(Color.line).frame(height: 1)
                HStack {
                    Text(tab == .table ? "Every request this session. You approve or refuse; you never start or stop a clock." : tab == .grid ? "\(s.bName)'s plan, read only, round by round" : "Every event, newest first")
                        .font(Theme.fine).foregroundStyle(Color.ink3)
                    Spacer()
                    Button("Hide ‹") { app.aTab = nil }.buttonStyle(LinkishStyle())
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Group {
                    switch tab {
                    case .table: RequestTable()
                    case .grid: GridTable(forA: true)
                    case .log: LogView()
                    }
                }
                .frame(height: 300)
            }
        }
    }
}

/// Every request is a box; the newest four are full, older ones fade, past 16 they go.
struct ABoxes: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        let r = s.openReq
        let waiting = r != nil && r?.verdict == nil
        let h = s.held
        let brief = s.state == .strategy && h != nil && (h!.brief != nil || h!.failed)
        let list = Array(s.requests.filter { $0.sessionId == s.sessionId }.reversed().prefix(16))
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            if brief, let hh = h { BriefBox(held: hh) }
            if list.isEmpty && !brief { EmptyBox() }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, x in
                Group {
                    if waiting && x.id == r?.id { LiveBox(request: x) } else { PastBox(request: x) }
                }
                .opacity(i >= 4 ? max(0.35, 1 - Double(i - 3) * 0.12) : 1)
            }
        }
    }
}

struct ABox<Content: View>: View {
    var tone: Color
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tone.opacity(0.7), lineWidth: 1.2))
    }
}

/// The live request: the policy's default beside it, Approve, and Refuse with a reason.
struct LiveBox: View {
    @EnvironmentObject var app: AppModel
    let request: Request

    var body: some View {
        let s = app.session
        let r = request
        let cant = s.cannotApprove(r)
        ABox(tone: .next) {
            Label2("\(s.bName) asks" + (r.round > 0 ? " · round \(r.round)" : "") + " · sent \(Format.stamp(r.sentAt))")
            Text(r.label).font(Theme.display(16)).foregroundStyle(Color.ink)
            HStack(spacing: 4) {
                Text("Policy says").foregroundStyle(Color.ink2)
                Text(r.policy?.word ?? "").fontWeight(.semibold).foregroundStyle(r.policy?.verdict == .approved ? Color.done : .blocked)
                if let why = r.policy?.reason, !why.isEmpty { Text(": “\(why)”").foregroundStyle(Color.ink2) }
            }.font(Theme.body)
            TextField("Reason, shown to \(s.bName) (needed to refuse)", text: $app.reason)
                .textFieldStyle(.roundedBorder)
                .onAppear { if app.reasonFor != r.id { app.reasonFor = r.id; app.reason = r.policy?.verdict == .refused ? (r.policy?.reason ?? "") : "" } }
            HStack(spacing: 8) {
                Button("Approve") { s.decide(r.id, .approved, "", by: .a) }.buttonStyle(MPMButtonStyle(kind: .primary)).disabled(cant != nil).help(cant ?? "")
                Button("Refuse") { s.decide(r.id, .refused, app.reason.trimmingCharacters(in: .whitespaces), by: .a) }.buttonStyle(MPMButtonStyle(kind: .plain)).disabled(app.reason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(cant.map { "Approve is off: \($0)" } ?? "\(s.bName)'s clock keeps running while you decide.").font(Theme.fine).foregroundStyle(Color.ink3)
        }
    }
}

/// A decided or closed request: what was asked, what was answered, and where it stands.
struct PastBox: View {
    @EnvironmentObject var app: AppModel
    let request: Request

    var body: some View {
        let s = app.session
        let x = request
        let open = x.outcome == nil, sys = x.raisedBy == .system
        let tone: Color = x.verdict == .approved ? .done : x.verdict == .refused ? .blocked : .ink3
        ABox(tone: tone) {
            Label2((sys ? (open ? "System · frozen" : "System") : "\(s.bName) asked") + (x.round > 0 ? " · round \(x.round)" : "") + " · \(x.id)")
            Text(x.label).font(Theme.display(15)).foregroundStyle(Color.ink)
            HStack(spacing: 4) {
                if let v = x.verdict {
                    Text(v == .approved ? "Approved" : "Refused").fontWeight(.semibold).foregroundStyle(v == .approved ? Color.done : .blocked)
                    Text("by " + (x.decidedBy == .a ? "you" : "policy") + (x.decidedBy == .a && x.verdict != x.policy?.verdict ? ", against the policy" : "") + (x.reason.isEmpty ? "" : ": “\(x.reason)”")).foregroundStyle(Color.ink2)
                } else {
                    Text("Waiting").fontWeight(.semibold).foregroundStyle(Color.ink2)
                }
            }.font(Theme.body)
            Text(status(s, x, open: open, sys: sys)).font(Theme.fine).foregroundStyle(Color.ink3)
        }
    }

    private func status(_ s: Session, _ x: Request, open: Bool, sys: Bool) -> String {
        if open { return sys ? "The clock stopped. Nothing runs until \(s.bName) presses Go." : "Waiting for \(s.bName) to press " + (x.verdict == .approved ? "Go." : "OK.") }
        if x.outcome == .accepted { return s.bName + (sys ? " pressed Go after " : " went after ") + Format.fmt(x.bTook ?? 0) + "." }
        if x.outcome == .acknowledged { return "\(s.bName) pressed OK." }
        return "Overtaken: the clock ran out first."
    }
}

struct BriefBox: View {
    @EnvironmentObject var app: AppModel
    let held: Held
    var body: some View {
        ABox(tone: .next) {
            Label2("From the assistant, for \(app.session.aName)")
            Text(held.brief?.text ?? "No brief this round: the model did not answer in time.").font(Theme.body).foregroundStyle(Color.ink)
            Text(held.brief?.forA ?? "The session goes on as usual.").font(Theme.fine).foregroundStyle(Color.ink3)
        }
    }
}

struct EmptyBox: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        let s = app.session
        ABox(tone: .line) {
            Text(s.state != nil ? "Nothing to decide" : "No session yet").font(Theme.display(15)).foregroundStyle(Color.ink)
            Text(s.state == nil ? "\(s.bName) is on the intake screen. The first request lands here when \(s.bName) presses OK."
                 : s.auto ? "The policy answers every request at once. Switch “Who answers” to You to decide them yourself."
                 : "When \(s.bName) presses Next phase, Snooze or asks to end, the request lands here with the policy's default beside it.")
                .font(Theme.fine).foregroundStyle(Color.ink3)
        }
    }
}

/// B's doings, as notes that fade: five seconds each, newest at the bottom.
struct ANotes: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        let s = app.session
        let now = s.mono()
        VStack(alignment: .leading, spacing: 4) {
            ForEach(s.liveNotes()) { n in
                HStack(spacing: 8) {
                    Label2(s.bName, color: n.warn ? .blocked : .ink3)
                    Text(n.text).font(Theme.fine).foregroundStyle(n.warn ? Color.blocked : Color.ink2).lineLimit(1)
                }
                .opacity(now - n.at > Session.noteMs - 700 ? 0.3 : 1)
            }
        }
    }
}

/// The full table of requests, in the drawer.
struct RequestTable: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        let s = app.session
        let list = s.requests.filter { $0.sessionId == s.sessionId }.reversed()
        let over = list.filter { $0.decidedBy == .a && $0.verdict != $0.policy?.verdict }.count
        let frz = list.filter { $0.raisedBy == .system }.compactMap(\.bTook).reduce(0, +)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Every request this session, newest first").font(Theme.fine).foregroundStyle(Color.ink2)
                Spacer()
                Text("\(Format.n(list.count, "request", "requests")) · \(Format.n(over, "override", "overrides")) · frozen \(Format.fmt(frz))").font(Theme.fine).foregroundStyle(Color.ink3)
            }
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        cell("#", 36); cell("Round", 50); cell("Asked", nil); cell("By", 60); cell("Policy", 60); cell("Verdict", 120); cell("A took", 70); cell("B took", 90); cell("Outcome", 90)
                    }.padding(.vertical, 4)
                    if list.isEmpty {
                        Text("No requests yet. Every phase change is one: \(s.bName) asks, or the System raises one when a clock runs out.").font(Theme.fine).foregroundStyle(Color.ink3).padding(8)
                    }
                    ForEach(list) { x in
                        HStack(spacing: 0) {
                            tcell(x.id, 36, mono: true); tcell("\(x.round)", 50, mono: true); tcell(x.label, nil)
                            tcell(x.raisedBy == .system ? "System" : s.bName, 60)
                            tcell(x.policy?.word ?? "", 60, color: x.policy?.verdict == .approved ? .done : .blocked)
                            tcell((x.verdict?.rawValue ?? "waiting") + (x.decidedBy == .a ? " by \(s.aName)" : "") + (x.decidedBy == .a && x.verdict != x.policy?.verdict ? " ≠ policy" : ""), 120, color: x.verdict == .approved ? .done : x.verdict == .refused ? .blocked : .ink2)
                            tcell(x.aTook.map(Format.fmt) ?? "…", 70, mono: true)
                            tcell(x.bTook.map { (x.raisedBy == .system ? "freeze " : "") + Format.fmt($0) } ?? "", 90, mono: true)
                            tcell(x.outcome?.rawValue ?? "open", 90, color: x.outcome == .overtaken ? .blocked : .ink2)
                        }
                        .padding(.vertical, 4)
                        Rectangle().fill(Color.line).frame(height: 1)
                    }
                }
            }
        }
        .padding(14)
    }

    private func cell(_ t: String, _ w: CGFloat?) -> some View {
        Label2(t).frame(width: w, alignment: .leading).frame(maxWidth: w == nil ? .infinity : nil, alignment: .leading)
    }
    private func tcell(_ t: String, _ w: CGFloat?, mono: Bool = false, color: Color = .ink) -> some View {
        Text(t).font(mono ? Theme.mono(11) : Theme.fine).foregroundStyle(color).lineLimit(1)
            .frame(width: w, alignment: .leading).frame(maxWidth: w == nil ? .infinity : nil, alignment: .leading)
    }
}
