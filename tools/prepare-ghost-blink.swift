import AppKit
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

setbuf(stdout, nil)
guard CommandLine.arguments.count == 4 else {
    fatalError("Usage: swift tools/prepare-ghost-blink.swift key-directory body.png output.png")
}
let keys = URL(fileURLWithPath: CommandLine.arguments[1])
let bodyURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
func decode(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Cannot decode \(url.path)")
    }
    return image
}
func raster(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    precondition(success, "Cannot rasterize image")
    return bytes
}
let body = decode(bodyURL)
let width = body.width
let height = body.height
precondition(width == 768 && height == 1152)
let base = raster(body, width: width, height: height)
var frames: [[UInt8]] = []
for index in 0..<8 {
    let url = keys.appendingPathComponent(String(format: "blink_key_%02d.png", index))
    let key = decode(url)
    precondition(key.width == 1024 && key.height == 1536)
    let native = raster(key, width: key.width, height: key.height)
    var resized = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let sx = (Double(x) + 0.5) * Double(key.width) / Double(width) - 0.5
            let sy = (Double(y) + 0.5) * Double(key.height) / Double(height) - 0.5
            let left = max(0, min(key.width - 2, Int(floor(sx))))
            let top = max(0, min(key.height - 2, Int(floor(sy))))
            let fx = sx - Double(left)
            let fy = sy - Double(top)
            for channel in 0..<4 {
                func value(_ px: Int, _ py: Int) -> Double { Double(native[(py * key.width + px) * 4 + channel]) }
                let upper = value(left, top) * (1 - fx) + value(left + 1, top) * fx
                let lower = value(left, top + 1) * (1 - fx) + value(left + 1, top + 1) * fx
                resized[(y * width + x) * 4 + channel] = UInt8((upper * (1 - fy) + lower * fy).rounded())
            }
        }
    }
    frames.append(resized)
    let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    print("key \(index) SHA-256 \(hash)")
}
precondition(frames[0] == frames[7], "Blink must return to the identical original pose")
let eyeRegion = CGRect(x: 150, y: 350, width: 300, height: 150)
func eyeCenter(_ bytes: [UInt8], region: CGRect) -> CGPoint {
    var xTotal = 0.0
    var yTotal = 0.0
    var weight = 0.0
    for y in Int(region.minY)..<Int(region.maxY) {
        for x in Int(region.minX)..<Int(region.maxX) {
            let offset = (y * width + x) * 4
            let alpha = Double(bytes[offset + 3])
            guard alpha > 128 else { continue }
            let dark = max(0, 0.4 - Double(max(bytes[offset], bytes[offset + 1], bytes[offset + 2])) / alpha)
            xTotal += Double(x) * dark
            yTotal += Double(y) * dark
            weight += dark
        }
    }
    precondition(weight > 0, "Cannot locate eye")
    return CGPoint(x: xTotal / weight, y: yTotal / weight)
}
for region in [CGRect(x: 160, y: 350, width: 100, height: 110),
               CGRect(x: 320, y: 390, width: 120, height: 110)] {
    let sourceCenter = eyeCenter(frames[0], region: region)
    let bodyCenter = eyeCenter(base, region: region)
    let error = hypot(sourceCenter.x - bodyCenter.x, sourceCenter.y - bodyCenter.y)
    print("Eye alignment error: \(error) px")
    precondition(error < 2, "New body and scaled keyframes are not aligned")
}
let delays = [0.07, 0.10, 0.10, 0.14, 0.14, 0.13, 0.13, 0.10]
var prepared: [CGImage] = []
for index in frames.indices {
    var result = base
    var changed = 0
    var resamplingNoise = 0
    for pixel in 0..<(width * height) {
        let offset = pixel * 4
        precondition(abs(Int(frames[index][offset + 3]) - Int(frames[0][offset + 3])) <= 1,
                     "Source blink alpha changed beyond resampling precision")
        guard frames[index][offset..<(offset + 3)] != frames[0][offset..<(offset + 3)] else { continue }
        let point = CGPoint(x: pixel % width, y: pixel / width)
        if !eyeRegion.contains(point) {
            precondition((0..<3).allSatisfy {
                abs(Int(frames[index][offset + $0]) - Int(frames[0][offset + $0])) <= 1
            }, "Source keyframe changed outside the eye region")
            resamplingNoise += 1
            continue
        }
        let alpha = Double(base[offset + 3])
        let keyAlpha = Double(frames[index][offset + 3])
        precondition(alpha > 240 && keyAlpha > 240, "Eye changes must be inside the opaque face")
        for channel in 0..<3 {
            let difference = Double(frames[index][offset + channel]) / keyAlpha
                - Double(frames[0][offset + channel]) / Double(frames[0][offset + 3])
            let value = Double(base[offset + channel]) + difference * alpha
            result[offset + channel] = UInt8(min(alpha, max(0, value)).rounded())
        }
        changed += 1
    }
    guard let provider = CGDataProvider(data: Data(result) as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
        fatalError("Cannot encode frame \(index)")
    }
    prepared.append(image)
    print("frame \(index): \(changed) eye differences; ignored \(resamplingNoise) one-byte resampling differences outside eyes; body alpha and other pixels preserved")
}
guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 8, nil) else {
    fatalError("Cannot create ghost blink APNG")
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]] as CFDictionary)
for index in prepared.indices {
    CGImageDestinationAddImage(destination, prepared[index], [kCGImagePropertyPNGDictionary: [
        kCGImagePropertyAPNGDelayTime: delays[index], kCGImagePropertyAPNGUnclampedDelayTime: delays[index]
    ]] as CFDictionary)
}
precondition(CGImageDestinationFinalize(destination))
print("Saved \(outputURL.path), \(delays.reduce(0, +)) seconds, 0.28 seconds of closed-eye poses")
