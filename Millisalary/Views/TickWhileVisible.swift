import AppKit
import SwiftUI

/// Runs the Ticker while the window it's in can be seen: not while it's
/// closed, minimised or covered
struct TickWhileVisible: NSViewRepresentable {
    @Environment(Ticker.self) private var ticker

    func makeNSView(context: Context) -> WindowView {
        WindowView(ticker: ticker)
    }

    func updateNSView(_ view: WindowView, context: Context) {}

    final class WindowView: NSView {
        private let ticker: Ticker
        private var observer: NSObjectProtocol?

        init(ticker: Ticker) {
            self.ticker = ticker
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            guard let window else {
                ticker.isRunning = false
                return
            }
            observer = NotificationCenter.default.observe(NSWindow.didChangeOcclusionStateNotification, object: window) {
                [weak self] in self?.update()
            }
            update()
        }

        private func update() {
            ticker.isRunning = window?.occlusionState.contains(.visible) ?? false
        }
    }
}
