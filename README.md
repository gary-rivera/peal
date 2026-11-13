# Tickle

Menu bar interval timer for macOS. Plays N rapid ticks at the Nth interval
mark of a time window (1st mark = 1 tick, 2nd = 2, …), a "Pop" when a
scheduled timer begins, and a double "Glass" chime when the window ends.
Built for keeping track of elapsed time in interviews without watching a
clock. Multiple timers can run or be scheduled at once; settings persist
via UserDefaults (`com.garyrivera.tickle`).

Perpetuity mode drops the window and ticks forever: marks anchor to the
clock hour (with a 10-minute interval, one tick at :10, two at :20, … five
at :50), a "Submarine" bong at the top of each hour resets the count, and
the timer runs until stopped by hand. Start one instantly from the menu's "Start in
perpetuity" item, or toggle the Timed/Perpetuity segment on the config
panel's window row.

A global tick-volume slider lives in both the menu (for quick adjustment
while timers run) and the New Timer panel; it scales every Tickle sound
and releasing it plays one tick as a loudness preview.

Menu bar shows the featured timer's progress as marks-elapsed/total-marks
(e.g. `3/9`), `in 4:32` for the next scheduled timer, or `✓` when all
timers are done.

## Build & install

```sh
./build.sh    # compiles Tickle.swift, assembles Tickle.app, installs to /Applications
```

Requires Xcode command line tools (`swiftc`). Targets macOS 13+.

## Dev loop (no bundle)

```sh
swiftc -O Tickle.swift -o tickle && ./tickle    # quit from the menu, or: pkill tickle
```

Note: run bare, the bundled feather menu icon isn't found, so it falls
back to the SF Symbols metronome — expected.

## Layout

- `Tickle.swift` — the whole app (AppKit, single file)
- `build.sh` — build + install script; also generates Info.plist
- `assets/` — app icon (`Tickle.icns`, compiled from `Tickle.iconset/`,
  source art `Tickle.png`) and the menu bar template image (`MenuIcon.png`)

To regenerate the icns after editing the iconset:
`iconutil -c icns assets/Tickle.iconset -o assets/Tickle.icns`
