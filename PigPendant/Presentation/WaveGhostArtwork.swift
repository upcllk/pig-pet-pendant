import AppKit

final class WaveGhostArtwork {
    private let width: Int
    private let height: Int
    private let pixels: [UInt8]
    private let restImage: NSImage
    private let cache = NSCache<NSNumber, NSImage>()
    private var lastRender: (key: NSNumber, image: NSImage)?

    init(image: NSImage) throws {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ArtworkError.unreadable(URL(fileURLWithPath: "ghost-wave.png"))
        }
        let rasterWidth = min(384, source.width)
        let rasterHeight = Int((Double(source.height) * Double(rasterWidth) / Double(source.width)).rounded())
        width = rasterWidth
        height = rasterHeight
        var data = [UInt8](repeating: 0, count: rasterWidth * rasterHeight * 4)
        let raster: CGImage? = data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: rasterWidth, height: rasterHeight,
                                          bitsPerComponent: 8, bytesPerRow: rasterWidth * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: rasterWidth, height: rasterHeight))
            return context.makeImage()
        }
        guard let raster else {
            throw ArtworkError.unreadable(URL(fileURLWithPath: "ghost-wave.png raster"))
        }
        pixels = data
        restImage = NSImage(cgImage: raster, size: image.size)
        cache.totalCostLimit = 20 * 1024 * 1024
    }

    static func blinkAmount(for sample: CharacterFrameSample) -> Double {
        let closure = [0.0, 0.18, 0.58, 1.0, 1.0, 0.62, 0.20, 0.0]
        let first = min(closure.count - 1, max(0, sample.firstIndex))
        let second = min(closure.count - 1, max(0, sample.secondIndex))
        return closure[first] + (closure[second] - closure[first]) * min(1, max(0, sample.fraction))
    }

    func image(for pose: GhostBodyPose, blinkSample: CharacterFrameSample) -> NSImage {
        let blink = Self.blinkAmount(for: blinkSample)
        let blinkStep = Int((blink * 72).rounded())
        let key = NSNumber(value: pose.key * 73 + blinkStep)
        return render(key: key) { self.sourcePoint($0, pose: pose, blink: Double(blinkStep) / 72) }
    }

    private func render(key: NSNumber, sourcePoint: (CGPoint) -> CGPoint) -> NSImage {
        if lastRender?.key == key, let image = lastRender?.image { return image }
        if let image = cache.object(forKey: key) {
            lastRender = (key, image)
            return image
        }
        var output = pixels
        for y in 0..<height {
            for x in 0..<width {
                let target = CGPoint(x: (Double(x) + 0.5) / Double(width),
                                     y: (Double(y) + 0.5) / Double(height))
                let source = sourcePoint(target)
                guard source != target else { continue }
                let sx = source.x * Double(width) - 0.5
                let sy = source.y * Double(height) - 0.5
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
            preconditionFailure("Cannot render local animation for ghost-wave")
        }
        let rendered = NSImage(cgImage: image, size: restImage.size)
        cache.setObject(rendered, forKey: key, cost: output.count)
        lastRender = (key, rendered)
        return rendered
    }

    private func sourcePoint(_ point: CGPoint, pose: GhostBodyPose, blink: Double) -> CGPoint {
        var result = point
        if blink > 0 {
            for eye in [CGPoint(x: 0.239, y: 0.416), CGPoint(x: 0.490, y: 0.454)] {
                let dx = abs(result.x - eye.x) / 0.058
                let dy = result.y - eye.y
                guard dx < 1, abs(dy) < 0.070 else { continue }
                let edge = min(1, (1 - dx) * 4)
                let scale = 1 - 0.94 * blink * edge * edge * (3 - 2 * edge)
                let distance = abs(dy)
                let inner = 0.043
                let outer = 0.070
                let mapped = distance < inner * scale ? distance / scale
                    : inner + (distance - inner * scale) * (outer - inner) / (outer - inner * scale)
                result.y = eye.y + (dy < 0 ? -mapped : mapped)
            }
        }

        let phase = pose.phase
        let drift = Double(pose.drift) / 16
        let ears: [(center: CGPoint, root: CGPoint, radius: CGSize, angle: Double)] = [
            (CGPoint(x: 0.190, y: 0.235), CGPoint(x: 0.265, y: 0.292),
             CGSize(width: 0.13, height: 0.13),
             0.58 * pose.pulse(start: 0, end: 0.72) * sin(phase * .pi * 4) + drift * 0.12),
            (CGPoint(x: 0.720, y: 0.300), CGPoint(x: 0.670, y: 0.278),
             CGSize(width: 0.14, height: 0.14),
             -0.66 * pose.pulse(start: 0.08, end: 0.80) * sin((phase - 0.08) * .pi * 4) - drift * 0.10)
        ]
        for ear in ears where ear.angle != 0 {
            let radius = hypot((result.x - ear.center.x) / ear.radius.width,
                               (result.y - ear.center.y) / ear.radius.height)
            guard radius < 1 else { continue }
            let angle = ear.angle * pow(1 - radius * radius, 2)
            let dx = result.x - ear.root.x
            let dy = result.y - ear.root.y
            result = CGPoint(x: ear.root.x + dx * cos(angle) - dy * sin(angle),
                             y: ear.root.y + dx * sin(angle) + dy * cos(angle))
        }

        if result.y > 0.69 {
            let t = min(1, max(0, (result.y - 0.69) / 0.18))
            let weight = t * t * (3 - 2 * t)
            let wave = sin(pose.hemPhase * .pi * 2 - result.x * .pi * 4.4)
            result.y += wave * 0.038 * weight
        }
        return result
    }
}
