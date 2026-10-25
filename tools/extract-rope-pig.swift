import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      CGImageSourceGetCount(source) > 1 else {
    fatalError("Usage: swift tools/extract-rope-pig.swift source.gif rope-pig.png")
}

struct Frame {
    let pixels: [UInt8]
    let width: Int
    let height: Int
    let attachmentX: Int
    let attachmentY: Int
    let delay: Double
}

var frames: [Frame] = []
var left = Int.max
var top = Int.max
var right = Int.min
var bottom = Int.min
for index in 0..<CGImageSourceGetCount(source) {
    guard let image = CGImageSourceCreateImageAtIndex(source, index, nil),
          let context = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
          let timing = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any],
          let delay = (timing[kCGImagePropertyGIFUnclampedDelayTime as String] ??
                       timing[kCGImagePropertyGIFDelayTime as String]) as? Double,
          delay.isFinite, delay > 0 else {
        fatalError("Cannot decode frame or timing at \(index)")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
        fatalError("Cannot access pixels at \(index)")
    }
    var pixels = Array(UnsafeBufferPointer(start: bytes, count: image.width * image.height * 4))
    var center = image.width / 2
    var attachmentY: Int?
    for y in 0..<image.height {
        guard let seed = (0..<image.width).filter({ pixels[(y * image.width + $0) * 4 + 3] > 0 })
            .min(by: { abs($0 - center) < abs($1 - center) }) else {
            fatalError("Missing rope at frame \(index), row \(y)")
        }
        var start = seed
        var end = seed
        while start > 0 && pixels[(y * image.width + start - 1) * 4 + 3] > 0 { start -= 1 }
        while end + 1 < image.width && pixels[(y * image.width + end + 1) * 4 + 3] > 0 { end += 1 }
        if end - start + 1 > 16 {
            guard y > image.height / 2 else { fatalError("Unexpected rope width at frame \(index)") }
            attachmentY = y
            break
        }
        center = (start + end) / 2
        for x in start...end {
            for channel in 0..<4 { pixels[(y * image.width + x) * 4 + channel] = 0 }
        }
    }
    guard let attachmentY = attachmentY else { fatalError("Cannot locate attachment at frame \(index)") }
    let attachment = attachmentY * image.width + center
    guard pixels[attachment * 4 + 3] > 0 else { fatalError("Disconnected attachment at frame \(index)") }
    var visited = [Bool](repeating: false, count: image.width * image.height)
    var component = [attachment]
    visited[attachment] = true
    var cursor = 0
    var bodyLeft = center
    var bodyRight = center
    var bodyTop = attachmentY
    var bodyBottom = attachmentY
    while cursor < component.count {
        let pixel = component[cursor]
        cursor += 1
        let x = pixel % image.width
        let y = pixel / image.width
        bodyLeft = min(bodyLeft, x)
        bodyRight = max(bodyRight, x)
        bodyTop = min(bodyTop, y)
        bodyBottom = max(bodyBottom, y)
        for nextY in max(0, y - 1)...min(image.height - 1, y + 1) {
            for nextX in max(0, x - 1)...min(image.width - 1, x + 1) {
                let next = nextY * image.width + nextX
                if !visited[next], pixels[next * 4 + 3] > 0 {
                    visited[next] = true
                    component.append(next)
                }
            }
        }
    }
    for y in 0..<image.height {
        for x in 0..<image.width where pixels[(y * image.width + x) * 4 + 3] > 0 {
            if x < bodyLeft - 2 || x > bodyRight + 2 || y < bodyTop - 2 || y > bodyBottom + 2 {
                for channel in 0..<4 { pixels[(y * image.width + x) * 4 + channel] = 0 }
                continue
            }
            left = min(left, x - center)
            right = max(right, x - center)
            top = min(top, y - attachmentY)
            bottom = max(bottom, y - attachmentY)
        }
    }
    frames.append(Frame(pixels: pixels, width: image.width, height: image.height,
                        attachmentX: center, attachmentY: attachmentY, delay: delay))
}

let padding = 4
let width = right - left + 1 + padding * 2
let height = bottom - top + 1 + padding * 2
let attachmentX = padding - left
let attachmentY = padding - top
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString,
                                                       frames.count, nil),
      let properties = CGImageSourceCopyProperties(source, nil) as? [String: Any],
      let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any],
      let loop = gif[kCGImagePropertyGIFLoopCount as String] as? Int else {
    fatalError("Cannot create output or read loop count")
}
CGImageDestinationSetProperties(destination, [
    kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: loop]
] as CFDictionary)
for frame in frames {
    // One shared canvas and attachment preserve body motion without the source's long rope.
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<frame.height {
        for x in 0..<frame.width {
            let sourceOffset = (y * frame.width + x) * 4
            guard frame.pixels[sourceOffset + 3] > 0 else { continue }
            let destinationX = x - frame.attachmentX + attachmentX
            let destinationY = y - frame.attachmentY + attachmentY
            let destinationOffset = (destinationY * width + destinationX) * 4
            for channel in 0..<4 { pixels[destinationOffset + channel] = frame.pixels[sourceOffset + channel] }
        }
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
        fatalError("Cannot encode frame")
    }
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyPNGDictionary: [
        kCGImagePropertyAPNGDelayTime: frame.delay,
        kCGImagePropertyAPNGUnclampedDelayTime: frame.delay
    ]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write output") }
print("Extracted \(frames.count) frames, \(frames.reduce(0) { $0 + $1.delay }) seconds")
print("Canvas: \(width)x\(height); attachment from top-left: (\(attachmentX), \(attachmentY))")
print("Output: \(output.path)")
