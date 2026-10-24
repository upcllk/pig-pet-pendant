import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

guard (3...4).contains(CommandLine.arguments.count) else {
    fatalError("Usage: swift -O tools/analyze-rope-animation.swift rope-pig.png output-directory [smoke-frame-directory]")
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), CGImageSourceGetCount(source) == 75 else {
    fatalError("Expected the 75-frame rope pig artwork")
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sampleWidth = 99
let sampleHeight = 89
var features: [[UInt8]] = []
var images: [CGImage] = []
var durations: [Double] = []
for index in 0..<75 {
    guard let image = CGImageSourceCreateImageAtIndex(source, index, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
          let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any],
          let delay = png[kCGImagePropertyAPNGUnclampedDelayTime as String] as? Double,
          let context = CGContext(data: nil, width: sampleWidth, height: sampleHeight,
                                  bitsPerComponent: 8, bytesPerRow: sampleWidth * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
        fatalError("Cannot decode frame \(index)")
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
    features.append(Array(UnsafeBufferPointer(start: bytes, count: sampleWidth * sampleHeight * 4)))
    images.append(image)
    durations.append(delay)
}
func difference(_ first: Int, _ second: Int) -> Double {
    zip(features[first], features[second]).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) }
        / Double(sampleWidth * sampleHeight * 4)
}
struct Neighbor: Codable {
    let index: Int
    let difference: Double
}
struct FrameAnalysis: Codable {
    let index: Int
    let startTime: Double
    let duration: Double
    let nextFrameDifference: Double?
    let nearestNonAdjacent: [Neighbor]
}
struct Transition: Codable {
    let from: Int
    let to: Int
    let difference: Double
}
struct Analysis: Codable {
    let source: String
    let sha256: String
    let frameCount: Int
    let canvas: [Int]
    let duration: Double
    let metric: String
    let featureSize: [Int]
    let meanAdjacentDifference: Double
    let maxAdjacentDifference: Double
    let transitions: [Transition]
    let frames: [FrameAnalysis]
}
var time = 0.0
var frames: [FrameAnalysis] = []
var adjacent: [Double] = []
for index in 0..<75 {
    let next = index < 74 ? difference(index, index + 1) : nil
    if let next = next { adjacent.append(next) }
    var nearest: [Neighbor] = []
    for candidate in 0..<75 where abs(candidate - index) > 5 {
        nearest.append(Neighbor(index: candidate, difference: difference(index, candidate)))
    }
    nearest.sort {
        if $0.difference == $1.difference { return $0.index < $1.index }
        return $0.difference < $1.difference
    }
    frames.append(FrameAnalysis(index: index, startTime: time, duration: durations[index],
                                nextFrameDifference: next, nearestNonAdjacent: Array(nearest.prefix(5))))
    time += durations[index]
}
let analysis = Analysis(source: input.lastPathComponent,
                        sha256: SHA256.hash(data: try Data(contentsOf: input)).map { String(format: "%02x", $0) }.joined(),
                        frameCount: 75, canvas: [images[0].width, images[0].height], duration: time,
                        metric: "Mean absolute byte difference of sRGB premultiplied RGBA; 0 identical, 255 maximum; pose heuristic, not optical flow",
                        featureSize: [sampleWidth, sampleHeight],
                        meanAdjacentDifference: adjacent.reduce(0, +) / Double(adjacent.count),
                        maxAdjacentDifference: adjacent.max()!,
                        transitions: [(74, 0), (0, 28), (28, 0), (51, 0)].map {
                            Transition(from: $0.0, to: $0.1, difference: difference($0.0, $0.1))
                        }, frames: frames)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(analysis).write(to: output.appendingPathComponent("rope-animation-analysis.json"))

let cellWidth = 297
let cellHeight = 288
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cellWidth * 10, pixelsHigh: cellHeight * 8,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create pose atlas") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
NSColor(calibratedRed: 238.0 / 255, green: 242.0 / 255, blue: 247.0 / 255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh).fill()
for index in 0..<75 {
    let x = (index % 10) * cellWidth
    let y = (7 - index / 10) * cellHeight
    NSImage(cgImage: images[index], size: NSSize(width: 297, height: 266))
        .draw(in: NSRect(x: x, y: y + 22, width: 297, height: 266))
    let label = String(format: "frame %02d   %.2f s", index, frames[index].startTime)
    (label as NSString).draw(at: NSPoint(x: x + 6, y: y + 3),
                             withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                                              .foregroundColor: NSColor.black])
}
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode pose atlas") }
try data.write(to: output.appendingPathComponent("rope-animation-poses.png"))
print(String(format: "Adjacent difference: mean %.3f, maximum %.3f", analysis.meanAdjacentDifference,
             analysis.maxAdjacentDifference))
for transition in analysis.transitions {
    print(String(format: "%d -> %d: %.3f", transition.from, transition.to, transition.difference))
}
print("Saved pose atlas and reproducible analysis to \(output.path)")

if CommandLine.arguments.count == 4 {
    let directory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.range(of: "^rope-state-[0-9]{4}\\.png$", options: .regularExpression) != nil }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard files.count == 210,
          let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("rope-state-preview.gif") as CFURL,
                                                           UTType.gif.identifier as CFString, files.count, nil) else {
        fatalError("Expected 210 GUI smoke frames, found \(files.count); run ./build.sh --test first")
    }
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
    ] as CFDictionary)
    for (index, file) in files.enumerated() {
        guard file.lastPathComponent == String(format: "rope-state-%04d.png", index * 4),
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: 368, height: 400, bitsPerComponent: 8,
                                      bytesPerRow: 368 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("Cannot read ordered smoke frame at \(file.path)")
        }
        context.setFillColor(red: 238.0 / 255, green: 242.0 / 255, blue: 247.0 / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 368, height: 400))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 368, height: 400))
        guard let result = context.makeImage() else { fatalError("Cannot render smoke preview") }
        let delay = ((Double(index + 1) * 100 / 15).rounded() - (Double(index) * 100 / 15).rounded()) / 100
        CGImageDestinationAddImage(destination, result, [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay
        ]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write smoke preview") }
    print("Saved 14-second app-rendered state preview")
}
