<p align="center"><img src="docs/menubar.png" width="112" alt="Status Ring in the menu bar"></p>

# Status Ring

**Battery, network and volume in one tiny menu bar glyph, because your menu bar is not a parking lot.**

[![License](https://img.shields.io/badge/license-MIT-black)](LICENSE) ![Platform](https://img.shields.io/badge/macOS-13%2B-black) [![Release](https://img.shields.io/github/v/release/krosta-codes/status-ring)](https://github.com/krosta-codes/status-ring/releases)

## Why this exists

My menu bar had a battery icon, a Wi-Fi icon, a volume icon and a system monitor, all fighting the notch for space. [DuoBar](https://github.com/Mikeli7666/DuoBar) by Mike Li had the right idea: pack the essentials into one glyph. Status Ring is my fork of it, tuned to how I read it at a glance, with CPU and memory folded in so I could delete my separate system monitor app.

## What it does

- **Ring:** battery level. Charging adds a bolt and turns green; full on the adapter is a closed green ring.
- **Center:** Wi-Fi, Ethernet or offline.
- **Four dots:** output volume.
- **Desktop Macs** (no battery) get the Adaptive Ring, which shows system load instead.
- **Click it** for a popover: battery details, network speed, nearby Wi-Fi, audio output and input switching, volume and brightness, CPU, memory and storage tiles. Cards can be reordered.
- While the popover is open, the volume keys move its slider instead of popping the system overlay (needs Accessibility).

## Install

| You need | Why |
|---|---|
| macOS 13 or newer | SwiftUI APIs the app uses |
| Xcode Command Line Tools | builds the app; no full Xcode needed |

1. Clone and run the installer:

   ```
   git clone https://github.com/krosta-codes/status-ring.git ~/Projects/apps/status-ring
   ~/Projects/apps/status-ring/install.sh
   ```

   It checks your Mac, builds with `swiftc`, installs to `/Applications` and starts the app.

2. Popover › Settings › **Launch Status Ring at login**.

3. Optional, saves re-granting Location and Bluetooth after every update: create a local signing certificate once. Keychain Access › Certificate Assistant › Create a Certificate…, name `<Your name> Local Signing`, Identity Type "Self-Signed Root", Certificate Type "Code Signing". Run `install.sh` again.

Permissions it may ask for: **Location** (macOS only reveals the Wi-Fi network name to apps with it), **Bluetooth** (recognises Bluetooth audio devices), **Accessibility** (volume keys, optional).

## Updates

Status Ring checks this repo's releases 30 s after start and once a day. A new version puts **Update to vX.Y.Z** in the popover footer; it pulls your clone, rebuilds and restarts. Settings › General has **Check now** and the daily-check toggle.

The check is one request to the GitHub API and nothing else. Turn it off in Settings, or `defaults write com.jurek.statusring updateCheck -bool false`.

## Build by hand

```
./build-local.sh               # build, install to /Applications, restart
./build-local.sh --no-install  # build only, into build/StatusRing.app
```

The macOS 27 SDK needs Xcode's SwiftUI macros, so the script picks the newest 26.x (or older) SDK from the Command Line Tools. Override with `SDK=/path/to/MacOSX.sdk`. Version lives in `VERSION`.

## Privacy

| What | Where it goes |
|---|---|
| Battery, network, audio, system stats | read locally, never sent anywhere |
| Wi-Fi name (Location permission) | used for display only |
| Update check | one request to api.github.com, no data about you |

## Known quirks

- Without Location permission the Wi-Fi name shows as hidden. That's macOS, not us. Promise.
- The source folders are still called `DuoBar`. Renaming 100 files buys nothing and makes merging upstream fixes harder.
- Built without Xcode, so the asset catalog is precompiled in `assets/`. Change the icon there, not in `Assets.xcassets`.

## Credits

Status Ring is a fork of [DuoBar](https://github.com/Mikeli7666/DuoBar) by Mike Li and contributors, released under the MIT License. Their copyright notice is kept in [LICENSE](LICENSE). All the hard Core Audio, IOKit and CoreWLAN work is theirs; the ring tweaks, system stats and the no-Xcode build are mine.

---

Built by [Jurek Krosta](https://jurekkrosta.com) ("AI Slop - aber richtig").
Need this built for your shop or team? [Contact](https://jurekkrosta.com).
