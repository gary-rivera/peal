import AppKit
import PealCore

/// Plays macOS system sounds at the global tick volume.
@MainActor
final class SoundPlayer {
    private static let directory = "/System/Library/Sounds"

    /// The tick-volume slider IS the output level: 1 plays samples at full
    /// NSSound volume (which still tops out at the Mac's output volume).
    var volume: Double = 1
    // Hold references so sounds aren't deallocated mid-playback.
    private var playing: [NSSound] = []

    static func availableSounds() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory))?
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted() ?? []
        return names.isEmpty ? [TimerSettings.defaultSound] : names
    }

    /// A timer event's sound: Pop at a scheduled start, N ticks at the Nth mark,
    /// a Submarine bong at perpetuity's top of the hour, and a double Glass
    /// chime as the window-end stop signal.
    func play(_ event: TickTimer.Event, tickSound: String) {
        switch event {
        case .started: play("Pop")
        case .ticks(let count): play(tickSound, times: count, gap: 0.2)
        case .hourReset: play("Submarine")
        case .finished: play("Glass", times: 2, gap: 0.6)
        }
    }

    func play(_ name: String, times: Int = 1, gap: TimeInterval = 0) {
        playing.removeAll { !$0.isPlaying }
        for i in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * gap) { [weak self] in
                guard let self,
                      let sound = NSSound(contentsOfFile: "\(Self.directory)/\(name).aiff", byReference: true)
                else { return }
                sound.volume = Float(volume)
                playing.append(sound)
                sound.play()
            }
        }
    }
}
