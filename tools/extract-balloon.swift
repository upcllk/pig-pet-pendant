import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Usage: swift tools/extract-balloon.swift source.jpg balloon.png")
}

let scaleX = CGFloat(image.width) / 1012
let scaleY = CGFloat(image.height) / 1024
let crop = CGRect(x: 224 * scaleX, y: 260 * scaleY, width: 270 * scaleX, height: 258 * scaleY).integral
guard let cropped = image.cropping(to: crop),
      let context = CGContext(data: nil, width: cropped.width, height: cropped.height,
                              bitsPerComponent: 8, bytesPerRow: cropped.width * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Cannot crop reference image")
}

func point(_ horizontal: CGFloat, _ vertical: CGFloat) -> CGPoint {
    CGPoint(x: horizontal * scaleX - crop.minX,
            y: crop.maxY - vertical * scaleY)
}

let outline = CGMutablePath()
outline.move(to: point(270, 306))
outline.addCurve(to: point(423, 279), control1: point(313, 260), control2: point(374, 256))
outline.addCurve(to: point(486, 389), control1: point(465, 300), control2: point(485, 347))
outline.addCurve(to: point(420, 502), control1: point(487, 439), control2: point(467, 478))
outline.addCurve(to: point(290, 493), control1: point(378, 525), control2: point(326, 516))
outline.addCurve(to: point(242, 373), control1: point(251, 469), control2: point(238, 420))
outline.addCurve(to: point(229, 361), control1: point(233, 376), control2: point(226, 373))
outline.addCurve(to: point(239, 311), control1: point(231, 342), control2: point(233, 324))
outline.addCurve(to: point(270, 306), control1: point(247, 293), control2: point(258, 300))
outline.closeSubpath()
context.addPath(outline)
context.clip()
context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))

guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
    fatalError("Cannot access cropped pixels")
}
for index in 0..<(cropped.width * cropped.height) {
    let offset = index * 4
    let alpha = CGFloat(bytes[offset + 3])
    guard alpha > 0 else { continue }
    let minimum = CGFloat(min(bytes[offset], bytes[offset + 1], bytes[offset + 2])) * 255 / alpha
    let opacity = min(1, max(0, (245 - minimum) / 15))
    for channel in 0..<4 {
        bytes[offset + channel] = UInt8(CGFloat(bytes[offset + channel]) * opacity)
    }
}

let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let result = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Cannot create transparent PNG")
}
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write transparent PNG") }
print("Extracted reference balloon: \(result.width)x\(result.height) -> \(output.path)")