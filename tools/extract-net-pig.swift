import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil) else {
    fatalError("Usage: swift tools/extract-net-pig.swift source.gif net-pig.png")
}

let frameCount = CGImageSourceGetCount(source)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString,
                                                       frameCount, nil) else {
    fatalError("Cannot create animated PNG")
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]] as CFDictionary)
var totalDuration = 0.0
var repairedPixels = 0
for frameIndex in 0..<frameCount {
    guard let image = CGImageSourceCreateImageAtIndex(source, frameIndex, nil),
          let context = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Cannot decode frame \(frameIndex)")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
        fatalError("Cannot access frame pixels")
    }
    let pixelCount = image.width * image.height
    let original = Array(UnsafeBufferPointer(start: bytes, count: pixelCount * 4))
    let colors = (0..<pixelCount).map { pixel -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) in
        let offset = pixel * 4
        let alpha = CGFloat(original[offset + 3])
        guard alpha > 0 else { return (0, 0, 0, 0) }
        return (CGFloat(original[offset]) * 255 / alpha,
                CGFloat(original[offset + 1]) * 255 / alpha,
                CGFloat(original[offset + 2]) * 255 / alpha, alpha)
    }
    let bluePixels = colors.map {
        $0.alpha >= 128 && $0.blue > $0.red + 8 && $0.blue > $0.green + 3 && $0.green >= $0.red - 2
    }
    var faceBounds = [(left: Int, right: Int)](repeating: (image.width, -1), count: image.height)
    for row in 0..<image.height {
        var faceLeft = image.width
        var faceRight = -1
        for column in 0..<image.width {
            let offset = (row * image.width + column) * 4
            let alpha = CGFloat(bytes[offset + 3])
            guard alpha > 0 else { continue }
            let red = CGFloat(bytes[offset]) * 255 / alpha
            let green = CGFloat(bytes[offset + 1]) * 255 / alpha
            let blue = CGFloat(bytes[offset + 2]) * 255 / alpha
            if red > 130 && red > green * 1.08 && green > blue * 1.04 {
                faceLeft = min(faceLeft, column)
                faceRight = max(faceRight, column)
            }
        }
        faceBounds[row] = (faceLeft, faceRight)
        for column in 0..<image.width {
            let offset = (row * image.width + column) * 4
            let alpha = CGFloat(bytes[offset + 3])
            guard alpha > 0, column < faceLeft || column > faceRight else { continue }
            let red = CGFloat(bytes[offset]) * 255 / alpha
            let green = CGFloat(bytes[offset + 1]) * 255 / alpha
            let blue = CGFloat(bytes[offset + 2]) * 255 / alpha
            let chroma = max(red, green, blue) - min(red, green, blue)
            let opacity = min(1, max(0, (chroma - 6) / 12))
            for channel in 0..<4 {
                bytes[offset + channel] = UInt8(CGFloat(bytes[offset + channel]) * opacity)
            }
        }
    }
    let directions = [(1, 0), (0, 1), (1, 1), (1, -1), (2, 1), (2, -1), (1, 2), (1, -2)]
    for pixel in 0..<pixelCount {
        let color = colors[pixel]
        let minimum = min(color.red, color.green, color.blue)
        let chroma = max(color.red, color.green, color.blue) - minimum
        let row = pixel / image.width
        let column = pixel % image.width
        let face = faceBounds[row]
        let missingLine = color.alpha == 0 && face.right >= face.left &&
            column >= face.left - 12 && column <= face.right + 12
        let damagedLine = color.alpha > 0 && minimum > 100 && chroma < 35 &&
            (CGFloat(bytes[pixel * 4 + 3]) < color.alpha || minimum > 175)
        guard missingLine || damagedLine else { continue }
        var bestSpan = CGFloat.infinity
        var endpoints: (first: Int, second: Int, firstDistance: CGFloat, secondDistance: CGFloat)?
        for (horizontal, vertical) in directions {
            var neighbors: [(pixel: Int, distance: CGFloat)] = []
            for sign in [-1, 1] {
                for step in 1...4 {
                    let nextColumn = column + horizontal * step * sign
                    let nextRow = row + vertical * step * sign
                    guard (0..<image.width).contains(nextColumn), (0..<image.height).contains(nextRow) else { break }
                    let neighbor = nextRow * image.width + nextColumn
                    if bluePixels[neighbor] {
                        let distance = hypot(CGFloat(horizontal * step), CGFloat(vertical * step))
                        neighbors.append((neighbor, distance))
                        break
                    }
                }
            }
            if neighbors.count == 2 {
                let span = neighbors[0].distance + neighbors[1].distance
                if span <= (missingLine ? 6 : 8) && span < bestSpan {
                    bestSpan = span
                    endpoints = (neighbors[0].pixel, neighbors[1].pixel, neighbors[0].distance, neighbors[1].distance)
                }
            }
        }
        guard let endpoints = endpoints else { continue }
        let first = colors[endpoints.first]
        let second = colors[endpoints.second]
        let fraction = endpoints.firstDistance / bestSpan
        let alpha = missingLine ? min(first.alpha, second.alpha) : color.alpha
        let repaired = [first.red + (second.red - first.red) * fraction,
                        first.green + (second.green - first.green) * fraction,
                        first.blue + (second.blue - first.blue) * fraction]
        for channel in 0..<3 {
            bytes[pixel * 4 + channel] = UInt8(min(255, max(0, repaired[channel])) * alpha / 255)
        }
        bytes[pixel * 4 + 3] = UInt8(alpha)
        repairedPixels += 1
    }
    var visited = [Bool](repeating: false, count: pixelCount)
    var foreground: [Int] = []
    for pixel in 0..<pixelCount {
        guard !visited[pixel], bytes[pixel * 4 + 3] > 0 else { continue }
        var component = [pixel]
        visited[pixel] = true
        var cursor = 0
        while cursor < component.count {
            let current = component[cursor]
            cursor += 1
            let row = current / image.width
            let column = current % image.width
            for neighborRow in max(0, row - 1)...min(image.height - 1, row + 1) {
                for neighborColumn in max(0, column - 1)...min(image.width - 1, column + 1) {
                    let neighbor = neighborRow * image.width + neighborColumn
                    if !visited[neighbor], bytes[neighbor * 4 + 3] > 0 {
                        visited[neighbor] = true
                        component.append(neighbor)
                    }
                }
            }
        }
        if component.count > foreground.count { foreground = component }
    }
    var retained = [Bool](repeating: false, count: pixelCount)
    for pixel in foreground { retained[pixel] = true }
    for pixel in 0..<pixelCount where !retained[pixel] {
        for channel in 0..<4 { bytes[pixel * 4 + channel] = 0 }
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, frameIndex, nil) as? [String: Any] ?? [:]
    let timing = properties["{WebP}"] as? [String: Any] ?? properties["{GIF}"] as? [String: Any] ?? [:]
    let delay = timing["UnclampedDelayTime"] as? Double ?? timing["DelayTime"] as? Double ?? 0.1
    totalDuration += delay
    guard let result = context.makeImage() else { fatalError("Cannot encode frame") }
    CGImageDestinationAddImage(destination, result, [kCGImagePropertyPNGDictionary: [
        kCGImagePropertyAPNGDelayTime: delay,
        kCGImagePropertyAPNGUnclampedDelayTime: delay
    ]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write animation") }
print("Extracted \(frameCount) frames, \(totalDuration) seconds; repaired \(repairedPixels) net pixels -> \(output.path)")