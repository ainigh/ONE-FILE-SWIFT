import MPMCore
import SwiftUI

/// The cover (screen-b.js coverModel): the request screen, time's up, the last reminder, the check-up.
/// Drawn on every screen; nothing underneath is reachable until B presses what it asks for.
struct CoverView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let _ = app.frame
        let s = app.session
        ZStack {
            Color.clear
            if let m = s.coverModel() {
                VStack(spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(m.heading).font(Theme.display(34)).foregroundStyle(Color.ink)
                        Spacer()
                        if let d = m.digits { Text(d).font(Theme.mono(34)).foregroundStyle(Theme.color(m.tone)) }
                    }
                    if !m.line.isEmpty { Text(m.line).font(.system(size: 17)).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true) }
                    if let q = m.question { Text(q).font(.system(size: 20, weight: .medium)).foregroundStyle(Color.ink) }
                    HStack(spacing: 12) {
                        ForEach(Array(m.buttons.enumerated()), id: \.offset) { _, b in
                            if let a = b.action {
                                Button(b.label) { s.performScreen(a) }
                                    .buttonStyle(MPMButtonStyle(kind: b.style == .primary ? .primary : .plain, big: true))
                            } else {
                                Text(b.label).font(.system(size: 13)).foregroundStyle(Color.ink3)
                            }
                        }
                        Spacer()
                        if m.ask {
                            Button("Ask to move on") { s.raise(.strategy) }
                                .buttonStyle(LinkishStyle())
                                .disabled(s.openReq != nil)
                        }
                    }
                    if let meta = m.meta { Text(meta).font(Theme.fine).foregroundStyle(Color.ink3) }
                    if m.kind == .waiting || m.kind == .checkup || m.kind == .ended {
                        HStack(spacing: 14) {
                            Text("Space does the one thing this screen asks for.").font(Theme.fine).foregroundStyle(Color.ink3)
                            Spacer()
                            Button("Open A") { app.setRole(.a); Windows.shared.showMain() }.buttonStyle(LinkishStyle())
                            Button("Admin") { app.setRole(.admin); Windows.shared.showMain() }.buttonStyle(LinkishStyle())
                        }
                    }
                }
                .padding(28)
                .frame(width: 560)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.surface))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.color(m.tone).opacity(0.6), lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

/// The band (render.js): during the movement break, along the top of the screen.
struct BandView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let _ = app.frame
        let s = app.session
        HStack(spacing: 16) {
            Label2("Break", color: .white.opacity(0.9))
            Text("Stand up and move").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            Text(Format.digits(s.left())).font(Theme.mono(15)).foregroundStyle(.white)
            Spacer()
            Button("Ask to move on") { s.raise(.work) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.18)))
                .disabled(s.openReq != nil)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rest)
    }
}

/// A's notice: a request waits for a person. It floats at the top right and covers nothing.
struct ANoticeView: View {
    @EnvironmentObject var app: AppModel
    @State private var reason = ""

    var body: some View {
        let _ = app.frame
        let s = app.session
        VStack(alignment: .leading, spacing: 10) {
            if let r = s.openReq, r.verdict == nil {
                Label2("\(s.bName) asks · round \(r.round) · \(Format.stamp(r.sentAt))", color: .next)
                Text(r.label).font(Theme.display(17)).foregroundStyle(Color.ink)
                HStack(spacing: 4) {
                    Text("Policy says").foregroundStyle(Color.ink2)
                    Text(r.policy?.word ?? "").foregroundStyle(r.policy?.verdict == .approved ? Color.done : .blocked).fontWeight(.semibold)
                    if let why = r.policy?.reason, !why.isEmpty { Text("“\(why)”").foregroundStyle(Color.ink2).lineLimit(2) }
                }
                .font(Theme.body)
                TextField("Reason, shown to \(s.bName) (needed to refuse)", text: $reason)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { reason = r.policy?.verdict == .refused ? (r.policy?.reason ?? "") : "" }
                let cant = s.cannotApprove(r)
                HStack(spacing: 8) {
                    Button("Approve") { s.decide(r.id, .approved, "", by: .a) }
                        .buttonStyle(MPMButtonStyle(kind: .primary)).disabled(cant != nil)
                    Button("Refuse") { s.decide(r.id, .refused, reason.trimmingCharacters(in: .whitespaces), by: .a) }
                        .buttonStyle(MPMButtonStyle(kind: .plain)).disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                    Button("Open A") { app.setRole(.a); Windows.shared.showMain() }.buttonStyle(LinkishStyle())
                }
                Text(cant.map { "Approve is off: \($0)" } ?? "\(s.bName)'s clock keeps running while you decide.").font(Theme.fine).foregroundStyle(Color.ink3)
            } else {
                Text("Nothing to decide.").foregroundStyle(Color.ink2)
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        .background(Color.surface)
    }
}
