import Cocoa

// MARK: - Configuration

enum Config {
    static let defaultDuration = 5
    static let maxDuration = 3600

    /// Countdown length in seconds. Read from the `duration` default, so it can be set
    /// on the command line (`./CountdownOverlay -duration 10`) or persisted with
    /// `defaults write <bundle id> duration -int 10`. Out-of-range values fall back
    /// to the default so a typo can never lock the screen for hours.
    static var duration: Int {
        let v = UserDefaults.standard.integer(forKey: "duration")
        return (1...maxDuration).contains(v) ? v : defaultDuration
    }

    static let usage = """
    CountdownOverlay — menubar countdown that covers every screen.

    usage: CountdownOverlay [-duration SECONDS]

      -duration N   countdown length, 1...\(maxDuration) (default \(defaultDuration))
      -h, --help    show this help
    """
}

// MARK: - Overlay window (one per screen)

final class OverlayWindow: NSWindow {
    let label = NSTextField(labelWithString: "")

    init(screen: NSScreen) {
        // Use the global-coordinate initializer: the `screen:` variant interprets
        // contentRect relative to that screen, which misplaces secondary displays.
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        setFrame(screen.frame, display: false)

        level = .screenSaver                       // above everything, incl. full-screen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.85)
        hasShadow = false
        ignoresMouseEvents = false                 // swallow clicks so they don't fall through
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        isMovable = false

        // Scale the digits to the screen so they fit on small displays too.
        let fontSize = min(260, max(80, screen.frame.height * 0.3))
        label.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
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

    // Swallow Esc, Cmd-W, Cmd-Q, arrow keys, etc. (belt and braces; the app-wide
    // event monitor in AppDelegate is the primary guard).
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func cancelOperation(_ sender: Any?) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlays: [OverlayWindow] = []
    private var timer: Timer?
    private var deadline: Date?
    private var shownValue = -1
    private var keyMonitor: Any?
    private var rebuildWork: DispatchWorkItem?

    private var isRunning: Bool { deadline != nil }

    /// Whole seconds left, computed from the wall-clock deadline so the count
    /// stays correct through timer coalescing, heavy load and system sleep.
    private var remaining: Int {
        guard let deadline = deadline else { return 0 }
        return max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)      // no Dock icon, menubar only

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Countdown") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "⏱"                 // pre-macOS 11 fallback (no SF Symbols)
            }
            button.toolTip = "Click to start a \(Config.duration)-second countdown"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)

        // After sleep the timer may not fire for a while; re-evaluate immediately.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil)
    }

    // Refuse to quit while the countdown is running.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isRunning ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        finish()                                   // never leave the cursor hidden
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // If something steals focus mid-countdown (e.g. Cmd-Tab), take it back so
    // key presses keep landing on the overlay instead of another app.
    func applicationDidResignActive(_ notification: Notification) {
        guard isRunning else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.bringOverlaysForward()
        }
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
        let start = menu.addItem(withTitle: "Start Countdown (\(Config.duration)s)",
                                 action: #selector(startCountdown),
                                 keyEquivalent: "")
        start.target = self
        start.isEnabled = !isRunning
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quit.isEnabled = !isRunning

        // Attach the menu only for the duration of this click; performClick tracks
        // the menu synchronously, so it is safe to detach right after.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil                      // restore click-to-start behaviour
    }

    // MARK: Countdown

    @objc private func startCountdown() {
        guard !isRunning else { return }           // ignore clicks mid-countdown
        deadline = Date().addingTimeInterval(TimeInterval(Config.duration))
        shownValue = -1
        statusItem.button?.appearsDisabled = true

        buildOverlays()
        bringOverlaysForward()
        updateLabels()
        installKeyMonitor()
        NSCursor.hide()

        // Tick often and derive the value from the deadline rather than counting
        // ticks, so the display cannot drift or skip.
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard isRunning else { return }
        if remaining <= 0 {
            finish()
        } else {
            updateLabels()
        }
    }

    private func finish() {
        guard isRunning else { return }
        deadline = nil
        timer?.invalidate()
        timer = nil
        rebuildWork?.cancel()
        rebuildWork = nil
        removeKeyMonitor()
        NSCursor.unhide()
        statusItem.button?.appearsDisabled = false
        tearDownOverlays()
    }

    private func buildOverlays() {
        tearDownOverlays()
        overlays = NSScreen.screens.map { screen in
            let w = OverlayWindow(screen: screen)
            w.orderFrontRegardless()
            return w
        }
    }

    private func tearDownOverlays() {
        overlays.forEach { $0.close() }
        overlays.removeAll()
    }

    private func bringOverlaysForward() {
        NSApp.activate(ignoringOtherApps: true)
        overlays.forEach { $0.orderFrontRegardless() }
        overlays.first?.makeKey()
    }

    private func updateLabels() {
        let value = remaining
        guard value != shownValue else { return }  // avoid redundant redraws
        shownValue = value
        overlays.forEach { $0.label.stringValue = "\(value)" }
    }

    // Swallow every key event app-wide while running. This does not depend on
    // which window is key and needs no accessibility permission.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { _ in
            nil
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    // MARK: System events

    // Rebuild if a display is plugged/unplugged or resized mid-countdown. These
    // notifications arrive in bursts, so coalesce them.
    @objc private func screensChanged() {
        guard isRunning else { return }
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.shownValue = -1
            self.buildOverlays()
            self.bringOverlaysForward()
            self.updateLabels()
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    @objc private func systemDidWake() {
        guard isRunning else { return }
        tick()                                     // finish at once if the deadline passed
        if isRunning { bringOverlaysForward() }
    }
}

// MARK: - Entry point

let args = CommandLine.arguments.dropFirst()
if args.contains("-h") || args.contains("--help") {
    print(Config.usage)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
