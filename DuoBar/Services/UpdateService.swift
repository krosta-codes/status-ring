import AppKit
import Combine
import Foundation

/// Update check (krosta app-standard UPDATES.md): asks the GitHub Releases of the repo once a day,
/// sends nothing else. "Update" pulls the source clone and rebuilds through update.sh; without a
/// clone it opens the release page.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    struct Release: Equatable { let tag: String; let url: URL }

    @Published private(set) var available: Release?
    @Published private(set) var statusText = ""

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private let repo = Bundle.main.object(forInfoDictionaryKey: "CSRepo") as? String ?? "krosta-codes/status-ring"
    private let sourceDir = Bundle.main.object(forInfoDictionaryKey: "CSSourceDir") as? String
    private var timer: Timer?

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "updateCheck") as? Bool ?? true }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.check(manual: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check(manual: false) }
        }
    }

    func check(manual: Bool) {
        if !manual && !isEnabled { return }
        statusText = "Checking…"
        let repo = repo, version = currentVersion
        Task.detached {
            let (release, error) = await Self.fetchLatest(repo: repo, version: version)
            await MainActor.run { self.handle(release: release, error: error, manual: manual) }
        }
    }

    private func handle(release: Release?, error: String?, manual: Bool) {
        guard let release else {
            statusText = "Check failed: \(error ?? "unknown error")"
            return
        }
        if Self.isNewer(release.tag, than: currentVersion) {
            available = release
            // Signal is the "Update to vX" button in the popover footer; no notification needed.
            statusText = "\(release.tag) is available (you have \(currentVersion))."
        } else {
            available = nil
            statusText = "Up to date (\(currentVersion))."
        }
    }

    func installUpdate() {
        guard let release = available else { return check(manual: true) }
        guard let src = sourceDir,
              FileManager.default.fileExists(atPath: "\(src)/.git"),
              FileManager.default.fileExists(atPath: "\(src)/update.sh") else {
            NSWorkspace.shared.open(release.url)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Update Status Ring to \(release.tag)?"
        alert.informativeText = "Pulls the new version into \(src), rebuilds and restarts Status Ring."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Release notes")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let logPath = NSHomeDirectory() + "/Library/Logs/StatusRing-update.log"
            if !FileManager.default.fileExists(atPath: logPath) { FileManager.default.createFile(atPath: logPath, contents: nil) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["\(src)/update.sh"]
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile(); process.standardOutput = handle; process.standardError = handle
            }
            do { try process.run(); statusText = "Updating…" } catch { statusText = "Update failed: \(error.localizedDescription)" }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.url)
        default:
            break
        }
    }

    // MARK: - Pure helpers

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    nonisolated static func parse(_ data: Data, repo: String) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let url = URL(string: json["html_url"] as? String ?? "") ?? URL(string: "https://github.com/\(repo)/releases")!
        return Release(tag: tag, url: url)
    }

    nonisolated static func fetchLatest(repo: String, version: String) async -> (Release?, String?) {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("StatusRing/\(version)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200, let release = parse(data, repo: repo) { return (release, nil) }
            if code == 404 {
                if let data = ghAPI("repos/\(repo)/releases/latest"), let release = parse(data, repo: repo) { return (release, nil) }
                return (nil, "no release published yet")
            }
            return (nil, "GitHub answered HTTP \(code)")
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// Private repo fallback: the user's own gh login. 15 s timeout.
    nonisolated static func ghAPI(_ path: String) -> Data? {
        guard let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let process = Process(), out = Pipe()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["api", path]
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) { if process.isRunning { process.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
