# Status Ring

One menu bar glyph for battery, network and volume on macOS.

- **Ring:** battery level. Charging shows a bolt and turns green; full on the adapter is a closed green ring.
- **Center:** Wi-Fi, Ethernet or offline.
- **Four dots:** output volume.
- Popover with battery, network speed, audio output and system stats.

## Build

Needs the Command Line Tools (no Xcode):

```sh
./build-local.sh   # builds build/StatusRing.app, installs to /Applications, restarts it
```

A LaunchAgent (`~/Library/LaunchAgents/com.jurek.statusring.plist`) starts it at login.

## Credits

Status Ring is a fork of [DuoBar](https://github.com/Mikeli7666/DuoBar) by Mike Li, released under the MIT License. The original notice is kept in [LICENSE](LICENSE).

Built by [Jurek Krosta](https://jurekkrosta.com).
