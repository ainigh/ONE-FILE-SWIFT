import Cocoa
import Foundation

// MARK: - Updater

/// Keeps the installed app on the newest commit of the branch it was built from (`main`, unless
/// install.sh was given another): checks at launch, every 6 hours, and from the menu; installs on
/// request. Installing takes GitHub's prebuilt release when it was made from that exact commit;
/// otherwise it downloads the source and builds it here with Apple's command line tools, so an
/// update never has to wait for GitHub Actions. The repository is public, so plain HTTPS is enough.
final class Updater {
    static let repo = "ainigh/ONE-FILE-SWIFT"
    static let appName = "MachinePromptsMan.app"
    static let assetName = "MachinePromptsMan.zip"
    static let checkInterval: TimeInterval = 6 * 3600

    struct Commit: Equatable {
        let sha: String
        let title: String
        var short: String { String(sha.prefix(7)) }
    }

    struct Release: Equatable {
        let tag: String
        let target: String?
        let assetURL: URL?
    }

    enum Plan: Equatable {
        case upToDate
        case prebuilt(Commit, Release)             // GitHub built this commit: download it
        case buildHere(Commit)                     // no release for it yet: build on this Mac
    }

    enum State {
        case idle, checking, upToDate
        case available(Plan)
        case installing(String)
        case failed(String)
    }

    struct Problem: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    // MARK: What this copy is (make-app.sh writes these into Info.plist)

    static var branch: String {
        let b = Bundle.main.object(forInfoDictionaryKey: "MPMBranch") as? String ?? ""
        return b.isEmpty ? "main" : b
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var currentCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "MPMCommit") as? String
    }

    /// A bare binary (`make build`, or swiftc by hand) isn't an installed app: don't update it.
    static var isInstalledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var versionLine: String {
        let commit = currentCommit.map { " (\($0.prefix(7)))" } ?? ""
        let branch = Self.branch == "main" ? "" : " · \(Self.branch)"
        return "Machine Prompts Man \(currentVersion)\(commit)\(branch)"
    }

    // MARK: State

    private(set) var state: State = .idle {
        didSet { onChange?(state) }
    }
    /// Called on the main thread whenever `state` changes.
    var onChange: ((State) -> Void)?
    private var timer: Timer?
    private let work = DispatchQueue(label: "com.ainigh.MachinePromptsMan.updater", qos: .utility)

    var isBusy: Bool {
        switch state {
        case .checking, .installing: return true
        default: return false
        }
    }

    func start() {
        guard Self.isInstalledApp else { return }
        check(userInitiated: false)
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
    }

    func check(userInitiated: Bool) {
        if isBusy { return }
        let before = state
        state = .checking
        work.async {
            let outcome: State
            do {
                let plan = try Self.findUpdate()
                outcome = plan == .upToDate ? .upToDate : .available(plan)
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            DispatchQueue.main.async {
                // A quiet background check that fails shouldn't leave an error in the menu, and
                // an update it already found stays offered.
                if case .failed = outcome, !userInitiated {
                    if case .available = before { self.state = before } else { self.state = .idle }
                } else {
                    self.state = outcome
                }
            }
        }
    }

    func install() {
        guard case .available(let plan) = state else { return }
        state = .installing("Updating…")
        work.async {
            do {
                try Self.install(plan) { step in
                    DispatchQueue.main.async { self.state = .installing(step) }
                }
            } catch {
                Self.log("update failed: \(error.localizedDescription)")
                DispatchQueue.main.async { self.state = .failed("Update failed: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: What's new

    static func findUpdate() throws -> Plan {
        let head = try fetchHead()
        let release = try? fetchRelease(for: head)
        return decide(head: head, installedCommit: currentCommit, latestRelease: release)
    }

    /// Compares the branch's newest commit with the one this copy was built from. A copy with no
    /// recorded commit (built by hand) updates to whatever the branch has.
    static func decide(head: Commit, installedCommit: String?, latestRelease: Release?) -> Plan {
        if let mine = installedCommit, !mine.isEmpty, mine != "unknown",
           head.sha.hasPrefix(mine) || mine.hasPrefix(head.sha) {
            return .upToDate
        }
        if let release = latestRelease, release.target == head.sha, release.assetURL != nil {
            return .prebuilt(head, release)
        }
        return .buildHere(head)
    }

    static func fetchHead() throws -> Commit {
        do {
            return try fetchHead(of: branch)
        } catch let p as Problem where branch != "main" && (p.errorDescription ?? "").hasPrefix("GitHub can't find") {
            // The branch this copy was installed from is gone (merged and deleted): follow main.
            log("branch \(branch) is gone; following main")
            return try fetchHead(of: "main")
        }
    }

    static func fetchHead(of branch: String) throws -> Commit {
        let json = try api("repos/\(repo)/commits/\(branch)")
        guard let sha = json["sha"] as? String,
              let details = json["commit"] as? [String: Any],
              let message = details["message"] as? String else {
            throw Problem("GitHub's answer for \(branch) had no commit in it")
        }
        return Commit(sha: sha, title: message.components(separatedBy: "\n").first ?? message)
    }

    /// The release GitHub made from this commit, if any; else the newest one (which `decide`
    /// then passes over, since its commit differs).
    static func fetchRelease(for head: Commit) throws -> Release {
        let list = try apiList("repos/\(repo)/releases?per_page=10")
        let releases = list.compactMap(release)
        guard let first = releases.first else { throw Problem("no release") }
        return releases.first { $0.target == head.sha } ?? first
    }

    static func release(_ json: [String: Any]) -> Release? {
        guard let tag = json["tag_name"] as? String else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let asset = assets.first { ($0["name"] as? String) == assetName }
        let url = (asset?["browser_download_url"] as? String).flatMap(URL.init(string:))
        return Release(tag: tag, target: json["target_commitish"] as? String, assetURL: url)
    }

    // MARK: Installing

    static func install(_ plan: Plan, step: @escaping (String) -> Void) throws {
        let fm = FileManager.default
        let app = Bundle.main.bundleURL
        guard isInstalledApp else { throw Problem("this copy isn't an app bundle") }
        // On the app's own volume, so the swap at the end is a rename.
        let scratch = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: app, create: true)
        defer { try? fm.removeItem(at: scratch) }

        let newApp: URL
        let commit: Commit
        switch plan {
        case .upToDate:
            return
        case let .prebuilt(head, release):
            commit = head
            step("Downloading \(release.tag)…")
            newApp = try downloadPrebuilt(release, into: scratch)
        case let .buildHere(head):
            commit = head
            newApp = try buildFromSource(head, in: scratch, step: step)
        }

        let newBundle = Bundle(url: newApp)
        guard let newID = newBundle?.bundleIdentifier, newID == Bundle.main.bundleIdentifier else {
            throw Problem("the new copy isn't \(app.lastPathComponent)")
        }
        // Never swap in something that isn't the commit we meant to install, or whose bundle was
        // damaged on the way (a truncated download, a half-finished build).
        guard newBundle?.object(forInfoDictionaryKey: "MPMCommit") as? String == commit.sha else {
            throw Problem("the new copy wasn't built from \(commit.short)")
        }
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
        } catch {
            throw Problem("the new copy's signature doesn't check out: \(error.localizedDescription)")
        }
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        // A build takes minutes: a session may have opened meanwhile. Never swap the bundle under a
        // running session, and tell the app the quit that follows is ours.
        var sessionRunning = false
        DispatchQueue.main.sync {
            sessionRunning = AppModel.shared.session.state != nil
            if !sessionRunning { AppModel.shared.quittingForUpdate = true }
        }
        if sessionRunning { throw Problem("a session is running: end it, then update again") }
        step("Restarting…")
        _ = try fm.replaceItemAt(app, withItemAt: newApp)
        log("updated to \(commit.short)")
        // Start the new copy once this one has quit.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                              app.path]
        try relaunch.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    static func downloadPrebuilt(_ release: Release, into scratch: URL) throws -> URL {
        guard let url = release.assetURL else { throw Problem("the release has no \(assetName)") }
        let zip = scratch.appendingPathComponent(assetName)
        try download(url, to: zip)
        let unpacked = scratch.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        return unpacked.appendingPathComponent(appName)
    }

    /// Downloads the commit's source and runs scripts/make-app.sh on it (for this Mac only).
    static func buildFromSource(_ commit: Commit, in scratch: URL, step: (String) -> Void) throws -> URL {
        guard (try? run("/usr/bin/xcode-select", ["-p"])) != nil else {
            throw Problem("building needs Apple's command line tools: run xcode-select --install in Terminal")
        }
        step("Downloading \(commit.short)…")
        let tarball = scratch.appendingPathComponent("source.tar.gz")
        guard let url = URL(string: "https://codeload.github.com/\(repo)/tar.gz/\(commit.sha)") else {
            throw Problem("bad source URL")
        }
        try download(url, to: tarball)
        let src = scratch.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try run("/usr/bin/tar", ["-xzf", tarball.path, "-C", src.path, "--strip-components", "1"])

        step("Building \(commit.short)…")
        log("building \(commit.short) in \(src.path)")
        let base = currentVersion.split(separator: "-").first.map(String.init) ?? "1.0"
        var env = ["VERSION": "\(base)-\(commit.short)", "COMMIT": commit.sha, "BRANCH": branch]
        if let identity = UserDefaults.standard.string(forKey: "signIdentity"), !identity.isEmpty {
            env["SIGN_IDENTITY"] = identity
        }
        try run("/bin/bash", [src.appendingPathComponent("scripts/make-app.sh").path],
                env: env, in: src, logOutput: true)
        return src.appendingPathComponent("build").appendingPathComponent(appName)
    }

    /// The error, plus the end of update.log when a build failed, for pasting somewhere.
    static func report(_ problem: String) -> String {
        guard let log = try? String(contentsOf: logURL, encoding: .utf8) else { return problem }
        let tail = log.components(separatedBy: "\n").suffix(60).joined(separator: "\n")
        return problem + "\n\n--- the end of \(logURL.path) ---\n" + tail
    }

    // MARK: GitHub

    /// GET https://api.github.com/<path>, as JSON.
    static func api(_ path: String) throws -> [String: Any] {
        guard let json = try apiJSON(path) as? [String: Any] else { throw Problem("GitHub's answer wasn't JSON") }
        return json
    }

    static func apiList(_ path: String) throws -> [[String: Any]] {
        guard let json = try apiJSON(path) as? [[String: Any]] else { throw Problem("GitHub's answer wasn't a list") }
        return json
    }

    static func apiJSON(_ path: String) throws -> Any {
        guard let url = URL(string: "https://api.github.com/\(path)") else { throw Problem("bad path \(path)") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MachinePromptsMan/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try fetch(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw Problem("GitHub can't find \(path)") }
        if status == 403 || status == 429 { throw Problem("GitHub's hourly limit: try again later") }
        guard status == 200 else { throw Problem("GitHub answered \(status)") }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func download(_ url: URL, to file: URL) throws {
        let (data, response) = try fetch(URLRequest(url: url))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Problem("download failed (GitHub answered \(status)): \(url)") }
        try data.write(to: file)
    }

    static func fetch(_ request: URLRequest) throws -> (Data, URLResponse) {
        final class Box { var result: Result<(Data, URLResponse), Error> = .failure(Problem("no answer")) }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data, let response = response {
                box.result = .success((data, response))
            } else {
                box.result = .failure(error ?? Problem("no answer"))
            }
            done.signal()
        }.resume()
        done.wait()
        return try box.result.get()
    }

    // MARK: Helpers

    /// ~/Library/Logs/MachinePromptsMan/update.log: what updates did, and a build's full output.
    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MachinePromptsMan/update.log")
    }

    static func log(_ line: String) {
        let url = logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }

    /// Runs a program and returns its output. Throws with the last line of its errors if it fails.
    /// `logOutput` also copies everything it printed into update.log.
    @discardableResult
    static func run(_ tool: String, _ args: [String], env extra: [String: String] = [:],
                    in dir: URL? = nil, logOutput: Bool = false) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        if let dir = dir { process.currentDirectoryURL = dir }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env.merge(extra) { $1 }
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Read stderr on another thread while stdout is read here, so a full pipe can't stall it.
        final class Box { var data = Data() }
        let errBox = Box()
        let errRead = DispatchGroup()
        errRead.enter()
        DispatchQueue.global().async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            errRead.leave()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errRead.wait()
        let errData = errBox.data
        let name = (tool as NSString).lastPathComponent
        if logOutput {
            log("\(name) \(args.joined(separator: " "))\n\(String(decoding: data, as: UTF8.self))\(String(decoding: errData, as: UTF8.self))")
        }
        if process.terminationStatus != 0 {
            let lines = String(decoding: errData.isEmpty ? data : errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            let message = logOutput ? (lines.last(where: { $0.contains("error") }) ?? lines.last ?? "") : (lines.last ?? "")
            let tail = message.isEmpty ? "\(name) failed (\(process.terminationStatus))" : message
            throw Problem(logOutput ? "\(tail) (details in \(logURL.path))" : tail)
        }
        return data
    }
}
