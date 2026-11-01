import Foundation
import Observation

/// The time the window's amounts are computed for, every 100 ms (the dial
/// shows four decimals) while the window is on screen. Views that read
/// `now` are the only ones redrawn on a tick
@Observable
final class Ticker {
    private(set) var now = Clock.now

    @ObservationIgnored private var timer: Timer?

    var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            isRunning ? start() : stop()
        }
    }

    private func start() {
        now = Clock.now
        timer = .repeating(every: 0.1, tolerance: 0.02) { [weak self] in self?.now = Clock.now }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}
