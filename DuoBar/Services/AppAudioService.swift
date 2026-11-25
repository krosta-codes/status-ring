@preconcurrency import CoreAudio
import AppKit
import Foundation

/// One app (helpers merged under their responsible parent) that has audio processes.
struct AudioApp: Equatable, Identifiable {
    var bundleID: String
    var name: String
    var icon: NSImage?
    var processObjects: [AudioObjectID]
    var isPlaying: Bool
    var pid: pid_t
    var id: String { bundleID }

    static func == (l: AudioApp, r: AudioApp) -> Bool {
        l.bundleID == r.bundleID && l.name == r.name && l.processObjects == r.processObjects
            && l.isPlaying == r.isPlaying && l.pid == r.pid
    }
}

/// Discovers which apps have audio processes and whether they are playing.
///
/// Public API (main actor):
/// - `onChange: (([AudioApp]) -> Void)?`: called on the main actor whenever the grouped list changes.
/// - `apps`: the latest list.
/// - `start()` / `stop()`: register or remove all Core Audio listeners (process list on the system
///   object, `IsRunningOutput` on every process object, rebound as the list changes).
/// - `refresh()`: safety refresh; the owner calls it from a 2 s timer while the popover is open.
/// - `AppAudioService.snapshot()`: one-shot read, no listeners (nonisolated).
/// - `AppAudioService.runListAudioAppsAndExit()`: hidden launch flag `--list-audio-apps`, prints
///   `<bundleID> <process-count> <playing 0|1>` per group and exits 0. Call it before the instance lock.
@available(macOS 14.2, *)
@MainActor
final class AppAudioService {
    var onChange: (([AudioApp]) -> Void)?
    private(set) var apps: [AudioApp] = []

    private struct ListenerRegistration {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let listener: AudioObjectPropertyListenerBlock
    }

    private let listenerQueue = DispatchQueue(label: "com.jurek.statusring.appaudio-listeners", qos: .utility)
    private var systemListener: ListenerRegistration?
    private var processListeners: [AudioObjectID: ListenerRegistration] = [:]
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        var address = CAQuery.address(kAudioHardwarePropertyProcessObjectList)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        if AudioObjectAddPropertyListenerBlock(CAQuery.system, &address, listenerQueue, listener) == noErr {
            systemListener = ListenerRegistration(objectID: CAQuery.system, address: address, listener: listener)
        }
        refresh()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        if let s = systemListener { remove(s) }
        systemListener = nil
        for r in processListeners.values { remove(r) }
        processListeners.removeAll()
    }

    func refresh() {
        let objects = CAQuery.objects(CAQuery.system, kAudioHardwarePropertyProcessObjectList)
        if isStarted { rebindProcessListeners(objects) }
        let next = Self.snapshot(processObjects: objects)
        guard next != apps else { return }
        apps = next
        onChange?(next)
    }

    private func rebindProcessListeners(_ objects: [AudioObjectID]) {
        let live = Set(objects)
        for (id, reg) in processListeners where !live.contains(id) {
            remove(reg)
            processListeners[id] = nil
        }
        for id in objects where processListeners[id] == nil {
            var address = CAQuery.address(kAudioProcessPropertyIsRunningOutput)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
            guard AudioObjectAddPropertyListenerBlock(id, &address, listenerQueue, listener) == noErr else { continue }
            processListeners[id] = ListenerRegistration(objectID: id, address: address, listener: listener)
        }
    }

    private func remove(_ reg: ListenerRegistration) {
        var address = reg.address
        AudioObjectRemovePropertyListenerBlock(reg.objectID, &address, listenerQueue, reg.listener)
    }

    deinit {
        for reg in processListeners.values + (systemListener.map { [$0] } ?? []) {
            var address = reg.address
            AudioObjectRemovePropertyListenerBlock(reg.objectID, &address, listenerQueue, reg.listener)
        }
    }

    // MARK: One-shot discovery

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private nonisolated static let responsibleFn: ResponsibleFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    /// Responsible (parent) PID, or the PID itself when the private symbol is missing or fails.
    nonisolated static func responsiblePID(_ pid: pid_t) -> pid_t {
        guard let fn = responsibleFn else { return pid }
        let r = fn(pid)
        return r > 0 ? r : pid
    }

    nonisolated static func snapshot() -> [AudioApp] {
        snapshot(processObjects: CAQuery.objects(CAQuery.system, kAudioHardwarePropertyProcessObjectList))
    }

    nonisolated static func snapshot(processObjects: [AudioObjectID]) -> [AudioApp] {
        let infos: [AudioProcessInfo] = processObjects.compactMap { obj in
            guard let pid: pid_t = CAQuery.value(obj, kAudioProcessPropertyPID, initial: pid_t(0)), pid > 0 else { return nil }
            let running: UInt32 = CAQuery.value(obj, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) ?? 0
            return AudioProcessInfo(pid: pid, bundleID: CAQuery.string(obj, kAudioProcessPropertyBundleID).flatMap { $0.isEmpty ? nil : $0 },
                                    isPlaying: running != 0, objectID: obj)
        }
        let groups = AppAudioGrouping.group(
            processes: infos,
            responsible: responsiblePID,
            ownPID: ProcessInfo.processInfo.processIdentifier,
            bundleIDForPID: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        )
        return groups.compactMap { g in
            guard let bundleID = g.bundleID else { return nil }
            let app = NSRunningApplication(processIdentifier: g.parentPID)
            return AudioApp(bundleID: bundleID, name: app?.localizedName ?? bundleID, icon: app?.icon,
                            processObjects: g.objectIDs, isPlaying: g.isPlaying, pid: g.parentPID)
        }
    }

    /// One line per group: `<bundleID> <process-count> <playing 0|1>`.
    nonisolated static func listAudioAppsLines() -> [String] {
        snapshot().map { "\($0.bundleID) \($0.processObjects.count) \($0.isPlaying ? 1 : 0)" }
    }

    /// Hidden launch flag `--list-audio-apps`: print the lines and exit 0.
    nonisolated static func runListAudioAppsAndExit() -> Never {
        for line in listAudioAppsLines() { print(line) }
        fflush(stdout)
        exit(0)
    }
}
