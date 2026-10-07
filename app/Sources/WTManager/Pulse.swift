import AppKit
import Combine
import Foundation

/// The animation clock, deliberately not part of the store.
///
/// The tick used to be `@Published` on `Store`, which every view in the window
/// observes — so moving a tail invalidated the whole tree, fifty-odd rows and
/// all, twice a second. A clock of its own means only the two views that
/// actually draw Wity are woken by it.
///
/// It runs at 0.22s rather than the old 0.55s because the blink needs the
/// finer grain: an eye held shut for half a second is not a blink, it is a
/// wince. The wag takes every third tick, so it still turns over at about two
/// thirds of a second a frame — the tail's speed did not change, only the
/// resolution underneath it.
@MainActor
final class Pulse: ObservableObject {
    static let shared = Pulse()

    @Published private(set) var tick = 0
    private var timer: Timer?

    static let interval: TimeInterval = 0.22
    /// Ticks per animation frame. Two, not three: the art went from four
    /// frames to eight so a pose could be *held* for a beat, and at three
    /// ticks each that is a five-second loop — long enough that nobody sees
    /// the same character twice. 0.44s a frame puts a full cycle at three
    /// and a half seconds, which is a breeze in a tree and a chicken that
    /// pecks about as often as a chicken does.
    static let wagEvery = 2
    /// One full blink cycle, and the two ticks in it where the eyes are shut:
    /// a double blink and then a long look, because a single evenly-spaced
    /// blink reads as a metronome and a pair followed by a pause is what an
    /// idle face actually does.
    ///
    /// Blinking is the whole of the idle animation. A periodic glance aside
    /// was tried and removed: the eyes are two pixels wide, so "looking" is
    /// one white pixel moving one column, which at rest reads less as a
    /// glance than as a flicker — and it competes with the expression, which
    /// is the channel that is actually carrying something.
    ///
    /// Not tick 0. A clock that has never been started sits at 0 — which is
    /// exactly the state the offscreen snapshot renders in — and a character
    /// whose every portrait has its eyes shut is one nobody can see the face
    /// of.
    static let blinkCycle = 64
    static let blinkAt: Set<Int> = [13, 15]

    var blinking: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && Self.blinkAt.contains(tick % Self.blinkCycle) }

    var wag: Int { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : tick / Self.wagEvery }

    /// The one name the menu bar listens on. AppKit draws the status item by
    /// hand, so it cannot observe the clock the way a SwiftUI view does — but
    /// it must not run a second timer of its own either, or the tail in the
    /// menu bar and the tail in the window drift apart within a minute.
    static let tickNote = Notification.Name("wtmanager.tick")

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick += 1
                NotificationCenter.default.post(name: Pulse.tickNote, object: nil)
            }
        }
    }
}
