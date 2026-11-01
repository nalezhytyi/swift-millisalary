import AppKit
import ImageIO
import Observation
import QuartzCore
import SwiftUI

/// An animated image from the bundle, played on a clock of its own. ImageIO's
/// own player (`CGAnimateImageDataWithBlock`) ran the face's 3 s cycle in
/// 3.7 s, so the frames are decoded once, at the largest size they're shown
/// at, and dropped again when nothing shows them. Frame 0 comes first, so a
/// view never waits for the rest
@Observable
final class FrameAnimation {
    let frameDuration: TimeInterval
    @ObservationIgnored private let resource: String
    @ObservationIgnored private let fileExtension: String
    /// The largest side it's shown at, in points
    @ObservationIgnored private let largestSide: CGFloat

    private(set) var frames: [CGImage] = []
    /// The background decode has finished with at least one frame. The
    /// cycle runs over what it produced: a frame that fails to decode is
    /// left out instead of keeping every view on frame 0
    private(set) var isLoaded = false
    /// When frame 0 is shown, in Core Animation's media time; the cycle
    /// runs from it
    private(set) var epoch = CACurrentMediaTime()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(resource: String, withExtension fileExtension: String, largestSide: CGFloat, frameDuration: TimeInterval) {
        self.resource = resource
        self.fileExtension = fileExtension
        self.largestSide = largestSide
        self.frameDuration = frameDuration
    }

    /// Starts the cycle again from frame 0, on every view that plays it
    func restart() {
        epoch = CACurrentMediaTime()
    }

    func load() {
        guard frames.isEmpty, task == nil,
              let url = Bundle.main.url(forResource: resource, withExtension: fileExtension),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return }

        let pixels = Int(largestSide * (NSScreen.main?.backingScaleFactor ?? 2))
        let count = CGImageSourceGetCount(source)
        frames = Self.decode(url, frames: 0..<1, pixels: pixels)
        task = Task { [weak self] in
            let all = await Task.detached(priority: .userInitiated) {
                Self.decode(url, frames: 0..<count, pixels: pixels)
            }.value
            guard let self, !Task.isCancelled else { return }
            task = nil
            // Nothing decoded: the views stay as they are
            guard !all.isEmpty else { return }
            frames = all
            isLoaded = true
            restart()
        }
    }

    func unload() {
        task?.cancel()
        task = nil
        frames = []
        isLoaded = false
    }

    private nonisolated static func decode(_ url: URL, frames: Range<Int>, pixels: Int) -> [CGImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        return frames.compactMap { CGImageSourceCreateThumbnailAtIndex(source, $0, options) }
    }
}

extension FrameAnimation {
    /// The largest face: the splash's, 96 pt
    static let largestFace: CGFloat = 96

    /// The money face (Resources/money-face.webp, 150 frames of 20 ms at
    /// 192 px, the largest face on a Retina screen): one
    /// clock for every face on screen, so the splash's face lands on the
    /// dial's showing the same frame, as the Electron app gets from the
    /// browser keeping one animation clock per image. About 20 MB on a
    /// Retina screen, decoded in 0.2 s while the window is open
    static func moneyFace() -> FrameAnimation {
        FrameAnimation(resource: "money-face", withExtension: "webp", largestSide: largestFace, frameDuration: 0.02)
    }

    /// The flying money in Breakdown's payday card (Resources/money-flying.webp,
    /// 150 frames of 20 ms at 128 px, its 64 pt on a Retina screen), decoded
    /// while the pane is shown
    static func flyingMoney() -> FrameAnimation {
        FrameAnimation(resource: "money-flying", withExtension: "webp", largestSide: 64, frameDuration: 0.02)
    }
}

/// Plays a frame animation, or holds frame 0 while `paused`. Core Animation
/// flips the frames in the render server, so a playing animation costs the
/// app nothing per frame: a SwiftUI TimelineView that swapped the image
/// updated the window's view graph 50 times a second for it. Every view on
/// the same clock (`epoch`) shows the same frame
struct AnimatedFrames: View {
    let animation: FrameAnimation
    var paused = false

    var body: some View {
        FrameLayer(
            frames: animation.frames,
            playing: animation.isLoaded && !paused,
            epoch: animation.epoch,
            frameDuration: animation.frameDuration
        )
    }
}

private struct FrameLayer: NSViewRepresentable {
    let frames: [CGImage]
    let playing: Bool
    let epoch: CFTimeInterval
    let frameDuration: TimeInterval

    func makeNSView(context: Context) -> FrameView {
        FrameView()
    }

    func updateNSView(_ view: FrameView, context: Context) {
        view.show(frames, playing: playing, epoch: epoch, frameDuration: frameDuration)
    }

    final class FrameView: NSView {
        private static let animationKey = "frames"
        /// What the layer shows, so the updates that change nothing (the
        /// dial's, ten a second) leave it alone
        private var shown: (first: CGImage?, count: Int, playing: Bool, epoch: CFTimeInterval)?

        init() {
            super.init(frame: .zero)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func makeBackingLayer() -> CALayer {
            let layer = CALayer()
            layer.contentsGravity = .resizeAspect
            // The frames are decoded for the largest face; smaller ones
            // scale them down through mipmaps
            layer.minificationFilter = .trilinear
            return layer
        }

        func show(_ frames: [CGImage], playing: Bool, epoch: CFTimeInterval, frameDuration: TimeInterval) {
            guard let layer else { return }
            let next = (first: frames.first, count: frames.count, playing: playing, epoch: epoch)
            if let shown, shown.first === next.first, shown.count == next.count,
               shown.playing == next.playing, shown.epoch == next.epoch {
                return
            }
            shown = next

            layer.removeAnimation(forKey: Self.animationKey)
            layer.contents = frames.first
            guard playing, frames.count > 1 else { return }

            // Frame i from i to i + 1 frame durations into each cycle, the
            // cycle counted from the epoch, as a discrete keyframe animation
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = frames
            animation.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
            animation.calculationMode = .discrete
            animation.duration = frameDuration * Double(frames.count)
            animation.repeatCount = .infinity
            animation.beginTime = layer.convertTime(epoch, from: nil)
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: Self.animationKey)
        }
    }
}

/// The money face: animated, or the still picture under Reduce Motion, as
/// the Electron app's <picture> does
struct MoneyFace: View {
    @Environment(FrameAnimation.self) private var animation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Image(.moneyFace)
                .resizable()
                .scaledToFit()
        } else {
            AnimatedFrames(animation: animation)
        }
    }
}
