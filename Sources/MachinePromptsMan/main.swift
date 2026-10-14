import Cocoa
import MPMCore
import ServiceManagement
import SwiftUI

// Machine Prompts Man: a work clock for macOS. The spec is docs/ (app.html and docs/js); the
// engine is MPMCore; this is the Mac around it: a menubar item with the ring, one window with
// the three roles, covers over every screen for B, a floating notice for A, the break band, the
// voice, the sounds, and the updater.

// MARK: - Launch arguments

enum Launch {
    static let usage = """
    Machine Prompts Man — a work clock for macOS. Work in rounds, rest by the numbers.

    usage: MachinePromptsMan [-speed N]

      -speed N      run the clocks N times faster (1 to 120), for trying it out
      -h, --help    show this help
      --version     print the version and commit this copy was built from
    """

    static var speed: Double {
        let v = UserDefaults.standard.double(forKey: "speed")
        return v >= 1 && v <= 120 ? v : 1
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let model = AppModel.shared
    private let windows = Windows.shared
    private let updater = Updater()
    private var loop: Timer?
    private var lastFrame: Date?
    private var lastStatus = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)      // no Dock icon, menubar only

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = StatusRing.image(fraction: 0, tone: .ink2, running: false)
            button.imagePosition = .imageLeading
            button.toolTip = "Machine Prompts Man — click for the window, right-click for the menu"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        model.updater = updater
        updater.onChange = { [weak self] _ in self?.refreshStatus(force: true) }
        updater.start()
        model.start()
        windows.model = model
        windows.showMain()

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)

        // The clock: ten frames a second; a long gap (the Mac slept) is stepped through in order.
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.frame() }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        loop = t
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.willQuit()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Quitting mid-session would leave the clocks nowhere: the menu asks to end it first.
        model.session.state == nil ? .terminateNow : .terminateCancel
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc private func didWake(_ note: Notification) { frame() }

    private func frame() {
        let now = Date()
        let real = lastFrame.map { now.timeIntervalSince($0) } ?? 0
        lastFrame = now
        model.frame(real: max(0, real))
        windows.update()
        refreshStatus(force: false)
    }

    // MARK: The menubar item

    private func refreshStatus(force: Bool) {
        let s = model.session
        let running = s.running()
        let digits = running ? Format.digits(s.left()) : s.frozen ? Format.digits(s.reading) : ""
        let len = s.phaseLen()
        let fraction = running && len > 0 ? 1 - s.left() / len : (s.frozen ? 1 : 0)
        let tone = s.state == nil ? Tone.ink2 : s.tone()
        let key = "\(digits)|\(Int(fraction * 60))|\(tone)|\(running)|\(model.updateAvailable)"
        if !force && key == lastStatus { return }
        lastStatus = key
        guard let button = statusItem.button else { return }
        button.image = StatusRing.image(fraction: fraction, tone: tone, running: running || s.frozen)
        button.title = digits.isEmpty ? "" : " " + digits
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.appearsDisabled = false
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { windows.toggleMain() }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let s = model.session
        func add(_ title: String, _ action: Selector?, key: String = "", enabled: Bool = true, state: Bool = false) -> NSMenuItem {
            let i = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            i.target = self
            i.isEnabled = enabled
            i.state = state ? .on : .off
            return i
        }
        let head = add(s.state == nil ? "No session" : "\(s.state!.title)\(s.frozen ? " ended" : "")" + (s.round > 0 ? " · round \(s.round)" : "") + (s.running() ? " · \(Format.digits(s.left())) left" : s.frozen ? " · waiting for Go" : ""), nil, enabled: false)
        head.isEnabled = false
        menu.addItem(.separator())
        _ = add("Open Window", #selector(openWindow), key: "")
        _ = add("End Session", #selector(endSession), enabled: s.canEnd())
        _ = add("Session Transcript…", #selector(saveTranscript), enabled: !s.events.isEmpty)
        _ = add("System Monitor", #selector(openMonitor))
        menu.addItem(.separator())
        _ = add("Test Mode (60×)", #selector(toggleTest), state: model.testMode)
        _ = add("Mute Sounds", #selector(toggleMute), state: model.muted)
        _ = add("Spoken Confirmations", #selector(toggleVoice), state: model.voiceOn)
        _ = add("Open at Login", #selector(toggleLogin), state: LoginItem.isOn)
        menu.addItem(.separator())
        _ = add("Schedule…", #selector(openSchedule))
        _ = add("Settings…", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addUpdateItems(menu)
        menu.addItem(.separator())
        _ = add(s.state == nil ? "Quit Machine Prompts Man" : "Quit (end the session first)", #selector(quit), key: "q", enabled: s.state == nil)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func addUpdateItems(_ menu: NSMenu) {
        let version = menu.addItem(withTitle: Updater.versionLine, action: nil, keyEquivalent: "")
        version.isEnabled = false
        guard Updater.isInstalledApp else { return }
        func item(_ title: String, _ action: Selector?, enabled: Bool = true) {
            let i = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            i.target = self
            i.isEnabled = enabled
        }
        switch updater.state {
        case .idle, .upToDate: item("Check for Updates…", #selector(checkForUpdates))
        case .checking: item("Checking for Updates…", nil, enabled: false)
        case .available(let plan):
            let title: String
            switch plan {
            case let .prebuilt(commit, release): title = "Update to \(release.tag) — \(commit.title)"
            case let .buildHere(commit): title = "Update (build here) — \(commit.short): \(commit.title)"
            case .upToDate: title = "Check for Updates…"
            }
            item(title, #selector(installUpdate), enabled: model.session.state == nil)
        case .installing(let step): item(step, nil, enabled: false)
        case .failed(let message):
            item(message, nil, enabled: false)
            item("Copy Update Details", #selector(copyUpdateDetails))
            item("Check for Updates…", #selector(checkForUpdates))
        }
    }

    @objc private func openWindow() { windows.showMain() }
    @objc private func endSession() { model.askToEnd() }
    @objc private func saveTranscript() { model.saveTranscript() }
    @objc private func openMonitor() { model.role = .admin; model.adTab = .monitor; windows.showMain() }
    @objc private func toggleTest() { model.setTestMode(!model.testMode) }
    @objc private func toggleMute() { model.setMuted(!model.muted) }
    @objc private func toggleVoice() { model.setVoiceOn(!model.voiceOn) }
    @objc private func toggleLogin() { LoginItem.toggle() }
    @objc private func openSchedule() { model.openSettings(tab: .schedule); windows.showMain() }
    @objc private func openSettings() { model.openSettings(tab: .session); windows.showMain() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() { updater.check(userInitiated: true) }
    @objc private func installUpdate() { if model.session.state == nil { updater.install() } }
    @objc private func copyUpdateDetails() {
        guard case .failed(let message) = updater.state else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Updater.report(message), forType: .string)
    }
}

// MARK: - The ring in the menubar

enum StatusRing {
    static func image(fraction: Double, tone: Tone, running: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY), r = 6.5
            let track = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            track.lineWidth = 2
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            track.stroke()
            if running && fraction > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - 360 * CGFloat(min(1, max(0, fraction))), clockwise: true)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                Theme.nsColor(tone).setStroke()
                arc.stroke()
            } else if !running {
                let hand = NSBezierPath()
                hand.move(to: NSPoint(x: c.x, y: c.y + 4))
                hand.line(to: c)
                hand.line(to: NSPoint(x: c.x + 3, y: c.y - 1.5))
                hand.lineWidth = 1.6
                hand.lineCapStyle = .round
                NSColor.labelColor.setStroke()
                hand.stroke()
            }
            return true
        }
        img.isTemplate = !running
        return img
    }
}

// MARK: - Open at login

enum LoginItem {
    static var isOn: Bool {
        if #available(macOS 13, *) { return SMAppServiceShim.isOn } else { return false }
    }
    static func toggle() {
        if #available(macOS 13, *) { SMAppServiceShim.toggle() }
    }
}

@available(macOS 13, *)
enum SMAppServiceShim {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    static func toggle() {
        do {
            if isOn { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            Updater.log("open at login: \(error.localizedDescription)")
        }
    }
}

// MARK: - Entry point

let args = CommandLine.arguments.dropFirst()
if args.contains("-h") || args.contains("--help") {
    print(Launch.usage)
    exit(0)
}
if args.contains("--version") {
    print(Updater.versionLine)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
