import MPMCore
import SwiftUI

/// The window: the header with the three roles, one role's screen, B's foot, the toast and the settings sheet.
struct MainView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let _ = app.frame
        VStack(spacing: 0) {
            HeaderView()
            Rectangle().fill(Color.line).frame(height: 1)
            ZStack(alignment: .bottom) {
                Group {
                    switch app.role {
                    case .b: BScreen()
                    case .a: AScreen()
                    case .admin: AdminScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let t = app.toast {
                    Text(t.text)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.error ? Color.stop : Color.doing))
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }
            }
            if app.role == .b {
                Rectangle().fill(Color.line).frame(height: 1)
                BFootView()
            }
        }
        .background(Color.bg)
        .sheet(isPresented: $app.settingsOpen) { SettingsView().environmentObject(app) }
    }
}

struct HeaderView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        let waiting = s.openReq != nil && s.openReq?.verdict == nil
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "clock").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.doing)
                Text("Machine Prompts Man").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
            }
            .frame(width: 230, alignment: .leading)
            Spacer()
            Seg(items: [(AppRole.b, "B · Work"), (.a, "A · Requests"), (.admin, "Admin")],
                selection: Binding(get: { app.role }, set: { app.setRole($0) }),
                badge: waiting ? .a : nil)
            Spacer()
            HStack(spacing: 10) {
                if app.updateAvailable {
                    Button { app.openSettings(tab: .general) } label: { Label("Update", systemImage: "arrow.down.circle") }
                        .buttonStyle(LinkishStyle())
                }
                Button { app.openSettings(tab: .session) } label: {
                    Label("Settings", systemImage: "gearshape").font(.system(size: 12))
                }
                .buttonStyle(MPMButtonStyle(kind: .small))
                .help("Settings (⌘,)")
            }
            .frame(width: 230, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 30).padding(.bottom, 10)
        .background(Color.chrome)
    }
}

/// B's foot (chrome.js): seated minutes, the voice style, End session.
struct BFootView: View {
    @EnvironmentObject var app: AppModel
    @State private var seat = ""

    var body: some View {
        let s = app.session
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Text("Already seated").font(Theme.fine).foregroundStyle(Color.ink2)
                TextField("0", text: $seat)
                    .textFieldStyle(.roundedBorder).frame(width: 52).font(Theme.mono(12))
                    .disabled(s.state != nil)
                    .onAppear { seat = String(Int(s.seatStart / 60)) }
                    .onSubmit { s.setSeatStart(minutes: Double(seat) ?? 0); seat = String(Int(s.seatStart / 60)) }
                Text("min").font(Theme.fine).foregroundStyle(Color.ink2)
                Text(s.state != nil ? "Set before a session opens." : "Counts toward the sitting limit when the session opens.").font(Theme.fine).foregroundStyle(Color.ink3)
            }
            Spacer()
            HStack(spacing: 8) {
                Text("Voice").font(Theme.fine).foregroundStyle(Color.ink2)
                Seg(items: [(VoiceStyle.rich, "Rich"), (.varied, "Varied"), (.fixed, "Fixed")],
                    selection: Binding(get: { s.voice }, set: { s.setVoice($0) }))
                    .help("Rich: a different sentence now and then, and often a second on what the numbers mean. Varied: one sentence at a time. Fixed: the spec's wording, word for word.")
            }
            Button("End session") { app.askToEnd() }
                .buttonStyle(LinkishStyle())
                .disabled(!s.canEnd())
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.chrome)
    }
}
