import AppKit
import Foundation

/// Pure decoding of the TascamVolume handoff keys, kept free of AppKit state so tests can call it.
enum TascamHandoffDecoding {
    static let domain = "com.jurek.tascamvolume"
    static let bundleID = "com.jurek.tascamvolume"
    static let notificationName = "com.jurek.tascamvolume.stateChanged"

    /// Lenient Bool: `defaults write` can store Bool, Int or String.
    static func bool(_ value: Any?) -> Bool {
        switch value {
        case let v as Bool: return v
        case let v as Int: return v != 0
        case let v as NSNumber: return v.boolValue
        case let v as String:
            return ["1", "true", "yes"].contains(v.trimmingCharacters(in: .whitespaces).lowercased())
        default: return false
        }
    }

    /// Active only while TascamVolume runs, announces the handoff and its engine runs.
    static func state(running: Bool, handoff: Any?, engineRunning: Any?, deviceUID: Any?) -> HandoffState {
        var uid = deviceUID as? String
        if uid?.isEmpty == true { uid = nil }
        guard running, bool(handoff), bool(engineRunning) else { return .inactive }
        return HandoffState(active: true, deviceUID: uid)
    }

    static func tapped(_ value: Any?) -> Set<String> {
        Set((value as? [Any] ?? []).compactMap { $0 as? String })
    }
}

/// Reads TascamVolume's published handoff state (its own defaults domain) and reports changes.
@available(macOS 14.2, *)
@MainActor
final class TascamHandoffMonitor {
    /// Called on the main actor whenever the handoff state or the tapped set changed.
    var onChange: ((HandoffState, Set<String>) -> Void)?
    private(set) var state: HandoffState = .inactive
    private(set) var tapped: Set<String> = []

    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var distributedObserver: NSObjectProtocol?
    private var watchdog: Timer?
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        let center = NSWorkspace.shared.notificationCenter
        for (name, store) in [(NSWorkspace.didLaunchApplicationNotification, true),
                              (NSWorkspace.didTerminateApplicationNotification, false)] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == TascamHandoffDecoding.bundleID else { return }
                MainActor.assumeIsolated { self?.refresh(terminating: !store) }
            }
            if store { launchObserver = token } else { terminateObserver = token }
        }
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(TascamHandoffDecoding.notificationName), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                // The notification can arrive before the defaults write is visible; read once more.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
        }
        refresh()
        // A crash or kill -9 of TascamVolume posts nothing, and a LaunchAgent-started binary may not
        // fire didTerminate: while the handoff is active, re-check once per second so Status Ring
        // takes the app back within the 2 s of AC7.
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.active else { return }
                self.refresh()
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        watchdog?.invalidate()
        watchdog = nil
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        if let terminateObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver) }
        if let distributedObserver { DistributedNotificationCenter.default().removeObserver(distributedObserver) }
        launchObserver = nil
        terminateObserver = nil
        distributedObserver = nil
        state = .inactive
        tapped = []
        onChange = nil
    }

    /// Re-reads everything. `terminating` ignores a still-listed process on its way out.
    func refresh(terminating: Bool = false) {
        guard running else { return }
        let domain = TascamHandoffDecoding.domain
        CFPreferencesAppSynchronize(domain as CFString)
        let defaults = UserDefaults(suiteName: domain)
        let isRunning = !terminating && !NSRunningApplication
            .runningApplications(withBundleIdentifier: TascamHandoffDecoding.bundleID).isEmpty
        let newState = TascamHandoffDecoding.state(
            running: isRunning,
            handoff: defaults?.object(forKey: "perAppHandoff"),
            engineRunning: defaults?.object(forKey: "perAppEngineRunning"),
            deviceUID: defaults?.object(forKey: "perAppDeviceUID"))
        let newTapped = TascamHandoffDecoding.tapped(defaults?.object(forKey: "perAppTapped"))
        guard newState != state || newTapped != tapped else { return }
        state = newState
        tapped = newTapped
        onChange?(newState, newTapped)
    }
}
