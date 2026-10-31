import AppKit
import ImageIO
import Observation
import SwiftUI

/// The money face's animation (Resources/money-face.webp, 150 frames of
/// 20 ms): one clock for every face on screen, so the splash's face lands
/// on the dial's showing the same frame, as the Electron app gets from the
/// browser keeping one animation clock per image. ImageIO's own player
/// (`CGAnimateImageDataWithBlock`) ran a cycle in 3.7 s instead of 3, so
/// the frames are decoded once, at the size a face is shown at (about 20 MB
/// on a Retina screen, in 0.2 s), and dropped again when the window closes.
/// Frame 0 comes first, so a face never waits for the rest
@Observable
final class FaceAnimation {
    static let frameDuration: TimeInterval = 0.02
    /// The largest face: the splash's, 96 pt
    static let largestFace: CGFloat = 96

    private(set) var frames: [CGImage] = []
    private(set) var frameCount = 0
    /// When frame 0 is shown; the cycle runs from it
    @ObservationIgnored var epoch = Date.now
    @ObservationIgnored private var task: Task<Void, Never>?

    var isLoaded: Bool { frameCount > 0 && frames.count == frameCount }

    func frame(at date: Date) -> CGImage? {
        guard isLoaded else { return frames.first }
        let elapsed = max(0, date.timeIntervalSince(epoch))
        return frames[Int(elapsed / Self.frameDuration) % frames.count]
    }

    func load() {
        guard frames.isEmpty, task == nil,
              let url = Bundle.main.url(forResource: "money-face", withExtension: "webp"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return }

        let pixels = Int(Self.largestFace * (NSScreen.main?.backingScaleFactor ?? 2))
        frameCount = CGImageSourceGetCount(source)
        frames = Self.decode(url, frames: 0..<1, pixels: pixels)
        task = Task { [weak self, frameCount] in
            let all = await Task.detached(priority: .userInitiated) {
                Self.decode(url, frames: 0..<frameCount, pixels: pixels)
            }.value
            guard let self, !Task.isCancelled else { return }
            frames = all
            epoch = .now
            task = nil
        }
    }

    func unload() {
        task?.cancel()
        task = nil
        frames = []
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

/// The money face: animated, or the still picture under Reduce Motion, as
/// the Electron app's <picture> does
struct MoneyFace: View {
    @Environment(FaceAnimation.self) private var animation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Image(.moneyFace)
                .resizable()
                .scaledToFit()
        } else {
            TimelineView(.animation(minimumInterval: FaceAnimation.frameDuration, paused: !animation.isLoaded)) { context in
                if let frame = animation.frame(at: context.date) {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            }
        }
    }
}
