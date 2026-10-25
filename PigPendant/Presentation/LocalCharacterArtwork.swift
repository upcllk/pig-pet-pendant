import AppKit

final class LocalCharacterArtwork {
    private let width: Int
    private let height: Int
    private let pixels: [UInt8]
    private let mode: DisplayMode
    private let restImage: NSImage
    private let cache = NSCache<NSNumber, NSImage>()

    init(image: NSImage, mode: DisplayMode) throws {
        self.mode = mode
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ArtworkError.unreadable(URL(fileURLWithPath: "\(mode.rawValue) animation"))
        }
        width = min(512, source.width)
        height = Int((Double(source.height) * Double(width) / Double(source.width)).rounded())
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let w = width
        let h = height
        let raster: CGImage? = data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
            return context.makeImage()
        }
        guard let raster = raster else {
            throw ArtworkError.unreadable(URL(fileURLWithPath: "\(mode.rawValue) animation raster"))
        }
        pixels = data
        restImage = NSImage(cgImage: raster, size: image.size)
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func image(for pose: LocalCharacterPose) -> NSImage {
        guard pose.step > 0 && pose.step < LocalCharacterPose.steps else { return restImage }
        let blink = pose.blink
        let earAngle = pose.earAngle
        let nuzzle = pose.nuzzle
        guard blink > 0 || abs(earAngle) > 0.000001 || nuzzle > 0.000001 else { return restImage }
        let step = pose.gesture == .blink && blink == 1 ? Int((0.4 * Double(LocalCharacterPose.steps)).rounded()) : pose.step
        let key = NSNumber(value: pose.gesture.rawValue * (LocalCharacterPose.steps + 1) + step)
        if let image = cache.object(forKey: key) { return image }
        var output = pixels
        for y in 0..<height {
            for x in 0..<width {
                let original = CGPoint(x: (Double(x) + 0.5) / Double(width),
                                       y: (Double(y) + 0.5) / Double(height))
                let point = sourcePoint(original, blink: blink, earAngle: earAngle, nuzzle: nuzzle)
                guard point != original else { continue }
                let sx = point.x * Double(width) - 0.5
                let sy = point.y * Double(height) - 0.5
                let left = Int(floor(sx))
                let top = Int(floor(sy))
                let fx = sx - Double(left)
                let fy = sy - Double(top)
                let offset = (y * width + x) * 4
                for channel in 0..<4 {
                    func value(_ px: Int, _ py: Int) -> Double {
                        guard (0..<width).contains(px), (0..<height).contains(py) else { return 0 }
                        return Double(pixels[(py * width + px) * 4 + channel])
                    }
                    let upper = value(left, top) * (1 - fx) + value(left + 1, top) * fx
                    let lower = value(left, top + 1) * (1 - fx) + value(left + 1, top + 1) * fx
                    output[offset + channel] = UInt8(max(0, min(255, (upper * (1 - fy) + lower * fy).rounded())))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(output) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            preconditionFailure("Cannot render local character animation for \(mode.rawValue)")
        }
        let result = NSImage(cgImage: image, size: restImage.size)
        cache.setObject(result, forKey: key, cost: output.count)
        return result
    }

    // Coordinates are normalized source pixels, with y increasing downward.
    private func sourcePoint(_ point: CGPoint, blink: Double, earAngle: Double, nuzzle: Double) -> CGPoint {
        var result = point
        if blink > 0 {
            let eyes: [CGPoint] = mode == .balloon
                ? [CGPoint(x: 0.217, y: 0.529), CGPoint(x: 0.567, y: 0.454)]
                : [CGPoint(x: 0.102, y: 0.378), CGPoint(x: 0.294, y: 0.391)]
            let rx = mode == .balloon ? 0.085 : 0.043
            let inner = mode == .balloon ? 0.062 : 0.057
            let outer = mode == .balloon ? 0.080 : 0.071
            for eye in eyes {
                let dx = abs(result.x - eye.x) / rx
                let dy = result.y - eye.y
                guard dx < 1, abs(dy) < outer else { continue }
                let edge = min(1, (1 - dx) * 4)
                let scale = 1 - 0.86 * blink * edge * edge * (3 - 2 * edge)
                let distance = abs(dy)
                let mapped = distance < inner * scale ? distance / scale
                    : inner + (distance - inner * scale) * (outer - inner) / (outer - inner * scale)
                result.y = eye.y + (dy < 0 ? -mapped : mapped)
            }
        }
        if earAngle != 0 {
            let ears: [(center: CGPoint, radius: CGSize, root: CGPoint)] = mode == .balloon
                ? [(CGPoint(x: 0.10, y: 0.27), CGSize(width: 0.15, height: 0.17), CGPoint(x: 0.13, y: 0.46)),
                   (CGPoint(x: 0.68, y: 0.20), CGSize(width: 0.19, height: 0.18), CGPoint(x: 0.68, y: 0.40))]
                : [(CGPoint(x: 0.10, y: 0.13), CGSize(width: 0.17, height: 0.23), CGPoint(x: 0.14, y: 0.25)),
                   (CGPoint(x: 0.40, y: 0.21), CGSize(width: 0.12, height: 0.17), CGPoint(x: 0.43, y: 0.33))]
            for (index, ear) in ears.enumerated() {
                let radius = hypot((result.x - ear.center.x) / ear.radius.width,
                                   (result.y - ear.center.y) / ear.radius.height)
                guard radius < 1 else { continue }
                let weight = pow(1 - radius * radius, 2)
                let angle = earAngle * weight * (index == 0 ? 1 : -1)
                let dx = result.x - ear.root.x
                let dy = result.y - ear.root.y
                result = CGPoint(x: ear.root.x + dx * cos(angle) - dy * sin(angle),
                                 y: ear.root.y + dx * sin(angle) + dy * cos(angle))
            }
        }
        if nuzzle > 0 {
            let nose = mode == .balloon ? CGPoint(x: 0.365, y: 0.706) : CGPoint(x: 0.166, y: 0.549)
            let radius = hypot((result.x - nose.x) / 0.19, (result.y - nose.y) / 0.18)
            if radius < 1 {
                let amount = nuzzle * pow(1 - radius * radius, 2)
                result.x = nose.x + (result.x - nose.x) / (1 + 0.14 * amount) + 0.034 * amount
                result.y = nose.y + (result.y - nose.y) / (1 + 0.09 * amount) + 0.012 * amount
            }
        }
        return result
    }
}
