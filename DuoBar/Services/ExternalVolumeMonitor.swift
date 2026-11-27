import AppKit
import Foundation

/// Level of an output whose volume is controlled by another app (for example TascamVolume
/// on an interface without a hardware volume control).
struct ExternalVolume: Equatable {
    var controller: String
    var level: Double
    var muted: Bool
}

/// Contract for any app that controls an output's volume itself:
/// post the distributed notification `com.jurek.statusring.externalVolume` with userInfo
/// `controller` (its bundle ID), `deviceUID`, `level` (0...1) and `muted` (Bool) on every
/// change and when Status Ring posts `com.jurek.statusring.externalVolumeRequest`.
/// Status Ring then shows that level (menu bar dots, Volume card) while the device is the
/// default output, has no settable volume of its own and the controller is running.
@MainActor
final class ExternalVolumeMonitor {
    static let changed = Notification.Name("com.jurek.statusring.externalVolume")
    static let request = Notification.Name("com.jurek.statusring.externalVolumeRequest")

    var onChange: (() -> Void)?
    private var states: [String: ExternalVolume] = [:] {
        didSet { updateWatchdog() }
    }
    private var observer: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var watchdog: Timer?

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.changed, object: nil, queue: .main
        ) { [weak self] note in
            let info = note.userInfo
            MainActor.assumeIsolated { self?.receive(info) }
        }
        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dropStoppedControllers() }
        }
        DistributedNotificationCenter.default().postNotificationName(
            Self.request, object: nil, userInfo: nil, deliverImmediately: true)
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        if let terminateObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver) }
        watchdog?.invalidate()
        observer = nil
        terminateObserver = nil
        watchdog = nil
    }

    /// The controlled level for `deviceUID`, if its controller is still running.
    func state(for deviceUID: String?) -> ExternalVolume? {
        guard let deviceUID, let s = states[deviceUID], Self.isRunning(s.controller) else { return nil }
        return s
    }

    static func decode(_ info: [AnyHashable: Any]?) -> (uid: String, state: ExternalVolume)? {
        guard let info, let uid = info["deviceUID"] as? String, !uid.isEmpty,
              let controller = info["controller"] as? String else { return nil }
        let level: Double
        switch info["level"] {
        case let n as NSNumber: level = n.doubleValue
        case let s as String: level = Double(s) ?? 0
        default: return nil
        }
        let muted = (info["muted"] as? NSNumber)?.boolValue ?? false
        return (uid, ExternalVolume(controller: controller, level: min(1, max(0, level)), muted: muted))
    }

    private func receive(_ info: [AnyHashable: Any]?) {
        guard let (uid, state) = Self.decode(info), states[uid] != state else { return }
        states[uid] = state
        onChange?()
    }

    /// A controller killed without notice posts nothing: check only while at least one is known.
    private func updateWatchdog() {
        guard observer != nil, !states.isEmpty else {
            watchdog?.invalidate()
            watchdog = nil
            return
        }
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.dropStoppedControllers() }
        }
        timer.tolerance = 0.3
        watchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func dropStoppedControllers() {
        guard !states.isEmpty else { return }
        let before = states.count
        states = states.filter { Self.isRunning($0.value.controller) }
        if states.count != before { onChange?() }
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
