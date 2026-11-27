# Per-app volume and output routing in Status Ring

Repo: `~/Projects/apps/status-ring` (fork of DuoBar, Swift, built with `swiftc` from the Command Line Tools, no Xcode). Second repo touched in checkpoint 4: `~/Projects/apps/tascam-volume`.

## Goal and done

**User story:** As Jurek, I open the Status Ring popover, tap into the Volume card and see every app that is playing audio right now. Each app has its own slider (0 to 100 %), a mute toggle and an output picker. One app can be quieter than the rest, or go to a different speaker, and the setting comes back the next time that app plays. On the TASCAM US-4x4, the per-app gains are applied by TascamVolume inside its existing tap, so each app is only ever tapped once.

Decisions agreed with Jurek on 2026-11-25:
- Scope: slider and mute per app, per-app output device, settings remembered per bundle ID. **No boost above 100 %.**
- On the US-4x4: **hand off.** Status Ring writes the per-app settings; TascamVolume applies gain and mute in its IOProc. On every other output, Status Ring runs its own taps.
- Class: `public · Mac · AI: no · rung 2` (public GitHub repo with releases). STANDARD.md section 0: Mac only, so sections 2, 3, 6, 7, 8 and 11 do not apply. The `.icns` icon already exists (`assets/AppIcon.icns`).

**Acceptance criteria (each is a checkable fact):**
1. AC1 List: with Music and Safari both playing, the App Volume panel shows one row each, with the app's name and icon. Helper processes (e.g. `com.apple.WebKit.WebContent`, Chrome Helper) are listed under their parent app, not as separate rows. An app that stops playing disappears from the list within 3 s, unless it has saved non-default settings (then it stays, dimmed). **Changed by Jurek 2026-11-27:** every running regular app (Dock icon) is listed, playing apps first, the rest dimmed, so an app can be set before it plays; its engine starts once the app has audio process objects (the first moment of sound may pass untapped).
2. AC2 Gain: setting an app to 30 % gives that app an output-to-input peak ratio of 0.30 ±0.02 in the debug log, and no other app changes. The default output's own volume is untouched.
3. AC3 Mute: muting an app gives an output peak of 0 for that app while other apps still play.
4. AC4 No-op default: an app at 100 %, unmuted, on the default output has **no tap** (the process tap count in the debug log is 0 for it). Status Ring adds no latency to apps you never touched.
5. AC5 Route: an app set to output X plays only on X (its original output is silent for it), and keeps the per-app gain. If X disappears, the app falls back to the current default output and the saved route stays, so it applies again when X comes back.
6. AC6 Remember: quit the app, quit Status Ring, relaunch both: the app comes back at its saved level, mute and route. `defaults read com.jurek.statusring appAudio` shows a readable dictionary keyed by bundle ID.
7. AC7 Handoff: with TascamVolume running and the US-4x4 as the default output, an app at 30 % is scaled by TascamVolume (its log shows the per-app tap), and Status Ring holds **no** tap for that app. When the default switches to EMBERTON, Status Ring takes over within 2 s, and TascamVolume drops that app's per-app tap.
8. AC8 Fail-safe: `kill -9` on Status Ring brings every app back to full level on its original output (macOS removes private taps when the process dies). Same for TascamVolume.
9. AC9 Older macOS: built for macOS 13 as before. On < 14.2 the Volume card shows no App Volume disclosure and nothing crashes (an `@available(macOS 14.2, *)` gate around everything tap-related).
10. AC10 Normal use: the master Volume slider, the volume keys while the popover is open, output and input switching, and module reordering all still work.

## Read first

| File | Lines | Why |
|---|---|---|
| `README.md` | all | What the app is, build script, signing, privacy table. Gets a `Class:` line and a feature section in CP5. |
| `build-local.sh` | 1-60 | Build: `swiftc` over `find DuoBar -name '*.swift'`, target `macos13.0`, SDK auto-pick (newest 26.x). Signs with "DuoBar Local Signing" (exists in the keychain, keeps TCC grants across rebuilds). New `.swift` files under `DuoBar/` get picked up automatically. |
| `assets/Info.plist` | all | Bundle ID `com.jurek.statusring`, `LSUIElement`, usage strings. Gets `NSAudioCaptureUsageDescription`. |
| `DuoBar/Services/AudioOutputService.swift` | 1-200, 246-300, 380-410, 525-613 | Core Audio listener pattern (`ListenerRegistration`, `registerSystemListener`), default output read, device list, `readString`/`readUInt32` helpers. Copy the listener pattern; do not change this file's behavior. |
| `DuoBar/Models/SystemStatusStore.swift` | 1-130, 260-320 | `@MainActor ObservableObject` that owns the services and exposes `setVolume`, `setDefaultOutput`. The new app-audio store sits next to it, not inside it (keeps this 574-line file stable). |
| `DuoBar/App/AppDelegate.swift` | 50-75, 180-191 | Where `SystemStatusStore` is created and torn down. The new store is created and stopped here too. |
| `DuoBar/MenuBar/StatusPopoverView.swift` | 1-40, 133-215, 271-320 | Module switch (`case .volume` at 152), `PopoverDetail` enum (271), `showDetail`, `detailPanel`, `matchedGeometryEffect` expansion. The new detail `.apps` is added exactly like `.output`. |
| `DuoBar/UI/VolumeStatusRow.swift` | all (152) | The Volume card. Gets a trailing disclosure that opens the App Volume panel. |
| `DuoBar/UI/AudioOutputRow.swift` | all (109) | `AudioDevicePanelView`: the visual reference for the new panel (header with Back, list, footer). Copy its structure and styling. |
| `DuoBar/UI/StatusRow.swift`, `PopoverCardBackground.swift` | all | Row and card styling to reuse. |
| `DuoBar/Utilities/PreferenceKeys.swift` | all | Add `appAudio` and `appAudioDebug` keys here. |
| `DuoBar/en.lproj/Localizable.strings` and the 5 other `.lproj` | | Every `localized("…")` key needs an entry; `DuoBarTests/LocalizationTests.swift` shows the expectation (all locales carry all keys). |
| `~/Projects/apps/tascam-volume/README.md` | all | How TascamVolume taps the US-4x4 (`excludingProcesses`, `mutedWhenTapped`, call-app tap with drift compensation, zone 2). |
| `~/Projects/apps/tascam-volume/Sources/TascamVolume/GainEngine.swift` | 84-230, 264-end | `currentExclusions()`, `start()` (tap and aggregate creation: **the code to copy** for Status Ring's tap engine), `stop()`, `render` (gain ramp per buffer, interleaved and non-interleaved walk). |
| `~/Projects/apps/tascam-volume/Sources/TascamVolume/Controller.swift` | 1-110, 190-260 | Defaults registration, `reconcile()` (rebuilds the tap when excluded apps start or quit), wake handling. |
| `~/Projects/apps/tascam-volume/Sources/TascamVolume/CoreAudioHelpers.swift` | all (80) | `CA.objects/value/string/device` helpers. Status Ring may copy this file under a new name (`DuoBar/Utilities/CoreAudioQuery.swift`, rename the enum to `CAQuery` to avoid clashes). Both repos are Jurek's; licenses allow it. |
| `~/Projects/apps/app-standard/STANDARD.md` | section 0, 1, 10 | Class line, repo skeleton, rung 2 release rules. |

Live systems touched: none (no Shopify, GHL, n8n, Coolify, Klaviyo). The only outward step is `git push` to the public `krosta-codes/status-ring` and private `krosta-codes/tascam-volume` repos, plus an optional GitHub release (CP5, ask Jurek first).

## Design

### Data model (shared contract with TascamVolume)

Stored in the `com.jurek.statusring` defaults domain under key `appAudio` as a **plist dictionary**, not JSON data, so `defaults read` shows it and TascamVolume can read it:

```
appAudio = {
  "com.spotify.client" = { volume = 0.3; muted = 0; outputUID = "BuiltInSpeakerDevice"; };
  "com.apple.Safari"   = { volume = 1;   muted = 1; };
}
```

- `volume`: Double 0...1. `muted`: Bool. `outputUID`: optional String, absent = follow the default output.
- An entry at volume 1, not muted, without `outputUID` is removed (the store stays small, and "no entry" means "untouched").
- After every write, Status Ring posts the distributed notification `com.jurek.statusring.appAudioChanged` (no userInfo). TascamVolume observes it, calls `CFPreferencesAppSynchronize("com.jurek.statusring" as CFString)` and rereads with `UserDefaults(suiteName: "com.jurek.statusring")`. Both apps are not sandboxed, so this works.
- TascamVolume announces that it supports the handoff by writing `perAppHandoff = 1` and `perAppDeviceUID = <US-4x4 UID>` into its own domain `com.jurek.tascamvolume` at startup, and posts `com.jurek.tascamvolume.stateChanged` on start, stop and device change. Status Ring treats the handoff as active only while (a) an app with bundle ID `com.jurek.tascamvolume` is running, (b) `perAppHandoff` is true, and (c) its engine is running (`perAppEngineRunning = 1`, written by TascamVolume on engine start and stop).

### Who taps which app (pure function, `AppAudioOwnership`)

Input: the app's setting (or none), the current default output UID, the handoff state. Output: `.untouched`, `.statusRing(targetUID)` or `.tascam`.

- No entry → `.untouched` (AC4).
- Effective target = `outputUID` if that device exists now, else the default output (AC5 fallback).
- Handoff active, and the effective target is the handoff device, **and** `outputUID` is nil (the app follows the default) → `.tascam`.
- Everything else → `.statusRing(target)`. That includes an app routed explicitly to the US-4x4 while the default is EMBERTON: Status Ring plays it to the US-4x4, and TascamVolume's main tap then picks up Status Ring's own output and applies the master volume keys on top. That is correct behavior; write it in the README.
- TascamVolume applies the same rule on its side: it creates per-app taps only for entries with no `outputUID` while the US-4x4 is the default output. Entries with an `outputUID` are **excluded** from its main tap (Status Ring's muted tap handles them), so they are never doubled.

### Status Ring tap engine (`AppTapEngine`, one per managed app)

Copy the structure of TascamVolume's `GainEngine.start/stop/render`, simplified:
- `CATapDescription(stereoMixdownOfProcesses: [all process objects of the app group])`, `isPrivate = true`, `muteBehavior = .mutedWhenTapped`, `name = "Status Ring <bundleID>"`.
- Private aggregate: target device as main sub-device and clock, one tap entry with `kAudioSubTapDriftCompensationKey: true` (the app may be clocked by a different device than the target), `kAudioAggregateDeviceTapAutoStartKey: true`.
- IOProc: zero all outputs, copy the stereo tap buffer to output channels 1/2 (walk buffers like `GainEngine.render`, works for interleaved and non-interleaved), multiply by a gain that ramps linearly per buffer from current to target (no zipper clicks). Mute = target gain 0. Record input and output peak into the shared pointer for the debug log.
- Gain changes write the shared target only; no rebuild. Rebuilds happen only when the target device or the app's process set changes.
- One engine per app keeps apps isolated: adding or removing one app never glitches another.
- `stop()` destroys IOProc, aggregate and tap in that order (copy `GainEngine.stop`).
- Fail-safe (AC8) comes for free: private taps and aggregates die with the process.

### Discovery (`AppAudioService`)

- Listen to `kAudioHardwarePropertyProcessObjectList` on the system object, and to `kAudioProcessPropertyIsRunningOutput` on each process object (register and unregister as the list changes). Also a 2 s safety poll while the popover is open.
- For each process object: PID (`kAudioProcessPropertyPID`), bundle ID (`kAudioProcessPropertyBundleID`), running output.
- Group helpers under their parent app: resolve the responsible PID via `responsibility_get_pid_responsible_for_pid` (private libsystem symbol, load with `dlsym(RTLD_DEFAULT, …)`; if missing, fall back to the PID itself). Then `NSRunningApplication(processIdentifier:)` gives name, icon and bundle ID of the parent. Skip Status Ring's own PID, and skip TascamVolume and its `--nudge` helper (bundle `com.jurek.tascamvolume`).
- Publishes `[AudioApp]`: `bundleID`, `name`, `icon`, `processObjects: [AudioObjectID]`, `isPlaying`.
- Keep the grouping logic (PID list in, groups out) in a pure function in `DuoBar/Models/AppAudioGrouping.swift` so it is testable without Core Audio.

### Store and UI

- `AppAudioStore` (`@MainActor ObservableObject`, `DuoBar/Models/AppAudioStore.swift`): owns `AppAudioService`, the settings, the handoff state and a dictionary of running `AppTapEngine`s. On every change it runs `AppAudioOwnership` per app and starts, retargets or stops engines. Listens to default output changes (own listener on `kAudioHardwarePropertyDefaultOutputDevice`), device list changes, `NSWorkspace.didWakeNotification` (rebuild all engines), and the TascamVolume notification.
- Created in `AppDelegate` next to `SystemStatusStore`, only `if #available(macOS 14.2, *)`, passed into `StatusPopoverView` as an optional.
- UI brief (unslop-ui): reference = the app's own `AudioDevicePanelView` (Control Center-style detail panel); color = the existing popover palette, no new accent; type = the popover's existing system font (SF), because the whole popover uses it. Switching Status Ring to Plus Jakarta Sans is a separate decision, not part of this build; note it in Progress as an open question for Jurek. Layout intent: the Volume card gets a small chevron; tapping it expands into "App Volume", one row per app: icon 18 pt, name, mute button (speaker glyph, like the master row), slider 0...1, an output menu (`Menu` with "Follow default" plus the selectable outputs, current choice checkmarked). Context menu on a row: "Reset" (removes the entry). Empty state: "No apps are playing audio". Footer: "Sound Settings…" like the output panel.
- If the System Audio Recording permission is denied, the panel shows one line with a button that opens Privacy & Security › Screen & System Audio Recording (`x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture`).

### Store API (fixed before CP2 so T5 and T6 can build in parallel)

```swift
@available(macOS 14.2, *) @MainActor final class AppAudioStore: ObservableObject {
    @Published private(set) var apps: [AppAudioRow]        // playing apps + running apps with saved settings
    @Published private(set) var outputs: [AudioDeviceStatus] // selectable outputs, same type as AudioStatus.selectableOutputs
    @Published private(set) var permission: AppAudioPermission // .unknown, .granted, .suspectedDenied
    @Published private(set) var handoff: HandoffState
    func setVolume(_ v: Double, for bundleID: String)
    func setMuted(_ m: Bool, for bundleID: String)
    func setOutput(_ uid: String?, for bundleID: String)    // nil = follow default
    func reset(_ bundleID: String)
    func start(); func stop()
}
struct AppAudioRow: Identifiable { id: String /*bundleID*/; name: String; icon: NSImage?; isPlaying: Bool; setting: AppAudioSetting; owner: AppAudioOwner }
```

### Handoff switchover (make before break)

- TascamVolume writes `perAppTapped` (array of bundle IDs it currently taps per app) into its domain after each engine (re)start and posts `com.jurek.tascamvolume.stateChanged`.
- Status Ring releases its own engine for an app only once that bundle ID shows up in `perAppTapped`. Going the other way (default switches away from the US-4x4), Status Ring starts its engine first; TascamVolume rebuilds on the default-output change anyway and drops the app.
- Added 2026-11-27 by the lead after the AC8 test: `kill -9` of TascamVolume posts nothing and NSWorkspace did not report the termination, so `TascamHandoffMonitor` re-checks once per second while the handoff is active (watchdog timer).
- Accepted short overlap: during a TascamVolume rebuild (tens of ms) an app may be tapped twice or not at all. Documented, not engineered away.

### Engine details the review added

- **Input streams off:** after creating the aggregate, switch its device input streams off for the IOProc (copy `setInterfaceInputs(on: false)` from `GainEngine.swift:244-262`), so a Bluetooth headset does not drop to HFP and no mic indicator appears.
- **New helper process:** when an app's process set grows, build the new engine first, then stop the old one. A helper plays untapped for that moment; documented.
- **Idle apps:** no engine for an app with no running processes. The engine starts when the app's first process appears in the process list, stops when the last one leaves.
- **Device changes:** listen to `kAudioDevicePropertyNominalSampleRate` and `kAudioDevicePropertyDeviceIsAlive` on each target device; rebuild that device's engines on change.
- **Permission:** there is no public query for System Audio Recording. Detector: an engine whose app reports `IsRunningOutput = 1` but whose tap delivers exact zeros for 3 s → `permission = .suspectedDenied`, stop that engine (which unmutes the app). The panel then shows the permission line. Added in CP2 by the lead: the detector only counts zero reads while `permission != .granted`; once any tap delivered audio, zeros mean silence (a paused video can keep `IsRunningOutput` on), so an engine is never dropped for them. Open Privacy & Security with `x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture`; the CP3 lead verifies this URL lands on the right pane and records a fallback (`?Privacy_ScreenCapture`) if not.
- **Debug log:** peaks are max-and-reset per 1 s window, written by the IOProc into the shared pointer, read and reset by a main-thread timer. Ratio prints `n/a` when input peak < 0.001. Use `%{public}@` in `os_log` so `log stream` shows values. **No `os_log` in the IOProc.**
- **Reading across apps:** TascamVolume reads Status Ring's settings with `CFPreferencesAppSynchronize` + `CFPreferencesCopyAppValue("appAudio", "com.jurek.statusring")`, with the same lenient decoding.

### Pitfalls known up front

- Every rebuild by the in-app updater signs with the local certificate; on Macs without one (other users), the System Audio Recording permission is asked again after each update. Say so in the README.
- `NSAudioCaptureUsageDescription` must be in `assets/Info.plist`, or tap creation fails silently with a permission error. The first tap triggers the TCC prompt. Signing with "DuoBar Local Signing" keeps the grant across rebuilds; an ad-hoc build re-prompts every time.
- The macOS 27 SDK needs Xcode's SwiftUI macros; keep using the 26.x SDK that `build-local.sh` picks. `CATapDescription` is in the 26.x SDK. Gate with `@available(macOS 14.2, *)`, the target stays `macos13.0`.
- Tests run with Xcode 27.2 (`/Applications/Xcode.app`, XCTest and Swift Testing) through `./run-tests.sh [TestClass ...]`, which sets `DEVELOPER_DIR` itself (xcode-select still points at the Command Line Tools; leave it). Baseline 2026-11-25: 328 tests, 0 failures, 6 skipped. The project uses synchronized folders (objectVersion 77), so new files in `DuoBar/` and `DuoBarTests/` join their targets without editing `project.pbxproj`. `build-local.sh` (swiftc) stays the build and install path.
- Never tap TascamVolume itself, and never let two Status Ring engines tap the same process.
- Call apps (WhatsApp, FaceTime, Zoom) run on the mic clock: drift compensation is on for every Status Ring tap, so they are safe. On the TascamVolume side, a per-app tap for a call app needs drift compensation too (match `callBundlePrefixes`).
- The IOProc runs on a real-time thread: no allocation, no locks, no Swift arrays grown inside it. Copy the `UnsafeMutablePointer<Float>` shared-state pattern from `GainEngine`.

## Tasks

Each task owns its files. No two tasks in one checkpoint share a file.

### CP1: model and tests

- **T1 Models + XCTest cases** (one subagent)
  - Files (new): `DuoBar/Models/AppAudioSettings.swift`, `DuoBar/Models/AppAudioOwnership.swift`, `DuoBar/Models/AppAudioGrouping.swift`, `DuoBar/Utilities/CoreAudioQuery.swift` (copy of TascamVolume `CoreAudioHelpers.swift`, enum renamed `CAQuery`; moved here so T2 and T3 both find it), `DuoBarTests/AppAudioTests.swift` (XCTest, `@testable import DuoBar`, like the existing test files). Edit: `DuoBar/Utilities/PreferenceKeys.swift` (add `appAudio`, `appAudioDebug`).
  - Decoding is lenient: `volume` accepts Double, Int, NSNumber or String (`defaults write -dict-add '{volume=0.3;}'` stores a string), `muted` accepts Bool, Int or String.
  - `AppAudioSettings`: struct `AppAudioSetting { volume: Double; muted: Bool; outputUID: String? }`, `isDefault`, plist dictionary encode and decode (`[String: Any]`), a `AppAudioSettingsStore` that reads and writes `UserDefaults` key `appAudio`, drops default entries on write, clamps volume to 0...1, and posts `com.jurek.statusring.appAudioChanged` via `DistributedNotificationCenter` after writing (injectable poster for tests).
  - `AppAudioOwnership`: pure function from the design section.
  - `AppAudioGrouping`: pure function `group(processes: [(pid, bundleID, isPlaying, objectID)], responsible: (pid) -> pid, ownPID:) -> [AppGroup]`, skipping own PID and `com.jurek.tascamvolume`.
  - Only Foundation and CoreAudio types in these files (no AppKit), so the logic stays testable without UI.
  - Tests are plain XCTest cases in `DuoBarTests/AppAudioTests.swift`; settings tests use a scratch `UserDefaults(suiteName: "statusring.tests")` and remove it in `tearDown`.
  - Cases: default entry dropped on write; clamp; round trip through a scratch `UserDefaults(suiteName: "statusring.tests")`; ownership table (untouched, follow default to non-handoff device, follow default to handoff device = tascam, explicit route to handoff device = statusRing, missing route device = fallback to default, handoff inactive = statusRing); grouping (helpers merged under responsible PID, own PID skipped, TascamVolume skipped, not-playing app without settings dropped by the caller flag).
  - Proof: `./run-tests.sh AppAudioTests` exit 0, then `./run-tests.sh` (all 328 + new) exit 0; `./build-local.sh --no-install` still builds.

### CP2: engine and discovery (waits for CP1: uses its types)

- **T2 AppAudioService** (subagent A, parallel with T3: different files)
  - File (new): `DuoBar/Services/AppAudioService.swift` (uses `CAQuery` from CP1).
  - Listener pattern from `AudioOutputService.swift` (`ListenerRegistration`), grouping from `AppAudioGrouping`, responsible PID via `dlsym`.
  - Proof: a hidden launch flag `StatusRing --list-audio-apps` prints the current groups as `bundleID pid-count playing` and exits; with Music playing it prints `com.apple.Music 1 1`. Add the flag handling in this file as a static func; T4 calls it from `DuoBarApp`/`AppDelegate` **before** `ApplicationInstanceLock` is taken (`AppDelegate.swift:37`), and exits. It also works while the installed Status Ring runs.
- **T3 AppTapEngine** (subagent B)
  - File (new): `DuoBar/Services/AppTapEngine.swift`.
  - From the design section; copy from `GainEngine.swift:114-262` and `264-end`. API: `init(bundleID:, processObjects:, targetUID:)`, `start() throws`, `stop()`, `var gain: Float` (target), `var muted: Bool`, `var peaks: (input: Float, output: Float)`, `var isRunning`.
  - Proof: compiles inside `./build-local.sh --no-install`. Functional proof comes in T4's check.
- **T4 Store + wiring** (after T2 and T3; lead hands it to one subagent)
  - Files: new `DuoBar/Models/AppAudioStore.swift`; edit `DuoBar/App/AppDelegate.swift` (create and stop the store, `--list-audio-apps` flag before the instance lock), `DuoBar/MenuBar/MenuBarController.swift` (hold the store and pass it to `StatusPopoverView` at line 77; until T6 adds the init parameter, T4 only stores it), `assets/Info.plist` (add `NSAudioCaptureUsageDescription`: "Status Ring reads an app's audio only to change its volume or send it to another output.").
  - Debug log: when `appAudioDebug` is true, log once per second per engine via `os_log` (subsystem `com.jurek.statusring`, category `appAudio`): `bundleID target=<uid> gain=<g> in=<peak> out=<peak> ratio=<out/in>`, plus `taps=<n>` overall.
  - Until CP3, settings are set from the command line: `defaults write com.jurek.statusring appAudio -dict-add com.apple.Music '{volume=0.3;}'`. A `defaults write` from outside does not reliably fire `UserDefaults.didChangeNotification` in the running app, so the store also rereads `appAudio` once per second while `appAudioDebug` is true (debug only).
  - Proof (lead runs): AC2, AC3, AC4, AC5, AC8 via the debug log (see Proof).

### CP3: UI (waits for CP2: binds to `AppAudioStore`)

- **T5 App Volume panel** (subagent A, parallel with T6)
  - File (new): `DuoBar/UI/AppVolumePanelView.swift`. Structure copied from `AudioDevicePanelView` in `DuoBar/UI/AudioOutputRow.swift`. Rows, mute, slider, output `Menu`, Reset context menu, empty state, permission-denied state, footer.
  - Proof: builds; screenshot in CP3 check.
- **T6 Volume card disclosure + popover detail + strings** (subagent B)
  - Also owns the one-line edit at `DuoBar/MenuBar/MenuBarController.swift:77` that passes the store into `StatusPopoverView` (T4 is finished by then, no conflict).
  - Files: `DuoBar/UI/VolumeStatusRow.swift` (optional `onShowApps: (() -> Void)?`, trailing chevron button shown only when non-nil, accessibility label "App Volume"), `DuoBar/MenuBar/StatusPopoverView.swift` (accept optional `AppAudioStore`, `PopoverDetail.apps`, `matchedGeometryEffect` on the volume row, `detailPanel` case), all six `Localizable.strings` (new keys: "App Volume", "No apps are playing audio", "Follow default", "Reset", "Allow System Audio Recording", the permission line; translate for ru, th, uk, zh-Hans, zh-Hant), and the `StatusPopoverView(...)` call site wherever it is constructed (`grep -rn "StatusPopoverView(" DuoBar`).
  - Proof: builds; `grep -c` of each new key is 1 in every `.lproj`.

### CP4: TascamVolume handoff (waits for CP2; can run parallel with CP3, different repo)

- **T7 TascamVolume per-app gains** (see Design, Handoff switchover) (one subagent, repo `~/Projects/apps/tascam-volume`)
  - Files: `Sources/TascamVolume/GainEngine.swift`, `Sources/TascamVolume/Controller.swift`, `README.md`.
  - Read Status Ring's `appAudio` via `UserDefaults(suiteName: "com.jurek.statusring")` after `CFPreferencesAppSynchronize`; observe `com.jurek.statusring.appAudioChanged`.
  - In `currentExclusions()`: apps whose bundle has an entry **with** `outputUID` → excluded from the main tap **and from `mirror`** (else zone 2 hears them raw while Status Ring also plays them), no tap of their own. Only while Status Ring is running (`NSRunningApplication` with bundle `com.jurek.statusring`); otherwise they stay in the main tap like any app. Apps whose entry has **no** `outputUID` → excluded from the main tap and get their own tap (`CATapDescription(processes: [objects], …)`, `mutedWhenTapped`, drift compensation only for call bundles), appended to the aggregate's tap list.
  - `render`: preallocate (outside the IOProc) a scratch buffer of the main tap's size; per cycle copy the main tap into it, add each per-app tap × its own ramped gain (gain or 0 if muted; per-app gains live in the shared `UnsafeMutablePointer<Float>`, extend its capacity), then run the existing master-gain, zone 2 and crossover path on the scratch buffer. Index bookkeeping like `callsIndex`/`mirrorIndex`.
  - Gain-only changes write the shared pointer, no rebuild. Set changes (an app gains or loses an entry, or its `outputUID` toggles) go through the existing `reconcile()` → `engine.restart()`.
  - At engine start and stop write `perAppHandoff`, `perAppDeviceUID`, `perAppEngineRunning` into its own defaults and post `com.jurek.tascamvolume.stateChanged`.
  - `--debug` logs each per-app tap: `app <bundleID> gain=<g> in=<peak>`.
  - README: a "Per-app volume (Status Ring)" section.
  - Proof: `build.sh` green; AC7 by the lead.
- **T8 Status Ring handoff state** (subagent B, parallel with T7: other repo)
  - File (new): `DuoBar/Services/TascamHandoffMonitor.swift`; edit `DuoBar/Models/AppAudioStore.swift` (if T5/T6 are running at the same moment, T8 waits: AppAudioStore is not touched by T5/T6, so no conflict).
  - Reads the three TascamVolume keys from `UserDefaults(suiteName: "com.jurek.tascamvolume")`, watches `NSWorkspace` launch and terminate for `com.jurek.tascamvolume`, observes `com.jurek.tascamvolume.stateChanged`, publishes `HandoffState { active: Bool; deviceUID: String? }` into the ownership function.
  - Proof: with TascamVolume running, `defaults write com.jurek.statusring appAudioDebug -bool true` shows `handoff=active device=<uid>` in the log.

### CP5: docs, version, release

- **T9 Docs** (lead or one subagent)
  - `README.md`: `Class: public · Mac · AI: no · rung 2` under the title; feature bullet "App Volume"; permission row "System Audio Recording (per-app volume, optional)"; privacy table row "App audio: processed live on this Mac, never recorded or sent"; Known quirks: needs macOS 14.2+, TascamVolume handoff, explicit route to the US-4x4 is also scaled by its master keys. `VERSION` → `2.1.0`.
  - Proof: README renders; no em or en dashes (`grep -nP '[\x{2013}\x{2014}]' README.md` empty).

## Checkpoints

| CP | Delivers | Tasks | Check |
|---|---|---|---|
| 0 | Verification path works | lead | `security find-identity -p codesigning` lists "DuoBar Local Signing"; `./build-local.sh --no-install` green on the current tree; `log stream --predicate 'subsystem == "com.jurek.statusring"'` runs; US-4x4 connected (ask Jurek to plug it in if `system_profiler SPAudioDataType` does not list it; without it AC7 stays unverified and CP4 cannot close). |
| 1 | Settings, ownership, grouping, tested | T1 | `./run-tests.sh` exit 0, plus each red-turn in Proof. |
| 2 | Per-app gain, mute and route work from `defaults write` | T2, T3 parallel; then T4 | AC2, AC3, AC4, AC5, AC8 via the debug log. |
| 3 | The App Volume panel in the popover | T5, T6 parallel | AC1, AC6, AC10, screenshot of the popover (light and dark), unslop scan. |
| 4 | Handoff with TascamVolume | T7, T8 parallel | AC7, AC8 for TascamVolume, Tascam zone 2 still plays (Jurek listens), call app test (WhatsApp call, no crackle). |
| 5 | Docs, version 2.1.0, pushed | T9 | README check, both repos pushed. |

CP3 and CP4 may overlap (different files and repos), at most 2 subagents at a time.

## How to run it

- Read this whole plan first. You are the lead: you write no code (there are no lead-only tasks here; nothing writes to a live customer system).
- Per checkpoint, hand the parallel tasks to subagents in waves of at most 2, each with `model: "sonnet"`.
- Each brief names: its task id and text from this plan, its files and only those, the bar to meet (the task's Proof line plus "builds with `./build-local.sh --no-install`"), the output path `~/Projects/apps/status-ring/plans/reports/<task-id>.md` which it writes after its first solid finding and appends to, and the report format PASS, ISSUES or BLOCKED with evidence (path, command output). Subagents run no git and do not install (`--no-install` only).
- Only the lead runs checks, installs (`./build-local.sh`), commits (no Claude attribution line, no `Co-Authored-By`) and updates Progress.
- Before each commit read the actual changed files, not the report. A mismatch goes back to its subagent or gets fixed.
- Something unplanned comes up: write it into this plan (Design or Tasks) before anyone builds it.
- After each checkpoint: commit, write the result and evidence into Progress. If the context window is half full, write the next checkpoint into Progress and stop; a fresh session continues from this plan.
- Two failed fixes resting on the same assumption: stop, name the assumption, find an observation that could refute it.
- Last step: commit and push both repos (`git push` in `status-ring` and `tascam-volume`). A GitHub release for `v2.1.0` (which triggers the in-app update banner for every user) only after Jurek says yes.

## Proof

Verification path: this is a native menu bar app, so there is no browser check. Proof is (1) XCTest via `./run-tests.sh` for the pure logic (Xcode 27.2), (2) the debug log of the real engines with real audio, (3) screenshots of the popover via `screencapture -l<windowid>` or `screencapture -R`, (4) Jurek listening for the audible checks (zone 2, call quality), which the lead asks for explicitly and records.

Test audio: `afplay -v 1 /System/Library/Sounds/Submarine.aiff` in a loop gives a process with a known bundle (`afplay` has none: use Music.app with any local track, and Safari with a YouTube tab, as the two real apps).

| AC | Test | Red-turn (make it, see it fail, undo with the exact reverse edit) |
|---|---|---|
| AC1 | `StatusRing --list-audio-apps` with Music + Safari playing lists exactly `com.apple.Music` and `com.apple.Safari` (no WebContent row); panel screenshot. Test `grouping merges helpers`. | In `AppAudioGrouping`, use `pid` instead of `responsible(pid)`: the test fails. |
| AC2 | `defaults write … com.apple.Music '{volume=0.3;}'`; log shows `com.apple.Music … ratio=0.30` (±0.02) and Safari has no engine. | In `AppTapEngine` render, skip the gain multiply: ratio reads 1.00. |
| AC3 | `{muted=1;}`: log `out=0.000`, Safari still audible. | Mute maps to gain 1 instead of 0: out ≠ 0. |
| AC4 | Entry removed: `taps=0` in the log. Test `ownership untouched`. | Ownership returns `.statusRing` for no entry: test fails, log shows `taps=1`. |
| AC5 | `{outputUID="<MacBook speakers UID>";}` with EMBERTON default: sound only from the MacBook. Then switch the MacBook speakers off by choosing a non-existing UID: falls back to EMBERTON; `defaults read` still shows the UID. Test `ownership missing route falls back`. | Fallback returns nil target: test fails. |
| AC6 | Quit Music and Status Ring, relaunch both, play: the log shows the saved gain within 3 s. Test `settings round trip`. | Drop the `outputUID` key in encode: round trip fails. |
| AC7 | US-4x4 default, TascamVolume running with `--debug`: its log shows `app com.apple.Music gain=0.30`, Status Ring log shows no engine for Music and `handoff=active`. Switch default to EMBERTON: within 2 s Status Ring log shows the Music engine, TascamVolume rebuilds without the per-app tap. Test `ownership follow default to handoff device`. | Ownership ignores handoff: test fails, and both logs show a Music tap. |
| AC8 | `kill -9 $(pgrep -x StatusRing)` while Music is at 30 %: Music back at full level on its original output (Jurek listens, or `TascamVolume --debug` input peak for Music returns to the unscaled level). Restart via `open /Applications/StatusRing.app`. | none (property of macOS). |
| AC9 | `grep -n "@available(macOS 14.2" DuoBar` covers `AppTapEngine`, `AppAudioService`, `AppAudioStore`, `AppVolumePanelView`; build still targets `macos13.0` (`grep -n macos13.0 build-local.sh`). No macOS 13 machine available: mark "unverified on 13, compile-gated" in Progress. | Remove one `@available`: build fails with an availability error. |
| AC10 | Manual pass with the installed app: master slider, volume keys with popover open, output switch, input switch, ⌘-drag reorder, the network detail panel. Screenshot. | none. |

Whole-build checks before CP5: `./run-tests.sh` exit 0; `./build-local.sh` green and installed; `python3 ~/.claude/skills/unslop-ui/scripts/devibe_scan.py DuoBar/UI/AppVolumePanelView.swift --severity high` exit 0 (if the scanner does not handle Swift, note "scanner n/a for Swift" and do the unslop checklist by hand on the screenshot); TascamVolume `build.sh` green; Activity Monitor CPU for Status Ring with two engines running < 3 %.

Done means: every AC either proven with evidence in Progress or explicitly marked "unverified" with the reason. An unverified AC7 or AC8 blocks the push of `tascam-volume`.

## Review findings

Sonnet review 2026-11-25 (full report: `plans/reports/plan-review.md`). Verdict ISSUES; all findings resolved in the plan:

| Finding | Resolution |
|---|---|
| Apps with `outputUID` excluded from the Tascam main tap still reach zone 2 via `mirror` | T7: also excluded from `mirror` |
| Tascam excludes routed apps even when Status Ring is not running | T7: only while Status Ring runs |
| Handoff order undefined (gap or double tap) | Design: make before break via `perAppTapped` |
| No store API for parallel UI tasks | Design: Store API block |
| `MenuBarController.swift:77` wiring unowned | T4 stores it, T6 passes it |
| No permission query, silent-but-muted risk | Design: zero-peak detector stops the engine |
| Aggregate input streams left on | Design: input streams off |
| Helper process plays untapped until rebuild | Design: build new engine first, documented |
| `--list-audio-apps` blocked by the instance lock | T2/T4: handled before the lock |
| `defaults write` stores strings | T1: lenient decoding; Tascam reads with `CFPreferencesCopyAppValue` |
| Idle apps unspecified | Design: engine only while processes exist |
| `os_log` privacy, no logging in IOProc, ratio windows | Design: debug log rules |
| Sample-rate change on target device | Design: device listeners |
| Re-prompt on updates without local cert | Pitfalls + README |
| Runner glob would pull in AppKit files; `PreferenceKeys` not standalone | T1: explicit file list, keys in `AppAudioSettings.swift` |
| `CoreAudioQuery.swift` owned by T2 but needed by T3 | Moved to T1 |
| GainEngine range 118-230 cut `stop()` | Corrected to 114-262 |


## Progress

- 2026-11-25 (planning session): Xcode 27.2 test setup in place. `run-tests.sh` added; `LocalizationTests` updated for the DuoBar to Status Ring rename (4 keys). Baseline: 328 tests, 0 failures. CP0 still to run.
- 2026-11-25 (build session) CP0: "DuoBar Local Signing" listed by `security find-identity -p codesigning`; `./build-local.sh --no-install` green (2.0.0); `log stream --predicate 'subsystem == "com.jurek.statusring"'` runs. **US-4x4 not connected** (`system_profiler SPAudioDataType` lists MacBook Air Speakers default, BlackHole, aggregates): AC7 stays unverified and CP4 cannot close until Jurek plugs it in. CP1 to CP3 proceed. T1 handed to a Sonnet subagent.
- 2026-11-25 CP1 done (commit 50800d1): T1 PASS, verified by the lead. Files read: settings (lenient decode, clamp, default entries dropped, distributed notification), ownership (rules match Design), grouping (responsible PID, own PID and TascamVolume skipped). `./run-tests.sh`: 342 tests, 6 skipped, 0 failures, exit 0. Red-turn (grouping `pid` instead of `responsible(pid)`): `testGroupingMergesHelpersUnderResponsible` failed "3 is not equal to 2", reverted, green (plans/reports/T1.md). API notes for CP2: `AudioProcessInfo`, `AppGroup`, `HandoffState.inactive`, `AppAudioOwnership.owner(setting:defaultOutputUID:deviceExists:handoff:)`, `AppAudioSettingsStore.load/save/set/remove`. CP2 started: T2 and T3 in parallel.
- 2026-11-25 CP2 part 1 (commit 26a5d3c): T2 PASS, T3 PASS, both files read by the lead. T3 engine: tap = last input buffer (works whether device input streams are listed or not), ramp per buffer, IOProc free of alloc/lock/log. T2 standalone check: afplay merged under its responsible parent (VSCode) `com.microsoft.VSCode 2 1`. Lead check of responsible PID for WebKit helpers: Mail's WebKit.GPU and WebContent resolve to `com.apple.mail`; two other WebKit.GPU processes have non-app parents and would show as `com.apple.WebKit.GPU` rows only if they play. AC1 Safari check in T4 proof decides whether the store must handle that. T4 handed to a Sonnet subagent.
- 2026-11-25 CP2 done: T4 PASS, store and wiring read by the lead. Lead fixes: `taps=` debug line moved before the no-engine early return (else `taps=0` never logs); permission detector guarded by `permission != .granted` (see Design). Installed, `appAudioDebug` on, test source = `afplay` loop (groups under `com.microsoft.VSCode`, the session host), control = Dia playing (`company.thebrowser.dia 3 1`: 3 helper processes merged into one row). Evidence from `/usr/bin/log show` (zsh's `log` builtin shadows the tool):
  - AC2 PASS: `com.microsoft.VSCode target=BuiltInSpeakerDevice gain=0.300 muted=0 in=0.359 out=0.108 ratio=0.30` on every window with signal; `taps=1` (Dia untouched).
  - AC3 PASS (log): `muted=1 in=0.359 out=0.000 ratio=0.00`.
  - AC4 PASS: after `defaults delete ... appAudio`: `taps=0` each second.
  - AC5 PASS (log): `outputUID="BlackHole2ch_UID"` gives `target=BlackHole2ch_UID ... ratio=0.30`; `outputUID="NoSuchDevice_UID"` gives `target=BuiltInSpeakerDevice` and `defaults read` keeps the UID. Original output silent for the routed app: **Jurek to listen** (depends on `mutedWhenTapped`).
  - AC8 PASS (log), audible part **Jurek to listen**: `kill -9` with VSCode at 0.3: no `statusring` device left in the device list; launchd relaunched Status Ring within 1 s and it restored `gain=0.300` (also the Status Ring half of AC6).
  - AC1: grouping proven on Dia (3 processes, 1 row) and afplay under its host; Safari + Music row check moves to CP3 screenshot.
  - `./run-tests.sh` 342 tests, 0 failures; installed build green.
- 2026-11-25 CP3 done + T8 done (CP4 Status Ring side). T5, T6, T8 PASS, diffs read by the lead. Installed and checked live:
  - Screenshots (local only, they show desktop content behind the popover, so not in the public repo): `~/Archive/status-ring/2026-11-25-cp3/` main-dark, main-light (Volume card chevron), panel-dark, panel-light, panel-tapped (Code at 30 %), panel-empty ("No apps are playing audio").
  - AC1 PASS: Dia (3 helper processes) and Code (afplay under its responsible host) listed as one row each with name and icon; after the sound stopped the row was gone within 4 s (panel-empty). Safari + Music not playing during the session: real Safari/WebKit row unverified, WebKit responsible-PID check on Mail passed (CP2 note). Artefact seen: an `afplay` loop spawns a new process every ~1 s, so its row flickers to dimmed between plays; with one long `afplay` the row stays bright, also while tapped. Not a bug for real apps.
  - AC6 partial: an outside `defaults write` moved the slider live; relaunch restored gain 0.300 (CP2). `defaults read com.jurek.statusring appAudio` shows a readable dictionary keyed by bundle ID.
  - AC7 Status Ring side PASS in simulation (TascamVolume keys written by hand, `BuiltInSpeakerDevice` standing in for the US-4x4, notification posted via a Swift one-liner; `notifyutil` does not reach DistributedNotificationCenter): baseline `taps=1 handoff=inactive`; handoff active, app not yet listed: engine kept (`taps=1 handoff=active ... tascamTapped=none`); `perAppTapped=[com.microsoft.VSCode]`: `taps=0 ... tascamTapped=com.microsoft.VSCode`; `perAppEngineRunning=false`: `taps=1 handoff=inactive` and `ratio=0.30` again. Keys deleted afterwards. Real AC7 still needs T7 and the US-4x4.
  - AC9: `@available(macOS 14.2` on AppTapEngine, AppAudioService, AppAudioStore, AppVolumePanelView, TascamHandoffMonitor; disclosure hidden when the store is absent; target `macos13.0`. Unverified on 13 (no machine), compile-gated.
  - AC10 partial: main popover renders and the master Volume, Output, Input, Battery, Network cards are intact in both modes. Volume keys, output/input switching, cmd-drag reorder by hand: **Jurek to confirm**.
  - CPU: Status Ring 0.9 to 1.5 % with one engine running (`ps -o %cpu`).
  - unslop scan: AppVolumePanelView.swift and VolumeStatusRow.swift exit 0, findings 0. `./run-tests.sh` 343 tests, 6 skipped, 0 failures.
  - Open question for Jurek (from the UI brief): switch the popover to Plus Jakarta Sans? Not part of this build.
  - Slider writes settings on every drag tick (UserDefaults write + distributed notification + reconcile). CPU stayed low; revisit only if TascamVolume rereads become noticeable in T7.
- 2026-11-25 CP4 T7 built, CP5 T9 done. T9: README (Class line, App Volume feature, permission, privacy row, quirks incl. `appAudio` format and diagnostics), VERSION 2.1.0, commit a28acbc. T7 in tascam-volume: local commits 912b5bf (auto-commit caught PerAppSettings.swift mid-work) + the T7 commit; `swift build -c release --scratch-path /private/tmp/claude-501/tv-build` green, render path grep clean, scratch buffer preallocated. Deviations by T7 (accepted): default-output listener added in Controller; reconcile compares a signature (pids + per-app set + route) instead of pids only; helper processes matched via responsible PID like Status Ring; max 8 own per-app taps (more stay in the main tap; Status Ring then keeps its own engine because the app never appears in perAppTapped, still correct); DJ apps in `excludedBundlePrefixes` ignore entries. **Not installed** (the running /Applications/TascamVolume.app is the old version) and **not pushed**: AC7, AC8 for TascamVolume, zone 2 and the call-app test need the US-4x4.
- Next session (needs Jurek): plug in the US-4x4; `cd ~/Projects/apps/tascam-volume && ./build.sh` (installs); run AC7 per the Proof table (`TascamVolume --debug` + Status Ring debug log, Music at 30 %, switch default to EMBERTON and back); AC8 kill -9 for both apps; Jurek listens: zone 2, WhatsApp call, routed-app silence on its original output, full level after kill -9; AC10 by hand (volume keys with popover open, output/input switch, cmd-drag reorder). Then `git push` in tascam-volume. Release v2.1.0 of status-ring only after Jurek says yes.
- 2026-11-27 CP4 verified on hardware (US-4x4 connected, default output). TascamVolume installed via `install.sh` (publishes `perAppHandoff=1`, `perAppDeviceUID=AppleUSBAudioEngine:TEAC Corporation:US-4x4:1134100:1,2`, `perAppEngineRunning=1`). Found Status Ring not running: it had been quit normally on 2026-11-25 23:49 ("Termination complete"); the LaunchAgent restarts only on crash; relaunched with `launchctl kickstart`. Test source: one long `afplay` (groups under `com.microsoft.VSCode`), Code at 30 %, TascamVolume as a `--debug` run (agent booted out for the test, restored after). EMBERTON not connected; MacBook Air Speakers used as the non-handoff output.
  - AC7 PASS: US-4x4 default: TascamVolume `app com.microsoft.VSCode gain=0.300 in=0.239`, `perAppTapped=("com.microsoft.VSCode")`, Status Ring `taps=0 handoff=active ... tascamTapped=com.microsoft.VSCode`. Default to MacBook speakers: within 2.5 s Status Ring `taps=1`, `target=BuiltInSpeakerDevice gain=0.300 ratio=0.30`; TascamVolume `Rebuilt tap ... per-app []`, `perAppTapped=()`. Back to US-4x4: TascamVolume taps Code again, Status Ring `taps=0`.
  - AC8 with both apps: `kill -9` Status Ring: launchd relaunched it within 4 s, TascamVolume kept `gain=0.300` throughout. `kill -9` TascamVolume: **bug found**, Status Ring stayed `handoff=active` (no process, no NSWorkspace terminate, no notification), so the app would have played untouched. Fixed with a 1 s watchdog in TascamHandoffMonitor while active (Design). Retest: 2 s after the kill `taps=1 handoff=inactive`, `target=<US-4x4> gain=0.300 ratio=0.30`. Status Ring alone: CP2.
  - `./run-tests.sh` 343 tests, 0 failures. Both agents restored and running; test setting removed. tascam-volume pushed (AC7 and AC8 verified).
  - Still for Jurek's ears: zone 2 plays with a per-app tap active; WhatsApp call without crackle; routed app silent on its original output; AC10 by hand. Release v2.1.0 only after Jurek says yes.
- 2026-11-27 follow-ups requested by Jurek (commits a8acaa3 and the next):
  - Volume card: any click on the card opens App Volume; slider and mute keep their own clicks. Checked with real CGEvent clicks: click on the title opened App Volume; click on the slider (MacBook speakers default) moved volume 31 to 81 and stayed on the main view (volume and output restored).
  - App Volume lists every running regular app (seen: Code, Dia, Finder, Notes; idle ones dimmed). AC1 changed accordingly (see AC1).
  - Reorder (cards and stat tiles share ReorderableStack): slots computed from a size snapshot taken at drag start instead of live frames (the dragged item's live frame contained its own offset: jitter; neighbours' frames were mid-animation: flip-flop), dragged item excluded from the swap animation (it jumped away and sprang back), lift animates on its own, order persisted once on release. Recorded a synthetic cmd-drag (Network past Volume): per-frame monotonic movement, one swap, clean settle; order then restored to network, volume, audioOutput, audioInput, battery, systemStats.
  - Opening motion: popover settles 8 pt down from the menu bar with a 0.96 to 1 scale (spring 0.32 s) on top of the existing fade and blur. Detail panel: content laid out at final size inside the growing surface (revealed, not stretched), fades in 0.1 s behind the growth; cards step back (scale 0.97 + fade). Verified in recorded frames. A first attempt put the content beside the glass surface and it rendered invisible (glass draws above siblings in the container); reverted to content inside the glass.
  - `./run-tests.sh` 343 tests, 0 failures; unslop scan exit 0 on ReorderableStack.swift and StatusPopoverView.swift.
- 2026-11-27 detail zoom (Jurek: "zoom in onto that one setting, depending on where it opens"): matchedGeometryEffect was not producing a match (the surface appeared full size, recorded frames). Replaced by an explicit transition: the detail surface (glass + clip) interpolates between the opened card's frame (from ReorderController.frames, converted to main-content coordinates) and the full panel, corner radius 22 to 26; the content is laid out at final size, pinned to the top and fades in 0.14 s behind the growth; the cards zoom 1 to 1.12 towards the opened card's centre (anchor) and fade; close reverses into the card. Spring 0.46 s, bounce 0.08 (retract wait 0.38 s). Recorded Network (grows from the top), Audio Input (grows out of its mid-panel slot), Audio Input close (shrinks back into its card). Unused matchedGeometryEffect calls removed.
- 2026-11-27 zoom close fix (Jurek: closing always looked the same): the removal transition was overridden by the glass container (removed glass shrank to the centre, recorded at 60 fps). Now state-driven: open places the surface on the card without animation, then animates `detailExpanded`; close animates the surface back onto the card while the cards zoom back out, then removes it without animation after 0.42 s. Recorded: Network close shrinks upward into the top card; Audio Input open and close grow from and collapse into its mid-panel slot.
- 2026-11-27 volume dots follow external controllers (Jurek): generic contract `com.jurek.statusring.externalVolume` (userInfo controller, deviceUID, level, muted; request `...externalVolumeRequest`), ExternalVolumeMonitor in Status Ring applies it when the default output has no settable volume and the controller runs (2 s watchdog). TascamVolume posts it on level/mute change, start, handoff republish and request. Verified: card 69 % at Tascam level 0.6875 (was "-"), dots 3 of 4; six volume-down keys gave level 0.3125 and 2 dots; six up restored 0.6875 and 3 dots.
- 2026-11-27 title flight (Jurek: headline stays visible and moves into the panel, options pop in): cards and panels mark their titles (`cardTitle`, `panelTitle`, DetailTitleFlight.swift); one flying copy drawn above the glass container (glass draws above siblings inside it) moves from the card title to the header (42, 17) and back on close, cross-fading wording that differs (Volume to App Volume, Network to Wi-Fi); real titles hidden during the flight. Measurements only at rest (cards report scaled frames while zooming, the header transient frames mid-pop; logged and fixed). Options fade in from transparent with an 8 pt rise. Recorded Volume open and Audio Input close.
