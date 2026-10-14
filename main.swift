import Cocoa

// MARK: - Configuration

/// Resolves the countdown length. Precedence: `-duration N` launch argument
/// (read via UserDefaults' argument domain, so it can also be persisted with
/// `defaults write <bundle id> duration -int 10`), then `COUNTDOWN_SECONDS`
/// env var, then the built-in default. Out-of-range values fall back to the
/// default so a typo can never lock the screen for hours.
enum Config {
    static let defaultDuration = 5
    static let minDuration = 1
    static let maxDuration = 3600

    static var duration: Int {
        var value = defaultDuration
        if let env = ProcessInfo.processInfo.environment["COUNTDOWN_SECONDS"],
           let parsed = Int(env.trimmingCharacters(in: .whitespaces)) {
            value = parsed
        }
        if UserDefaults.standard.object(forKey: "duration") != nil {
            value = UserDefaults.standard.integer(forKey: "duration")
        }
        return (minDuration...maxDuration).contains(value) ? value : defaultDuration
    }

    static let usage = """
    CountdownOverlay — menubar countdown that covers every screen.

    usage: CountdownOverlay [-duration SECONDS]

      -duration N   countdown length, \(minDuration)...\(maxDuration) (default \(defaultDuration))
      -h, --help    show this help

    COUNTDOWN_SECONDS=N in the environment is used when -duration is absent.
    """
}

// MARK: - Overlay window (one per screen)

final class OverlayWindow: NSWindow {
    private let label = NSTextField(labelWithString: "")

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
        animationBehavior = .none                  // appear instantly, no fade
        isMovable = false

        // Scale the digits with the screen so they fit on small displays
        // and stay legible on large ones.
        let shortSide = min(screen.frame.width, screen.frame.height)
        let fontSize = min(max(shortSide * 0.28, 72), 320)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityLabel("Countdown")

        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content
    }

    func setRemaining(_ seconds: Int) {
        let text = "\(seconds)"
        if label.stringValue != text {
            label.stringValue = text
        }
    }

    // Allow the window to take focus so it captures key presses.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Swallow Esc, Cmd-W, Cmd-Q, arrow keys, etc.
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func flagsChanged(with event: NSEvent) {}
    override func cancelOperation(_ sender: Any?) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }

    // Swallow mouse interaction on the overlay itself.
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlays: [OverlayWindow] = []
    private var timer: Timer?
    private var deadline: Date?
    private var keyMonitor: Any?
    private var rebuildWork: DispatchWorkItem?
    private var previousApp: NSRunningApplication?
    private var lastShown = -1
    private let duration = Config.duration

    private var isRunning: Bool { deadline != nil }

    /// Whole seconds left, rounded up so "5" shows for the first full second.
    private var remainingSeconds: Int {
        guard let deadline = deadline else { return 0 }
        return max(0, Int(ceil(deadline.timeIntervalSinceNow)))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)      // no Dock icon, menubar only

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Countdown") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "⏱"                 // fallback if SF Symbols are unavailable
            }
            button.toolTip = "Countdown Overlay (\(duration)s) — click to start, right-click for menu"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(screensChanged),
                           name: NSApplication.didChangeScreenParametersNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(appDidResignActive(_:)),
                           name: NSApplication.didResignActiveNotification,
                           object: nil)

        // After sleep/wake the deadline may already have passed; resync at once.
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(workspaceDidWake(_:)),
                                                          name: NSWorkspace.didWakeNotification,
                                                          object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardown()
    }

    // Refuse to quit while the countdown is running.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isRunning ? .terminateCancel : .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

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
        menu.autoenablesItems = false              // honour the isEnabled flags below

        let title = menu.addItem(withTitle: isRunning
                                    ? "Counting down… \(remainingSeconds)s"
                                    : "Countdown length: \(duration)s",
                                 action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(.separator())

        let start = menu.addItem(withTitle: "Start Countdown",
                                 action: #selector(startCountdown), keyEquivalent: "")
        start.target = self
        start.isEnabled = !isRunning

        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        quit.isEnabled = !isRunning

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil                      // restore click-to-start behaviour
    }

    // MARK: Countdown

    @objc private func startCountdown() {
        guard !isRunning else { return }           // ignore clicks mid-countdown

        previousApp = NSWorkspace.shared.frontmostApplication
        deadline = Date().addingTimeInterval(TimeInterval(duration))
        lastShown = -1
        statusItem.button?.appearsDisabled = true
        NSCursor.hide()

        buildOverlays()
        updateLabels()
        regainFocus()

        // Swallow every key event delivered to this process, regardless of
        // which window is key, so Cmd-Q etc. never reach the responder chain.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { _ in nil }

        // Tick often and derive the display from the deadline, so the count
        // never drifts and recovers correctly after the machine sleeps.
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func workspaceDidWake(_ note: Notification) {
        tick()                                     // finish at once if the deadline passed
        if isRunning { regainFocus() }
    }
    @objc private func appDidResignActive(_ note: Notification) { regainFocus() }

    private func tick() {
        guard isRunning else { return }
        if remainingSeconds <= 0 {
            finish()
        } else {
            updateLabels()
        }
    }

    private func finish() {
        teardown()

        // Give focus back to whatever the user was using before we took over.
        if let app = previousApp, !app.isTerminated, app != NSRunningApplication.current {
            app.activate(options: [])
        }
        previousApp = nil
    }

    /// Stops the timer and removes all overlays. Safe to call repeatedly.
    private func teardown() {
        timer?.invalidate()
        timer = nil
        deadline = nil
        rebuildWork?.cancel()
        rebuildWork = nil
        NSCursor.unhide()                          // never leave the cursor hidden
        statusItem?.button?.appearsDisabled = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        closeOverlays()
    }

    private func closeOverlays() {
        overlays.forEach { $0.close() }
        overlays.removeAll()
    }

    private func buildOverlays() {
        closeOverlays()
        overlays = NSScreen.screens.map { screen in
            let w = OverlayWindow(screen: screen)
            w.orderFrontRegardless()
            return w
        }
    }

    private func updateLabels() {
        let value = remainingSeconds
        guard value != lastShown else { return }
        lastShown = value
        overlays.forEach { $0.setRemaining(value) }
    }

    /// Keeps the overlay key and the app active for as long as the countdown
    /// runs, so key events keep landing in our swallowing handlers.
    private func regainFocus() {
        guard isRunning else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.overlays.forEach { $0.orderFrontRegardless() }
            self.overlays.first?.makeKey()
        }
    }

    // Rebuild if a display is plugged/unplugged or resized mid-countdown. These
    // notifications arrive in bursts, so coalesce them.
    @objc private func screensChanged() {
        guard isRunning else { return }
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.lastShown = -1
            self.buildOverlays()
            self.updateLabels()
            self.regainFocus()
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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
