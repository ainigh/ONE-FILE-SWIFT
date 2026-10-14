import AppKit
import Foundation

// The folder the user picked for the files the app writes, kept as a bookmark across launches.
// Picking it through the open panel is what lets a user-chosen folder be written; one under
// Desktop, Documents or Downloads still gets macOS's question the first time it's touched (the
// usage descriptions in Info.plist are what that question shows). The microphone's permission is
// asked by Listener (Voice.swift).

enum OutputFolder {
    private static let bookmarkKey = "outputFolderBookmark"
    private static let askedKey = "outputFolderAsked"
    private static let defaults = UserDefaults.standard

    /// The user was asked once already (and may have cancelled): don't ask at every countdown.
    static var askedOnce: Bool { defaults.bool(forKey: askedKey) }

    /// The chosen folder, if one was chosen and it's still there.
    static func current() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        let url = (try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))
        guard let url = url else { return nil }
        if stale, let fresh = bookmark(url) { defaults.set(fresh, forKey: bookmarkKey) }
        return url
    }

    /// Asks for a folder (on the main thread; the app comes forward so the panel is seen).
    @discardableResult
    static func choose() -> URL? {
        defaults.set(true, forKey: askedKey)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where Machine Prompts Man saves what it says and hears."
        panel.prompt = "Use This Folder"
        if let url = current() { panel.directoryURL = url }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if let data = bookmark(url) {
            defaults.set(data, forKey: bookmarkKey)
        } else {
            Updater.log("couldn't keep a bookmark for \(url.path)")
        }
        return url
    }

    static func forget() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    /// A security-scoped bookmark where the system gives one, else a plain one (this app isn't
    /// sandboxed, so the plain one is enough to find the folder again).
    private static func bookmark(_ url: URL) -> Data? {
        (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    struct NoFolder: LocalizedError {
        var errorDescription: String? {
            "no output folder chosen (right-click the menubar icon → Choose Output Folder…)"
        }
    }

    /// Writes `text` to a new, dated file in the folder: countdown-2026-10-14T15-42-07.txt.
    @discardableResult
    static func write(_ text: String, kind: String, at date: Date = Date()) throws -> URL {
        guard let folder = current() else { throw NoFolder() }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        let url = folder.appendingPathComponent("\(kind)-\(stamp(date)).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return f.string(from: date)
    }
}
