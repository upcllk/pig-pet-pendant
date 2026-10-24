import AppKit
import Foundation

struct AnimatedArtwork {
    let frames: [NSImage]
    let frameDurations: [TimeInterval]
    let duration: TimeInterval

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 1 else { return nil }
        var images: [NSImage] = []
        var durations: [TimeInterval] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
                  let animation = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any],
                  let delay = animation[kCGImagePropertyAPNGUnclampedDelayTime as String] as? Double,
                  delay.isFinite, delay > 0 else { return nil }
            let size = NSSize(width: image.width, height: image.height)
            if let first = images.first, first.size != size { return nil }
            images.append(NSImage(cgImage: image, size: size))
            durations.append(delay)
        }
        frames = images
        frameDurations = durations
        duration = durations.reduce(0, +)
    }

    func frameIndex(at elapsed: TimeInterval) -> Int {
        AnimationTimeline(frameDurations: frameDurations).frameIndex(at: elapsed)
    }
}
