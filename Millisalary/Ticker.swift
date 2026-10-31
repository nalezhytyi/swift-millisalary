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
        // The common modes keep it ticking during a live resize and while a
        // menu is open
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Clock.now }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}
