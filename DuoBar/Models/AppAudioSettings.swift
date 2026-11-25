import Foundation

/// Per-app audio setting, stored per bundle ID as a plist dictionary.
struct AppAudioSetting: Equatable {
    var volume: Double = 1
    var muted: Bool = false
    var outputUID: String?

    init(volume: Double = 1, muted: Bool = false, outputUID: String? = nil) {
        self.volume = AppAudioSetting.clamp(volume)
        self.muted = muted
        self.outputUID = outputUID
    }

    var isDefault: Bool { volume == 1 && !muted && outputUID == nil }

    static func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return 1 }
        return min(1, max(0, v))
    }

    var plist: [String: Any] {
        var d: [String: Any] = ["volume": volume, "muted": muted]
        if let outputUID { d["outputUID"] = outputUID }
        return d
    }

    /// Lenient decoding: `defaults write -dict-add` stores strings.
    init?(plist: Any) {
        guard let d = plist as? [String: Any] else { return nil }
        var volume = 1.0
        switch d["volume"] {
        case let v as Double: volume = v
        case let v as Int: volume = Double(v)
        case let v as NSNumber: volume = v.doubleValue
        case let v as String: volume = Double(v.trimmingCharacters(in: .whitespaces)) ?? 1
        default: break
        }
        var muted = false
        switch d["muted"] {
        case let v as Bool: muted = v
        case let v as Int: muted = v != 0
        case let v as NSNumber: muted = v.boolValue
        case let v as String:
            let s = v.trimmingCharacters(in: .whitespaces).lowercased()
            muted = ["1", "true", "yes"].contains(s)
        default: break
        }
        var uid = d["outputUID"] as? String
        if uid?.isEmpty == true { uid = nil }
        self.init(volume: volume, muted: muted, outputUID: uid)
    }
}

/// Reads and writes the `appAudio` dictionary in UserDefaults.
final class AppAudioSettingsStore {
    static let notificationName = "com.jurek.statusring.appAudioChanged"

    private let defaults: UserDefaults
    private let post: () -> Void

    init(defaults: UserDefaults = .standard,
         post: @escaping () -> Void = {
             DistributedNotificationCenter.default().postNotificationName(
                 Notification.Name(AppAudioSettingsStore.notificationName),
                 object: nil, userInfo: nil, deliverImmediately: true)
         }) {
        self.defaults = defaults
        self.post = post
    }

    func load() -> [String: AppAudioSetting] {
        guard let raw = defaults.dictionary(forKey: PreferenceKeys.appAudio) else { return [:] }
        var out: [String: AppAudioSetting] = [:]
        for (bundleID, value) in raw {
            if let s = AppAudioSetting(plist: value), !s.isDefault { out[bundleID] = s }
        }
        return out
    }

    /// Writes all settings (default entries are dropped), then posts the change notification.
    func save(_ settings: [String: AppAudioSetting]) {
        var raw: [String: Any] = [:]
        for (bundleID, s) in settings where !s.isDefault { raw[bundleID] = s.plist }
        defaults.set(raw, forKey: PreferenceKeys.appAudio)
        post()
    }

    func set(_ setting: AppAudioSetting, for bundleID: String) {
        var all = load()
        all[bundleID] = setting
        save(all)
    }

    func remove(_ bundleID: String) {
        var all = load()
        all.removeValue(forKey: bundleID)
        save(all)
    }
}
