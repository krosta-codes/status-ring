import CoreAudio
import Foundation

struct AudioProcessInfo: Equatable {
    var pid: pid_t
    var bundleID: String?
    var isPlaying: Bool
    var objectID: AudioObjectID
}

struct AppGroup: Equatable {
    var parentPID: pid_t
    var bundleID: String?
    var objectIDs: [AudioObjectID]
    var isPlaying: Bool
}

enum AppAudioGrouping {
    static let tascamBundleID = "com.jurek.tascamvolume"

    /// Groups audio processes under their responsible (parent) app.
    /// `bundleIDForPID` resolves the parent's bundle ID; when it returns nil the
    /// first member's own bundle ID is used.
    static func group(processes: [AudioProcessInfo],
                      responsible: (pid_t) -> pid_t,
                      ownPID: pid_t,
                      bundleIDForPID: (pid_t) -> String? = { _ in nil }) -> [AppGroup] {
        var order: [pid_t] = []
        var groups: [pid_t: AppGroup] = [:]
        for p in processes {
            if p.pid == ownPID || p.bundleID == tascamBundleID { continue }
            let parent = responsible(p.pid)
            if parent == ownPID { continue }
            let parentBundle = bundleIDForPID(parent)
            if parentBundle == tascamBundleID { continue }
            if var g = groups[parent] {
                g.objectIDs.append(p.objectID)
                g.isPlaying = g.isPlaying || p.isPlaying
                if g.bundleID == nil { g.bundleID = parentBundle ?? p.bundleID }
                groups[parent] = g
            } else {
                order.append(parent)
                groups[parent] = AppGroup(parentPID: parent, bundleID: parentBundle ?? p.bundleID,
                                          objectIDs: [p.objectID], isPlaying: p.isPlaying)
            }
        }
        return order.compactMap { groups[$0] }
    }
}
