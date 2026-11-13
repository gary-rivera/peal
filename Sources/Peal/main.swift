// Peal — menu bar interview timer.
//
// Menu bar shows a bell icon (filled while a timer is active) plus the
// featured timer's progress as "marks elapsed / total marks" (e.g. "3/9" for
// the 3rd of 9 interval marks in the window), "in 4:32" for the next scheduled
// timer, or "✓" when all timers have finished. "+N" marks additional timers.
//
// Each timer plays N rapid ticks at its Nth interval mark (1st mark = 1 tick,
// 2nd = 2, ...), a "Pop" when a scheduled timer begins, and stops itself with
// a double "Glass" chime when its time window ends.
//
// Perpetuity mode trades the window for the clock: marks anchor to the hour
// (:10, :20, … for a 10m interval), a "Submarine" bong at :00 resets the
// count, and the timer ticks forever until stopped by hand.
//
// Menu:
//   Start timer         open the configuration panel.
//   Start in perpetuity  begin an endless clock-anchored timer right away.
//   Play sample ticks   preview a 3-tick burst of the configured sound.
//   Tick volume         slider scaling every Peal sound; shared with the
//                       config panel's slider and persisted.
//   <timer list>        rich custom rows grouped under section headers with a
//                       state dot and live count pill — Ongoing, Upcoming,
//                       Finished. Each row: colored accent dot, bold primary
//                       line (elapsed of window / start time), a badge
//                       ("3 / 9 ticks", "in 4:32"), a tick-marked progress
//                       track with fired marks lit and a live playhead, and a
//                       dimmed config line. Stop/Reset surface inline on hover.
//   Stop all            persistent footer button. Individual rows keep their
//                       hover Reset for removing a single timer.
//
// Configuration panel:
//   ± steppers with sec/min/hr unit segments for interval and window, a
//   Timed/Perpetuity mode segment on the window row, a live
//   "Interval time preview" timeline (every mark drawn as an escalating bar
//   stack, red when the window overflows the 9-mark ceiling, with an in-place
//   plain-language fix), a tick sound popup with ▶ preview, a tick volume
//   slider (global, mirrored in the menu), and a unified
//   start flow: a "Start now / At a time" segment feeding one primary button.
//   The button is disabled while the configuration is invalid.
//
// Config values persist across launches (UserDefaults) as defaults for the
// next timer; each launched timer keeps the settings it was started with.
//
// Build:  ./build.sh         (or for development: swift run Peal)
// Quit from the menu, or: pkill Peal

import AppKit

MainActor.assumeIsolated {
    NSMenuItem.disableIcons()
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
    withExtendedLifetime(delegate) { app.run() }  // app.delegate is weak
}
