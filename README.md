# Peal

Menu bar interval timer for macOS. Plays N rapid ticks at the Nth interval
mark of a time window (1st mark = 1 tick, 2nd = 2, …), a "Pop" when a
scheduled timer begins, and a double "Glass" chime when the window ends.
Built for keeping track of elapsed time in interviews without watching a
clock. Multiple timers can run or be scheduled at once; settings persist
via UserDefaults (`com.garyrivera.peal`).

Perpetuity mode drops the window and ticks forever: marks anchor to the
clock hour (with a 10-minute interval, one tick at :10, two at :20, … five
at :50), a "Submarine" bong at the top of each hour resets the count, and
the timer runs until stopped by hand. Start one instantly from the menu's "Start in
perpetuity" item, or toggle the Timed/Perpetuity segment on the config
panel's window row.

A global tick-volume slider lives in both the menu (for quick adjustment
while timers run) and the New Timer panel; it scales every Peal sound
and releasing it plays one tick as a loudness preview.

Menu bar shows the featured timer's progress as marks-elapsed/total-marks
(e.g. `3/9`), `in 4:32` for the next scheduled timer, or `✓` when all
timers are done.

## Build & install

```sh
./build.sh    # swift build -c release, assembles Peal.app, installs to /Applications
```

Requires Xcode command line tools (Swift 6 toolchain). Targets macOS 13+.

## Dev loop (no bundle)

```sh
swift run Peal    # quit from the menu, or: pkill Peal
```

## Layout

- `Package.swift` — Swift package (Swift 6 language mode)
- `Sources/PealCore/` — Foundation-only domain logic, no AppKit
  - `TimerConfig` — interval + `TimerMode` (timed window or perpetual),
    mark count/positions, clock-hour math
  - `TickTimer` — one timer's lifecycle; `advance(now:)` returns events
    (start, ticks, hour reset, finish) that the app turns into sounds
  - `ConfigIssue` — validation, shared by the config panel and start alert
  - `TimerSettings` — the panel's persisted choices (typed UserDefaults keys)
  - `Formatting` — clock / duration strings
- `Sources/Peal/` — the AppKit app
  - `main.swift` — entry point (app overview lives in its header comment)
  - `App/` — `AppDelegate`, legacy-defaults migration, menu icon suppression
  - `UI/Theme/` — design tokens, `FlippedView`, drawing helpers
  - `UI/Controls/` — config panel controls, one per file
  - `UI/Config/` — `TimelineCard` (interval preview)
  - `UI/Menu/` — menu row views
- `Tests/PealCoreTests/` — Swift Testing suite for PealCore (`swift test`)
- `build.sh` — build + install script; also generates Info.plist
- `assets/` — app icon (`Peal.icns`, compiled from `Peal.iconset/`,
  source art `Peal.png`). The menu bar uses the SF Symbols bell
  (`bell` idle, `bell.fill` while a timer is active).

To regenerate the icns after editing the iconset:
`iconutil -c icns assets/Peal.iconset -o assets/Peal.icns`
