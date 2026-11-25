# Per-app volume and output routing in Status Ring

Repo: `~/Projects/apps/status-ring` (fork of DuoBar, Swift, built with `swiftc` from the Command Line Tools, no Xcode). Second repo touched in checkpoint 4: `~/Projects/apps/tascam-volume`.

## Goal and done

**User story:** As Jurek, I open the Status Ring popover, tap into the Volume card and see every app that is playing audio right now. Each app has its own slider (0 to 100 %), a mute toggle and an output picker. One app can be quieter than the rest, or go to a different speaker, and the setting comes back the next time that app plays. On the TASCAM US-4x4, the per-app gains are applied by TascamVolume inside its existing tap, so each app is only ever tapped once.

Decisions agreed with Jurek on 2026-11-25:
- Scope: slider and mute per app, per-app output device, settings remembered per bundle ID. **No boost above 100 %.**
- On the US-4x4: **hand off.** Status Ring writes the per-app settings; TascamVolume applies gain and mute in its IOProc. On every other output, Status Ring runs its own taps.
- Class: `public · Mac · AI: no · rung 2` (public GitHub repo with releases). STANDARD.md section 0: Mac only, so sections 2, 3, 6, 7, 8 and 11 do not apply. The `.icns` icon already exists (`assets/AppIcon.icns`).

**Acceptance criteria (each is a checkable fact):**
1. AC1 List: with Music and Safari both playing, the App Volume panel shows one row each, with the app's name and icon. Helper processes (e.g. `com.apple.WebKit.WebContent`, Chrome Helper) are listed under their parent app, not as separate rows. An app that stops playing disappears from the list within 3 s, unless it has saved non-default settings (then it stays, dimmed).
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

### Pitfalls known up front

- `NSAudioCaptureUsageDescription` must be in `assets/Info.plist`, or tap creation fails silently with a permission error. The first tap triggers the TCC prompt. Signing with "DuoBar Local Signing" keeps the grant across rebuilds; an ad-hoc build re-prompts every time.
- The macOS 27 SDK needs Xcode's SwiftUI macros; keep using the 26.x SDK that `build-local.sh` picks. `CATapDescription` is in the 26.x SDK. Gate with `@available(macOS 14.2, *)`, the target stays `macos13.0`.
- No XCTest in the Command Line Tools: the existing `DuoBarTests/` cannot run here. New tests use a small `swiftc` runner (CP1).
- Never tap TascamVolume itself, and never let two Status Ring engines tap the same process.
- Call apps (WhatsApp, FaceTime, Zoom) run on the mic clock: drift compensation is on for every Status Ring tap, so they are safe. On the TascamVolume side, a per-app tap for a call app needs drift compensation too (match `callBundlePrefixes`).
- The IOProc runs on a real-time thread: no allocation, no locks, no Swift arrays grown inside it. Copy the `UnsafeMutablePointer<Float>` shared-state pattern from `GainEngine`.

## Tasks

Each task owns its files. No two tasks in one checkpoint share a file.

### CP1: model and tests

- **T1 Models + test runner** (one subagent)
  - Files (new): `DuoBar/Models/AppAudioSettings.swift`, `DuoBar/Models/AppAudioOwnership.swift`, `DuoBar/Models/AppAudioGrouping.swift`, `tools/tests/AppAudioTests.swift`, `tools/run-tests.sh`. Edit: `DuoBar/Utilities/PreferenceKeys.swift` (add `appAudio`, `appAudioDebug`).
  - `AppAudioSettings`: struct `AppAudioSetting { volume: Double; muted: Bool; outputUID: String? }`, `isDefault`, plist dictionary encode and decode (`[String: Any]`), a `AppAudioSettingsStore` that reads and writes `UserDefaults` key `appAudio`, drops default entries on write, clamps volume to 0...1, and posts `com.jurek.statusring.appAudioChanged` via `DistributedNotificationCenter` after writing (injectable poster for tests).
  - `AppAudioOwnership`: pure function from the design section.
  - `AppAudioGrouping`: pure function `group(processes: [(pid, bundleID, isPlaying, objectID)], responsible: (pid) -> pid, ownPID:) -> [AppGroup]`, skipping own PID and `com.jurek.tascamvolume`.
  - Only Foundation and CoreAudio types in these files (no AppKit), so the runner compiles them alone.
  - `tools/run-tests.sh`: `swiftc -sdk <same SDK pick as build-local.sh> -parse-as-library DuoBar/Models/AppAudio*.swift DuoBar/Utilities/PreferenceKeys.swift tools/tests/AppAudioTests.swift -o build/app-audio-tests && build/app-audio-tests`. The test file has a `@main` that runs named cases with a tiny `expect(_:_:)` helper, prints `PASS name` / `FAIL name: detail`, exits non-zero on any failure.
  - Cases: default entry dropped on write; clamp; round trip through a scratch `UserDefaults(suiteName: "statusring.tests")`; ownership table (untouched, follow default to non-handoff device, follow default to handoff device = tascam, explicit route to handoff device = statusRing, missing route device = fallback to default, handoff inactive = statusRing); grouping (helpers merged under responsible PID, own PID skipped, TascamVolume skipped, not-playing app without settings dropped by the caller flag).
  - Proof: `tools/run-tests.sh` exits 0; `./build-local.sh --no-install` still builds.

### CP2: engine and discovery (waits for CP1: uses its types)

- **T2 AppAudioService** (subagent A, parallel with T3: different files)
  - File (new): `DuoBar/Services/AppAudioService.swift`, `DuoBar/Utilities/CoreAudioQuery.swift` (copy of TascamVolume `CoreAudioHelpers.swift`, enum renamed `CAQuery`).
  - Listener pattern from `AudioOutputService.swift` (`ListenerRegistration`), grouping from `AppAudioGrouping`, responsible PID via `dlsym`.
  - Proof: a hidden launch flag `StatusRing --list-audio-apps` prints the current groups as `bundleID pid-count playing` and exits; with Music playing it prints `com.apple.Music 1 1`. Add the flag handling in this file as a static func; T4 calls it from `AppDelegate`.
- **T3 AppTapEngine** (subagent B)
  - File (new): `DuoBar/Services/AppTapEngine.swift`.
  - From the design section; copy from `GainEngine.swift:118-230` and `264-end`. API: `init(bundleID:, processObjects:, targetUID:)`, `start() throws`, `stop()`, `var gain: Float` (target), `var muted: Bool`, `var peaks: (input: Float, output: Float)`, `var isRunning`.
  - Proof: compiles inside `./build-local.sh --no-install`. Functional proof comes in T4's check.
- **T4 Store + wiring** (after T2 and T3; lead hands it to one subagent)
  - Files: new `DuoBar/Models/AppAudioStore.swift`; edit `DuoBar/App/AppDelegate.swift` (create and stop the store, `--list-audio-apps` flag), `assets/Info.plist` (add `NSAudioCaptureUsageDescription`: "Status Ring reads an app's audio only to change its volume or send it to another output.").
  - Debug log: when `appAudioDebug` is true, log once per second per engine via `os_log` (subsystem `com.jurek.statusring`, category `appAudio`): `bundleID target=<uid> gain=<g> in=<peak> out=<peak> ratio=<out/in>`, plus `taps=<n>` overall.
  - Until CP3, settings are set from the command line: `defaults write com.jurek.statusring appAudio -dict-add com.apple.Music '{volume=0.3;}'`. A `defaults write` from outside does not reliably fire `UserDefaults.didChangeNotification` in the running app, so the store also rereads `appAudio` once per second while `appAudioDebug` is true (debug only).
  - Proof (lead runs): AC2, AC3, AC4, AC5, AC8 via the debug log (see Proof).

### CP3: UI (waits for CP2: binds to `AppAudioStore`)

- **T5 App Volume panel** (subagent A, parallel with T6)
  - File (new): `DuoBar/UI/AppVolumePanelView.swift`. Structure copied from `AudioDevicePanelView` in `DuoBar/UI/AudioOutputRow.swift`. Rows, mute, slider, output `Menu`, Reset context menu, empty state, permission-denied state, footer.
  - Proof: builds; screenshot in CP3 check.
- **T6 Volume card disclosure + popover detail + strings** (subagent B)
  - Files: `DuoBar/UI/VolumeStatusRow.swift` (optional `onShowApps: (() -> Void)?`, trailing chevron button shown only when non-nil, accessibility label "App Volume"), `DuoBar/MenuBar/StatusPopoverView.swift` (accept optional `AppAudioStore`, `PopoverDetail.apps`, `matchedGeometryEffect` on the volume row, `detailPanel` case), all six `Localizable.strings` (new keys: "App Volume", "No apps are playing audio", "Follow default", "Reset", "Allow System Audio Recording", the permission line; translate for ru, th, uk, zh-Hans, zh-Hant), and the `StatusPopoverView(...)` call site wherever it is constructed (`grep -rn "StatusPopoverView(" DuoBar`).
  - Proof: builds; `grep -c` of each new key is 1 in every `.lproj`.

### CP4: TascamVolume handoff (waits for CP2; can run parallel with CP3, different repo)

- **T7 TascamVolume per-app gains** (one subagent, repo `~/Projects/apps/tascam-volume`)
  - Files: `Sources/TascamVolume/GainEngine.swift`, `Sources/TascamVolume/Controller.swift`, `README.md`.
  - Read Status Ring's `appAudio` via `UserDefaults(suiteName: "com.jurek.statusring")` after `CFPreferencesAppSynchronize`; observe `com.jurek.statusring.appAudioChanged`.
  - In `currentExclusions()`: apps whose bundle has an entry **with** `outputUID` → excluded from the main tap, no tap of their own (Status Ring handles them). Apps whose entry has **no** `outputUID` → excluded from the main tap and get their own tap (`CATapDescription(processes: [objects], …)`, `mutedWhenTapped`, drift compensation only for call bundles), appended to the aggregate's tap list.
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
| 1 | Settings, ownership, grouping, tested | T1 | `tools/run-tests.sh` exit 0, plus each red-turn in Proof. |
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

Verification path: this is a native menu bar app, so there is no browser check. Proof is (1) the `swiftc` test runner for the pure logic, (2) the debug log of the real engines with real audio, (3) screenshots of the popover via `screencapture -l<windowid>` or `screencapture -R`, (4) Jurek listening for the audible checks (zone 2, call quality), which the lead asks for explicitly and records.

Test audio: `afplay -v 1 /System/Library/Sounds/Submarine.aiff` in a loop gives a process with a known bundle (`afplay` has none: use Music.app with any local track, and Safari with a YouTube tab, as the two real apps).

| AC | Test | Red-turn (make it, see it fail, undo with the exact reverse edit) |
|---|---|---|
| AC1 | `StatusRing --list-audio-apps` with Music + Safari playing lists exactly `com.apple.Music` and `com.apple.Safari` (no WebContent row); panel screenshot. Runner case `grouping merges helpers`. | In `AppAudioGrouping`, use `pid` instead of `responsible(pid)`: the runner case fails. |
| AC2 | `defaults write … com.apple.Music '{volume=0.3;}'`; log shows `com.apple.Music … ratio=0.30` (±0.02) and Safari has no engine. | In `AppTapEngine` render, skip the gain multiply: ratio reads 1.00. |
| AC3 | `{muted=1;}`: log `out=0.000`, Safari still audible. | Mute maps to gain 1 instead of 0: out ≠ 0. |
| AC4 | Entry removed: `taps=0` in the log. Runner case `ownership untouched`. | Ownership returns `.statusRing` for no entry: runner fails, log shows `taps=1`. |
| AC5 | `{outputUID="<MacBook speakers UID>";}` with EMBERTON default: sound only from the MacBook. Then switch the MacBook speakers off by choosing a non-existing UID: falls back to EMBERTON; `defaults read` still shows the UID. Runner case `ownership missing route falls back`. | Fallback returns nil target: runner fails. |
| AC6 | Quit Music and Status Ring, relaunch both, play: the log shows the saved gain within 3 s. Runner case `settings round trip`. | Drop the `outputUID` key in encode: round trip fails. |
| AC7 | US-4x4 default, TascamVolume running with `--debug`: its log shows `app com.apple.Music gain=0.30`, Status Ring log shows no engine for Music and `handoff=active`. Switch default to EMBERTON: within 2 s Status Ring log shows the Music engine, TascamVolume rebuilds without the per-app tap. Runner case `ownership follow default to handoff device`. | Ownership ignores handoff: runner fails, and both logs show a Music tap. |
| AC8 | `kill -9 $(pgrep -x StatusRing)` while Music is at 30 %: Music back at full level on its original output (Jurek listens, or `TascamVolume --debug` input peak for Music returns to the unscaled level). Restart via `open /Applications/StatusRing.app`. | none (property of macOS). |
| AC9 | `grep -n "@available(macOS 14.2" DuoBar` covers `AppTapEngine`, `AppAudioService`, `AppAudioStore`, `AppVolumePanelView`; build still targets `macos13.0` (`grep -n macos13.0 build-local.sh`). No macOS 13 machine available: mark "unverified on 13, compile-gated" in Progress. | Remove one `@available`: build fails with an availability error. |
| AC10 | Manual pass with the installed app: master slider, volume keys with popover open, output switch, input switch, ⌘-drag reorder, the network detail panel. Screenshot. | none. |

Whole-build checks before CP5: `tools/run-tests.sh` exit 0; `./build-local.sh` green and installed; `python3 ~/.claude/skills/unslop-ui/scripts/devibe_scan.py DuoBar/UI/AppVolumePanelView.swift --severity high` exit 0 (if the scanner does not handle Swift, note "scanner n/a for Swift" and do the unslop checklist by hand on the screenshot); TascamVolume `build.sh` green; Activity Monitor CPU for Status Ring with two engines running < 3 %.

Done means: every AC either proven with evidence in Progress or explicitly marked "unverified" with the reason. An unverified AC7 or AC8 blocks the push of `tascam-volume`.

## Review findings

(filled in by the plan review before handover)

## Progress

(empty; the running session records state here)
