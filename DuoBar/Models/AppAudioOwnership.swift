import Foundation

/// State of the TascamVolume handoff (see plan, "Handoff").
struct HandoffState: Equatable {
    var active: Bool
    var deviceUID: String?

    static let inactive = HandoffState(active: false, deviceUID: nil)
}

enum AppAudioOwner: Equatable {
    case untouched
    case statusRing(targetUID: String)
    case tascam
}

enum AppAudioOwnership {
    static func owner(setting: AppAudioSetting?,
                      defaultOutputUID: String,
                      deviceExists: (String) -> Bool,
                      handoff: HandoffState) -> AppAudioOwner {
        guard let setting, !setting.isDefault else { return .untouched }
        var target = defaultOutputUID
        if let uid = setting.outputUID, deviceExists(uid) { target = uid }
        if handoff.active, let hUID = handoff.deviceUID, target == hUID, setting.outputUID == nil {
            return .tascam
        }
        return .statusRing(targetUID: target)
    }
}
