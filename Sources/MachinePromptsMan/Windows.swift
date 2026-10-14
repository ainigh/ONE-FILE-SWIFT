import AppKit
import MPMCore
import SwiftUI

// The windows: one main window with the three roles; covers over every screen for B (the last
// reminder, time's up, the check-up, every freeze, a request that is not a strip); a floating,
// non-covering notice for A when a request waits for a person; and the break band along the top.


final class Windows {
    static let shared = Windows()
    var model: AppModel!

    private var main: NSWindow?
    private var covers: [CoverWindow] = []
    private var band: NSPanel?
    private var notice: NSPanel?
    private var keyMonitor: Any?
    private var lastCoverKey = ""

    // MARK: The main window

    func showMain() {
        if main == nil { main = makeMain() }
        NSApp.activate(ignoringOtherApps: true)
        main?.makeKeyAndOrderFront(nil)
    }

    func toggleMain() {
        if let w = main, w.isVisible, w.isKeyWindow { w.orderOut(nil) } else { showMain() }
    }

    private func makeMain() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Machine Prompts Man"
        w.titlebarAppearsTransparent = true
        w.minSize = NSSize(width: 840, height: 560)
        w.isReleasedWhenClosed = false
        w.center()
        w.setFrameAutosaveName("MPM.main")
        w.backgroundColor = Theme.bg
        let host = NSHostingView(rootView: MainView().environmentObject(model))
        w.contentView = host
        installKeys()
        return w
    }

    /// The keyboard (input.js): Space does the one thing the screen asks for; the rest while no
    /// text field has the keyboard.
    private func installKeys() {
        if keyMonitor != nil { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self, let m = self.model else { return e }
            guard let w = e.window, w === self.main || self.covers.contains(where: { $0 === w }) else { return e }
            if let fr = w.firstResponder, fr is NSTextView || fr is NSTextField { return e }
            return self.handleKey(e, m) ? nil : e
        }
    }

    private func handleKey(_ e: NSEvent, _ m: AppModel) -> Bool {
        let s = m.session
        let mod = e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control)
        let k = e.charactersIgnoringModifiers ?? ""
        let sel = s.selected.flatMap { s.nodes[$0] != nil ? $0 : nil }
        let onBoard = m.role == .b && (m.boardOpen || s.bView() == .plan) && s.editBlock() == nil && s.coverModel() == nil
        if mod && (k == "z" || k == "Z") && onBoard { if e.modifierFlags.contains(.shift) { s.redo() } else { s.undo() }; return true }
        if mod && k == "," { m.openSettings(tab: .session); return true }
        if mod || e.modifierFlags.contains(.option) { return false }
        switch e.keyCode {
        case 49: m.primary(); return true                       // Space
        case 53:                                                // Escape
            if m.depFor != nil { m.depFor = nil }
            else if m.settingsOpen { m.settingsOpen = false }
            else if m.role == .a && m.aTab != nil { m.aTab = nil }
            else if s.selected != nil { s.selected = nil }
            else { return false }
            return true
        case 36: if let id = sel, onBoard { m.renaming = id; m.boardView = .map; return true }; return false   // Return
        case 51, 117: if let id = sel, onBoard { s.crossOut(id); return true }; return false              // Backspace, Delete
        default: break
        }
        switch k.lowercased() {
        case "d": if let id = sel, onBoard, s.canPick() { s.pick(.d, id); return true }
        case "n": if let id = sel, onBoard, s.canPick() { s.pick(.n, id); return true }
        case "a": if onBoard { if let nk = s.addChild(sel ?? s.goal()) { s.selected = nk; m.renaming = nk; m.boardView = .map }; return true }
        default: break
        }
        return false
    }

    // MARK: Covers, the band and A's notice: refreshed every frame

    func update() {
        guard let m = model else { return }
        let s = m.session
        updateCovers(m, s)
        updateBand(m, s)
        updateNotice(m, s)
    }

    private func updateCovers(_ m: AppModel, _ s: Session) {
        let cover = m.role == .b ? s.coverModel() : nil
        if cover == nil {
            if !covers.isEmpty { covers.forEach { $0.close() }; covers = []; lastCoverKey = "" ; NSCursor.unhide() }
            return
        }
        if covers.isEmpty || covers.count != NSScreen.screens.count {
            covers.forEach { $0.close() }
            covers = NSScreen.screens.map { screen in
                let w = CoverWindow(screen: screen)
                w.contentView = NSHostingView(rootView: CoverView().environmentObject(m))
                w.orderFrontRegardless()
                return w
            }
            NSApp.activate(ignoringOtherApps: true)
            covers.first?.makeKey()
        }
    }

    private func updateBand(_ m: AppModel, _ s: Session) {
        let show = m.role == .b && s.state == .break && s.running()
        if !show { band?.orderOut(nil); return }
        if band == nil {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.contentView = NSHostingView(rootView: BandView().environmentObject(m))
            band = p
        }
        if let b = band, let screen = NSScreen.main ?? NSScreen.screens.first {
            let v = screen.visibleFrame
            b.setFrame(NSRect(x: v.minX, y: v.maxY - 44, width: v.width, height: 44), display: true)
            if !b.isVisible { b.orderFrontRegardless() }
        }
    }

    private func updateNotice(_ m: AppModel, _ s: Session) {
        // A request waits for a person in the A role, and A's screen is not what the window shows.
        let waiting = !s.auto && s.openReq?.verdict == nil && s.openReq != nil
        let show = waiting && !(m.role == .a && (main?.isVisible ?? false))
        if !show { notice?.orderOut(nil); return }
        if notice == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 220), styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
                            backing: .buffered, defer: false)
            p.title = "A"
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isFloatingPanel = true
            p.becomesKeyOnlyIfNeeded = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.backgroundColor = Theme.surface
            p.contentView = NSHostingView(rootView: ANoticeView().environmentObject(m))
            notice = p
        }
        if let n = notice, !n.isVisible, let screen = NSScreen.main ?? NSScreen.screens.first {
            let v = screen.visibleFrame
            n.setFrameOrigin(NSPoint(x: v.maxX - n.frame.width - 16, y: v.maxY - n.frame.height - 16))
            n.orderFrontRegardless()
        }
    }
}

/// A cover over one screen: above everything, swallowing keys (Space is the one thing it asks for).
final class CoverWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.72)
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { AppModel.shared.primary() }
    }
    override func cancelOperation(_ sender: Any?) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}
