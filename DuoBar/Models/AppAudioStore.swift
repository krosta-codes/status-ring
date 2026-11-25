import AppKit
import CoreAudio
import Foundation
import os

enum AppAudioPermission: Equatable {
    case unknown
    case granted
    case suspectedDenied
}

struct AppAudioRow: Identifiable {
    var id: String
    var name: String
    var icon: NSImage?
    var isPlaying: Bool
    var setting: AppAudioSetting
    var owner: AppAudioOwner

    /// Equality ignores the icon on purpose: the icon belongs to the bundle ID.
    func sameContent(as other: AppAudioRow) -> Bool {
        id == other.id && name == other.name && isPlaying == other.isPlaying
            && setting == other.setting && owner == other.owner
    }
}

/// Owns discovery, the per-app settings and one `AppTapEngine` per managed app.
/// Every change (apps, settings, default output, device list, wake, handoff) runs `reconcile()`.
@available(macOS 14.2, *)
@MainActor
final class AppAudioStore: ObservableObject {
    @Published private(set) var apps: [AppAudioRow] = []
    @Published private(set) var outputs: [AudioDeviceStatus] = []
    @Published private(set) var permission: AppAudioPermission = .unknown
    @Published private(set) var handoff: HandoffState = .inactive

    /// The popover sets this; while true a 2 s safety poll refreshes discovery.
    var popoverVisible = false {
        didSet {
            guard popoverVisible != oldValue else { return }
            updatePollTimer()
        }
    }

    /// Plug-in point for T8 (make before break, handoff direction): return false for a bundle ID
    /// while TascamVolume has not yet listed it in `perAppTapped`; Status Ring then keeps its own
    /// engine for that app until it returns true. Until T8 every app may be released at once.
    var handoffReleaseReady: (String) -> Bool = { _ in true }

    private static let excludedBundleIDs: Set<String> = ["com.jurek.statusring", "com.jurek.tascamvolume"]
    private static let zeroReadsForDenied = 3
    private static let log = OSLog(subsystem: "com.jurek.statusring", category: "appAudio")

    private let service = AppAudioService()
    private let outputService = AudioOutputService()
    private let settingsStore = AppAudioSettingsStore()

    private var settings: [String: AppAudioSetting] = [:]
    private var audioApps: [AudioApp] = []
    private var engines: [String: AppTapEngine] = [:]
    /// Engine signature (target + processes) that failed to start; not retried until something real changes.
    private var failed: [String: String] = [:]
    /// Apps whose tap delivered only zeros while playing; no engine until their settings change or restart.
    private var denied: Set<String> = []
    private var zeroReads: [String: Int] = [:]
    private var started = false

    private struct Listener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var systemListeners: [Listener] = []
    private var deviceListeners: [String: [Listener]] = [:]

    private var tickTimer: Timer?
    private var pollTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var lastDebugSettingsRaw: NSDictionary?

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        denied = []
        failed = [:]
        zeroReads = [:]
        settings = settingsStore.load()

        service.onChange = { [weak self] list in
            self?.audioApps = list
            self?.reconcile()
        }
        service.start()
        audioApps = service.apps

        outputService.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.outputs = status.selectableOutputs
            self.reconcile()
        }
        outputService.start()

        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            addListener(on: CAQuery.system, selector: selector, into: &systemListeners) { [weak self] in
                self?.reconcile()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildAll() }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadSettingsIfChanged() }
        }

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        updatePollTimer()
        reconcile()
    }

    func stop() {
        guard started else { return }
        started = false
        tickTimer?.invalidate(); tickTimer = nil
        pollTimer?.invalidate(); pollTimer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        wakeObserver = nil
        defaultsObserver = nil
        for l in systemListeners { remove(l) }
        systemListeners = []
        for list in deviceListeners.values { for l in list { remove(l) } }
        deviceListeners = [:]
        service.onChange = nil
        service.stop()
        outputService.onStatusChange = nil
        for engine in engines.values { engine.stop() }
        engines = [:]
    }

    // MARK: Public API

    func setVolume(_ v: Double, for bundleID: String) {
        var s = settings[bundleID] ?? AppAudioSetting()
        s.volume = AppAudioSetting.clamp(v)
        write(s, for: bundleID)
    }

    func setMuted(_ m: Bool, for bundleID: String) {
        var s = settings[bundleID] ?? AppAudioSetting()
        s.muted = m
        write(s, for: bundleID)
    }

    /// `nil` = follow the default output.
    func setOutput(_ uid: String?, for bundleID: String) {
        var s = settings[bundleID] ?? AppAudioSetting()
        s.outputUID = uid
        write(s, for: bundleID)
    }

    func reset(_ bundleID: String) {
        settings.removeValue(forKey: bundleID)
        settingsStore.remove(bundleID)
        settingChanged(bundleID)
        reconcile()
    }

    /// Single input for the handoff state (T8's TascamHandoffMonitor calls this).
    func updateHandoff(_ state: HandoffState) {
        guard state != handoff else { return }
        handoff = state
        reconcile()
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Settings

    private func write(_ s: AppAudioSetting, for bundleID: String) {
        if s.isDefault { settings.removeValue(forKey: bundleID) } else { settings[bundleID] = s }
        settingsStore.set(s, for: bundleID)
        settingChanged(bundleID)
        reconcile()
    }

    private func settingChanged(_ bundleID: String) {
        denied.remove(bundleID)
        failed.removeValue(forKey: bundleID)
        zeroReads.removeValue(forKey: bundleID)
    }

    private func reloadSettingsIfChanged() {
        guard started else { return }
        let fresh = settingsStore.load()
        guard fresh != settings else { return }
        for key in Set(fresh.keys).union(settings.keys) where fresh[key] != settings[key] { settingChanged(key) }
        settings = fresh
        reconcile()
    }

    // MARK: Reconcile

    private func defaultOutputUID() -> String? {
        let id = CAQuery.defaultOutput
        guard id != kAudioObjectUnknown else { return nil }
        return CAQuery.string(id, kAudioDevicePropertyDeviceUID)
    }

    private func deviceObject(uid: String) -> AudioObjectID? {
        CAQuery.objects(CAQuery.system, kAudioHardwarePropertyDevices).first {
            CAQuery.string($0, kAudioDevicePropertyDeviceUID) == uid
        }
    }

    private func reconcile() {
        guard started else { return }
        let defaultUID = defaultOutputUID()
        var rows: [AppAudioRow] = []
        var seen = Set<String>()

        for app in audioApps where !Self.excludedBundleIDs.contains(app.bundleID) {
            seen.insert(app.bundleID)
            let setting = settings[app.bundleID]
            let owner: AppAudioOwner
            if let defaultUID {
                owner = AppAudioOwnership.owner(
                    setting: setting, defaultOutputUID: defaultUID,
                    deviceExists: { self.deviceObject(uid: $0) != nil }, handoff: handoff)
            } else {
                owner = .untouched
            }
            if app.isPlaying || setting != nil {
                rows.append(AppAudioRow(id: app.bundleID, name: app.name, icon: app.icon,
                                        isPlaying: app.isPlaying, setting: setting ?? AppAudioSetting(),
                                        owner: owner))
            }
            applyEngine(for: app, owner: owner, setting: setting)
        }

        // Apps that left the process list: drop their engines.
        for bundleID in engines.keys where !seen.contains(bundleID) { dropEngine(bundleID) }

        rows.sort {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let unchanged = rows.count == apps.count && zip(rows, apps).allSatisfy { $0.sameContent(as: $1) }
        if !unchanged { apps = rows }

        syncDeviceListeners()
    }

    private func applyEngine(for app: AudioApp, owner: AppAudioOwner, setting: AppAudioSetting?) {
        let id = app.bundleID
        switch owner {
        case .statusRing(let target):
            guard !app.processObjects.isEmpty, !denied.contains(id) else { dropEngine(id); return }
            let procs = Set(app.processObjects)
            if let engine = engines[id], engine.targetUID == target, Set(engine.processObjects) == procs {
                apply(setting, to: engine)
                return
            }
            let signature = "\(target)|\(app.processObjects.sorted())"
            if failed[id] == signature { return }
            // Make before break: start the new engine, then stop the old one.
            let fresh = AppTapEngine(bundleID: id, processObjects: app.processObjects, targetUID: target)
            apply(setting, to: fresh)
            do {
                try fresh.start()
                failed.removeValue(forKey: id)
                engines[id]?.stop()
                engines[id] = fresh
            } catch {
                failed[id] = signature
                os_log("engine start failed for %{public}@: %{public}@", log: Self.log, type: .error,
                       id, String(describing: error))
                if engines[id]?.targetUID != target { dropEngine(id) }
            }
        case .tascam:
            // T8 plugs in here: keep our engine until TascamVolume reports the app in perAppTapped.
            if engines[id] != nil, !handoffReleaseReady(id) { return }
            dropEngine(id)
        case .untouched:
            dropEngine(id)
        }
    }

    private func apply(_ setting: AppAudioSetting?, to engine: AppTapEngine) {
        engine.gain = Float(setting?.volume ?? 1)
        engine.muted = setting?.muted ?? false
    }

    private func dropEngine(_ bundleID: String) {
        engines[bundleID]?.stop()
        engines.removeValue(forKey: bundleID)
        zeroReads.removeValue(forKey: bundleID)
    }

    private func rebuildAll() {
        guard started else { return }
        for engine in engines.values { engine.stop() }
        engines = [:]
        failed = [:]
        reconcile()
    }

    private func rebuildDevice(uid: String) {
        guard started else { return }
        for (id, engine) in engines where engine.targetUID == uid {
            engine.stop()
            engines.removeValue(forKey: id)
            failed.removeValue(forKey: id)
        }
        reconcile()
    }

    // MARK: Core Audio listeners

    private func addListener(on object: AudioObjectID, selector: AudioObjectPropertySelector,
                             into list: inout [Listener], handler: @escaping @MainActor () -> Void) {
        var address = CAQuery.address(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return }
        list.append(Listener(object: object, address: address, block: block))
    }

    private func remove(_ l: Listener) {
        var address = l.address
        AudioObjectRemovePropertyListenerBlock(l.object, &address, .main, l.block)
    }

    private func syncDeviceListeners() {
        let inUse = Set(engines.values.map(\.targetUID))
        for uid in deviceListeners.keys where !inUse.contains(uid) {
            for l in deviceListeners[uid] ?? [] { remove(l) }
            deviceListeners.removeValue(forKey: uid)
        }
        for uid in inUse where deviceListeners[uid] == nil {
            guard let device = deviceObject(uid: uid) else { continue }
            var list: [Listener] = []
            for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
                addListener(on: device, selector: selector, into: &list) { [weak self] in
                    self?.rebuildDevice(uid: uid)
                }
            }
            deviceListeners[uid] = list
        }
    }

    // MARK: Timers

    private func updatePollTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard started, popoverVisible else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.service.refresh() }
        }
    }

    private func tick() {
        guard started else { return }
        let debug = UserDefaults.standard.bool(forKey: PreferenceKeys.appAudioDebug)
        if debug {
            // `defaults write` from outside does not reliably fire didChangeNotification.
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
            let raw = UserDefaults.standard.dictionary(forKey: PreferenceKeys.appAudio) as NSDictionary?
            if raw != lastDebugSettingsRaw {
                lastDebugSettingsRaw = raw
                reloadSettingsIfChanged()
            }
        }
        if debug {
            let line = "taps=\(engines.count) handoff=\(handoff.active ? "active" : "inactive") "
                + "device=\(handoff.deviceUID ?? "none")"
            os_log("%{public}@", log: Self.log, type: .default, line)
        }
        guard !engines.isEmpty else { return }

        var deniedNow: [String] = []
        for (id, engine) in engines {
            let p = engine.peaks   // reading resets, so once per tick
            let playing = audioApps.first { $0.bundleID == id }?.isPlaying ?? false
            if p.input > 0 {
                zeroReads[id] = 0
                if permission != .granted { permission = .granted }
            } else if playing && permission != .granted {
                // Once a tap has delivered audio, permission is proven: zeros are just silence
                // (a paused video can keep IsRunningOutput on), so never drop the engine for them.
                let n = (zeroReads[id] ?? 0) + 1
                zeroReads[id] = n
                if n >= Self.zeroReadsForDenied { deniedNow.append(id) }
            } else {
                zeroReads[id] = 0
            }
            if debug {
                let ratio = p.input < 0.001 ? "n/a" : String(format: "%.2f", p.output / p.input)
                let line = "\(id) target=\(engine.targetUID) gain=\(String(format: "%.3f", engine.gain)) "
                    + "muted=\(engine.muted ? 1 : 0) in=\(String(format: "%.3f", p.input)) "
                    + "out=\(String(format: "%.3f", p.output)) ratio=\(ratio)"
                os_log("%{public}@", log: Self.log, type: .default, line)
            }
        }
        for id in deniedNow {
            denied.insert(id)
            permission = .suspectedDenied
            dropEngine(id)
        }
        if !deniedNow.isEmpty { syncDeviceListeners() }
    }
}
