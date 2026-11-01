import AppKit
import ImageIO
import Observation
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
    /// When frame 0 is shown; the cycle runs from it
    @ObservationIgnored var epoch = Date.now
    @ObservationIgnored private var task: Task<Void, Never>?

    init(resource: String, withExtension fileExtension: String, largestSide: CGFloat, frameDuration: TimeInterval) {
        self.resource = resource
        self.fileExtension = fileExtension
        self.largestSide = largestSide
        self.frameDuration = frameDuration
    }

    func frame(at date: Date) -> CGImage? {
        guard isLoaded else { return frames.first }
        let elapsed = max(0, date.timeIntervalSince(epoch))
        return frames[Int(elapsed / frameDuration) % frames.count]
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
            epoch = .now
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

    /// The money face (Resources/money-face.webp, 150 frames of 20 ms): one
    /// clock for every face on screen, so the splash's face lands on the
    /// dial's showing the same frame, as the Electron app gets from the
    /// browser keeping one animation clock per image. About 20 MB on a
    /// Retina screen, decoded in 0.2 s while the window is open
    static func moneyFace() -> FrameAnimation {
        FrameAnimation(resource: "money-face", withExtension: "webp", largestSide: largestFace, frameDuration: 0.02)
    }

    /// The flying money in Breakdown's payday card (Resources/money-flying.webp,
    /// 150 frames of 20 ms at 192 px), decoded while the pane is shown
    static func flyingMoney() -> FrameAnimation {
        FrameAnimation(resource: "money-flying", withExtension: "webp", largestSide: 64, frameDuration: 0.02)
    }
}

/// Plays a frame animation, or holds frame 0 while `paused`
struct AnimatedFrames: View {
    let animation: FrameAnimation
    var paused = false

    var body: some View {
        TimelineView(.animation(minimumInterval: animation.frameDuration, paused: paused || !animation.isLoaded)) { context in
            if let frame = animation.frame(at: paused ? animation.epoch : context.date) {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
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
