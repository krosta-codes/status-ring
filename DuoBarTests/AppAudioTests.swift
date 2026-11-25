import XCTest
@testable import DuoBar

final class AppAudioTests: XCTestCase {
    private let suite = "statusring.tests"
    private var defaults: UserDefaults!
    private var posts = 0
    private var store: AppAudioSettingsStore!

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
        posts = 0
        store = AppAudioSettingsStore(defaults: defaults, post: { [unowned self] in self.posts += 1 })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    // MARK: settings

    func testDefaultEntryDroppedOnWrite() {
        store.save(["a": AppAudioSetting(), "b": AppAudioSetting(volume: 0.5)])
        let raw = defaults.dictionary(forKey: "appAudio")
        XCTAssertNil(raw?["a"])
        XCTAssertNotNil(raw?["b"])
        XCTAssertEqual(store.load().keys.sorted(), ["b"])
    }

    func testVolumeClamped() {
        XCTAssertEqual(AppAudioSetting(volume: 3).volume, 1)
        XCTAssertEqual(AppAudioSetting(volume: -1).volume, 0)
        XCTAssertEqual(AppAudioSetting(plist: ["volume": 7])?.volume, 1)
    }

    func testSettingsRoundTrip() {
        let s = AppAudioSetting(volume: 0.3, muted: true, outputUID: "BuiltInSpeakerDevice")
        store.set(s, for: "com.spotify.client")
        XCTAssertEqual(store.load()["com.spotify.client"], s)
        XCTAssertEqual(AppAudioSetting(plist: s.plist), s)
    }

    func testLenientStringDecode() {
        let s = AppAudioSetting(plist: ["volume": "0.3", "muted": "1"])
        XCTAssertEqual(s?.volume, 0.3)
        XCTAssertEqual(s?.muted, true)
        XCTAssertEqual(AppAudioSetting(plist: ["volume": 0, "muted": 1])?.muted, true)
        XCTAssertEqual(AppAudioSetting(plist: ["volume": NSNumber(value: 0.25)])?.volume, 0.25)
        XCTAssertNil(AppAudioSetting(plist: "nonsense"))
    }

    func testNotificationPostedAfterWrite() {
        store.set(AppAudioSetting(volume: 0.5), for: "x")
        XCTAssertEqual(posts, 1)
        store.remove("x")
        XCTAssertEqual(posts, 2)
    }

    // MARK: ownership

    private let usb = "TASCAM-UID"
    private let other = "EMBERTON-UID"
    private func exists(_ uid: String) -> Bool { [usb, other, "SPK"].contains(uid) }
    private func owner(_ s: AppAudioSetting?, default d: String, handoff: HandoffState) -> AppAudioOwner {
        AppAudioOwnership.owner(setting: s, defaultOutputUID: d, deviceExists: exists, handoff: handoff)
    }
    private var active: HandoffState { HandoffState(active: true, deviceUID: usb) }

    func testOwnershipUntouched() {
        XCTAssertEqual(owner(nil, default: other, handoff: active), .untouched)
        XCTAssertEqual(owner(AppAudioSetting(), default: usb, handoff: active), .untouched)
    }

    func testOwnershipFollowDefaultNonHandoffDevice() {
        XCTAssertEqual(owner(AppAudioSetting(volume: 0.3), default: other, handoff: active), .statusRing(targetUID: other))
    }

    func testOwnershipFollowDefaultToHandoffDevice() {
        XCTAssertEqual(owner(AppAudioSetting(volume: 0.3), default: usb, handoff: active), .tascam)
    }

    func testOwnershipExplicitRouteToHandoffDevice() {
        let s = AppAudioSetting(volume: 0.3, outputUID: usb)
        XCTAssertEqual(owner(s, default: other, handoff: active), .statusRing(targetUID: usb))
        XCTAssertEqual(owner(s, default: usb, handoff: active), .statusRing(targetUID: usb))
    }

    func testOwnershipMissingRouteFallsBackToDefault() {
        let s = AppAudioSetting(volume: 0.3, outputUID: "GONE")
        XCTAssertEqual(owner(s, default: other, handoff: active), .statusRing(targetUID: other))
    }

    func testOwnershipHandoffInactiveIsStatusRing() {
        let s = AppAudioSetting(volume: 0.3)
        XCTAssertEqual(owner(s, default: usb, handoff: .inactive), .statusRing(targetUID: usb))
        XCTAssertEqual(owner(s, default: usb, handoff: HandoffState(active: false, deviceUID: usb)), .statusRing(targetUID: usb))
    }

    // MARK: grouping

    private func proc(_ pid: pid_t, _ bundle: String?, playing: Bool = true, obj: UInt32) -> AudioProcessInfo {
        AudioProcessInfo(pid: pid, bundleID: bundle, isPlaying: playing, objectID: obj)
    }

    func testGroupingMergesHelpersUnderResponsible() {
        let procs = [proc(100, "com.apple.Safari", playing: false, obj: 1),
                     proc(101, "com.apple.WebKit.WebContent", obj: 2),
                     proc(200, "com.apple.Music", obj: 3)]
        let map: [pid_t: pid_t] = [101: 100]
        let groups = AppAudioGrouping.group(
            processes: procs, responsible: { map[$0] ?? $0 }, ownPID: 1,
            bundleIDForPID: { $0 == 100 ? "com.apple.Safari" : ($0 == 200 ? "com.apple.Music" : nil) })
        XCTAssertEqual(groups.count, 2)
        let safari = groups.first { $0.bundleID == "com.apple.Safari" }
        XCTAssertEqual(safari?.objectIDs, [1, 2])
        XCTAssertEqual(safari?.isPlaying, true)
        XCTAssertEqual(safari?.parentPID, 100)
    }

    func testGroupingSkipsOwnPID() {
        let groups = AppAudioGrouping.group(
            processes: [proc(5, "com.jurek.statusring", obj: 1), proc(6, "a.b", obj: 2)],
            responsible: { $0 }, ownPID: 5)
        XCTAssertEqual(groups.map(\.bundleID), ["a.b"])
    }

    func testGroupingSkipsTascamVolume() {
        let groups = AppAudioGrouping.group(
            processes: [proc(7, "com.jurek.tascamvolume", obj: 1),
                        proc(8, nil, obj: 2),
                        proc(9, "a.b", obj: 3)],
            responsible: { $0 == 8 ? 7 : $0 }, ownPID: 1,
            bundleIDForPID: { $0 == 7 ? "com.jurek.tascamvolume" : nil })
        XCTAssertEqual(groups.map(\.bundleID), ["a.b"])
    }

    func testTascamHandoffDecoding() {
        XCTAssertTrue(TascamHandoffDecoding.bool(true))
        XCTAssertTrue(TascamHandoffDecoding.bool(1))
        XCTAssertTrue(TascamHandoffDecoding.bool(" Yes "))
        XCTAssertFalse(TascamHandoffDecoding.bool("0"))
        XCTAssertFalse(TascamHandoffDecoding.bool(nil))
        let on = TascamHandoffDecoding.state(running: true, handoff: 1, engineRunning: "true", deviceUID: "uid")
        XCTAssertEqual(on, HandoffState(active: true, deviceUID: "uid"))
        XCTAssertEqual(TascamHandoffDecoding.state(running: false, handoff: 1, engineRunning: 1, deviceUID: "uid"), .inactive)
        XCTAssertEqual(TascamHandoffDecoding.state(running: true, handoff: 0, engineRunning: 1, deviceUID: "uid"), .inactive)
        XCTAssertEqual(TascamHandoffDecoding.state(running: true, handoff: 1, engineRunning: 0, deviceUID: "uid"), .inactive)
        XCTAssertEqual(TascamHandoffDecoding.tapped(["a", 3, "b"]), ["a", "b"])
        XCTAssertEqual(TascamHandoffDecoding.tapped(nil), [])
    }
}
