import AppKit
import Observation
import SwiftUI

/// The launch splash (splash.ts in the Electron app): the face at 96 pt
/// over the window plays one cycle of its animation, then flies onto the
/// dial's face while the background dissolves. A click skips the rest of
/// the cycle; under Reduce Motion the still face shows for 0.8 s and fades;
/// it fades too when the window opens on Breakdown or Settings. Only once,
/// at launch, and not when the app was started at login
@Observable
final class SplashModel {
    enum Phase {
        case showing, flying, fading, done
    }

    private(set) var phase = Phase.showing
    private(set) var backgroundOpacity = 1.0
    /// The toolbar's title and sidebar button are drawn above any overlay,
    /// so they're taken out while the splash covers the window, and put
    /// back before it lifts
    private(set) var hidesToolbarItems = true
    /// The dial's face, in the window's coordinates (top-left origin), once
    /// it has been laid out
    var dialFaceFrame: CGRect?
    /// Measures the dial's face now. Its reports only come when its own
    /// frame changes, not when the content around it moves (as it does when
    /// the toolbar's items come back), so the flight measures it afresh
    @ObservationIgnored var measureDialFace: (() -> CGRect?)?
    @ObservationIgnored private var skipped = false
    @ObservationIgnored private var started = false

    private static let cycle: TimeInterval = 3
    private static let reducedMotionHold: TimeInterval = 0.8
    private static let dialTimeout: TimeInterval = 2
    private static let flight: TimeInterval = 0.5
    private static let backgroundFade: TimeInterval = 0.3
    private static let reducedMotionFade: TimeInterval = 0.2
    /// Putting the toolbar's items back makes the toolbar taller and moves
    /// the window's content down: the flight waits for that layout
    private static let toolbarSettle: TimeInterval = 0.15

    var isVisible: Bool { phase != .done }

    /// The dial's own face stays hidden while the splash's flies onto it
    var hidesDialFace: Bool { phase == .showing || phase == .flying }

    /// No splash this launch
    func cancel() {
        phase = .done
        hidesToolbarItems = false
    }

    func skip() {
        skipped = true
    }

    /// Runs the splash once its view is on screen
    func run(face: FaceAnimation, reduceMotion: Bool, opensOnDial: @escaping () -> Bool) {
        guard !started, phase != .done else { return }
        started = true

        Task {
            if reduceMotion {
                await wait(Self.reducedMotionHold) { self.skipped }
            } else {
                // The cycle starts from frame 0 once every frame is ready
                await wait(5) { face.isLoaded }
                face.epoch = .now
                await wait(Self.cycle) { self.skipped }
            }

            // Under the still opaque splash, so the content's move isn't seen
            hidesToolbarItems = false
            await wait(Self.toolbarSettle) { false }
            if let frame = measureDialFace?() {
                dialFaceFrame = frame
            }
            if !reduceMotion, opensOnDial() {
                await wait(Self.dialTimeout) { self.dialFaceFrame != nil }
            }
            if !reduceMotion, opensOnDial(), dialFaceFrame != nil {
                withAnimation(.easeOut(duration: Self.backgroundFade)) {
                    backgroundOpacity = 0
                }
                withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: Self.flight)) {
                    phase = .flying
                }
                await wait(Self.flight) { false }
            } else {
                withAnimation(.linear(duration: Self.reducedMotionFade)) {
                    phase = .fading
                }
                await wait(Self.reducedMotionFade) { false }
            }
            phase = .done
        }
    }

    /// Waits up to `seconds`, or until `done` says so
    private func wait(_ seconds: TimeInterval, until done: () -> Bool) async {
        let end = Date.now.addingTimeInterval(seconds)
        while Date.now < end, !done() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// The splash over the whole window, sidebar and toolbar included
struct SplashView: View {
    @Environment(SplashModel.self) private var splash
    @Environment(FaceAnimation.self) private var face
    @Environment(Navigation.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the overlay itself sits in the window, to place the face in
    /// the window's coordinates
    @State private var origin = CGPoint.zero

    var body: some View {
        GeometryReader { proxy in
            let rect = faceRect(in: proxy.size)

            ZStack(alignment: .topLeading) {
                // The detail pane's background: white, or #1e1e1e when dark
                Color(nsColor: .textBackgroundColor)
                    .opacity(splash.backgroundOpacity)
                MoneyFace()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Measured here, inside the reader that places the face: outside
            // it the frame starts below the toolbar while the face is placed
            // from the window's top, which landed it a toolbar too high
            .background(WindowFrameReporter { origin = $0.origin })
        }
        .ignoresSafeArea()
        .opacity(splash.phase == .fading ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { splash.skip() }
        .accessibilityHidden(true)
        .onAppear {
            splash.run(face: face, reduceMotion: reduceMotion) { [navigation] in
                navigation.pane == .earnings
            }
        }
    }

    private func faceRect(in size: CGSize) -> CGRect {
        if splash.phase == .flying, let target = splash.dialFaceFrame {
            return target.offsetBy(dx: -origin.x, dy: -origin.y)
        }
        let side = FaceAnimation.largestFace
        return CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
    }
}

/// Reports a view's frame in its window's coordinates, top-left origin.
/// SwiftUI's own coordinate spaces stop at a NavigationSplitView column,
/// which is hosted on its own, so this asks AppKit
struct WindowFrameReporter: NSViewRepresentable {
    let report: (CGRect) -> Void
    /// Hands over a way to measure the view on demand
    var measure: ((@escaping () -> CGRect?) -> Void)?

    func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView(report: report)
        measure? { [weak view] in view?.currentFrame() }
        return view
    }

    func updateNSView(_ view: ReportingView, context: Context) {
        view.report = report
        view.reportFrame()
    }

    final class ReportingView: NSView {
        var report: (CGRect) -> Void
        private var reported: CGRect?

        init(report: @escaping (CGRect) -> Void) {
            self.report = report
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportFrame()
        }

        override func layout() {
            super.layout()
            reportFrame()
        }

        override func setFrameOrigin(_ origin: NSPoint) {
            super.setFrameOrigin(origin)
            reportFrame()
        }

        /// The frame as laid out now, after any pending layout
        func currentFrame() -> CGRect? {
            guard let content = window?.contentView else { return nil }
            content.layoutSubtreeIfNeeded()
            let frame = convert(bounds, to: content)
            return content.isFlipped
                ? frame
                : CGRect(x: frame.minX, y: content.bounds.height - frame.maxY, width: frame.width, height: frame.height)
        }

        func reportFrame() {
            guard let flipped = currentFrame(), flipped != reported, flipped.width > 0 else { return }
            reported = flipped
            // Not during a SwiftUI update
            DispatchQueue.main.async { [report] in report(flipped) }
        }
    }
}
