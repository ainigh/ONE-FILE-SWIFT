import Cocoa

// MARK: - Overlay window (one per screen)

final class OverlayWindow: NSWindow {
    let label = NSTextField(labelWithString: "")

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false,
                   screen: screen)

        level = .screenSaver                       // above everything, incl. full-screen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.85)
        hasShadow = false
        ignoresMouseEvents = false                 // swallow clicks so they don't fall through
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 220, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: screen.frame)
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content
    }

    // Allow the window to take focus so it captures key presses.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Swallow Esc, Cmd-W, Cmd-Q, arrow keys, etc.
    override func keyDown(with event: NSEvent) {}
    override func cancelOperation(_ sender: Any?) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlays: [OverlayWindow] = []
    private var timer: Timer?
    private var remaining = 0
    private let duration = 5

    private var isRunning: Bool { timer != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)      // no Dock icon, menubar only

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Countdown")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    // Refuse to quit while the countdown is running.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isRunning ? .terminateCancel : .terminateNow
    }

    // MARK: Menubar interaction

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            startCountdown()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Start Countdown", action: #selector(startCountdown), keyEquivalent: "")
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quit.isEnabled = !isRunning
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil                      // restore click-to-start behaviour
    }

    // MARK: Countdown

    @objc private func startCountdown() {
        guard !isRunning else { return }           // ignore clicks mid-countdown
        remaining = duration
        buildOverlays()
        updateLabels()

        NSApp.activate(ignoringOtherApps: true)
        overlays.first?.makeKey()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 {
            finish()
        } else {
            updateLabels()
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
    }

    private func buildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { screen in
            let w = OverlayWindow(screen: screen)
            w.orderFrontRegardless()
            return w
        }
    }

    private func updateLabels() {
        overlays.forEach { $0.label.stringValue = "\(remaining)" }
    }

    // Rebuild if a display is plugged/unplugged mid-countdown.
    @objc private func screensChanged() {
        guard isRunning else { return }
        buildOverlays()
        updateLabels()
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
