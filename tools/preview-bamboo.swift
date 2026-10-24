import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let artwork = CGContext(data: nil, width: original.width, height: original.height,
                             bitsPerComponent: 8, bytesPerRow: original.width * 4,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Usage: swift tools/preview-bamboo.swift reference.png output-directory")
}

let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
artwork.draw(original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
let pixels = artwork.data!.assumingMemoryBound(to: UInt8.self)
var bounds = CGRect.null
var retained = 0
for row in 0..<original.height {
    for column in 0..<original.width {
        let offset = (row * original.width + column) * 4
        let red = Int(pixels[offset])
        let green = Int(pixels[offset + 1])
        let blue = Int(pixels[offset + 2])
        let warm = red > green + 7 && red > blue + 10 && Double(blue) > Double(green) * 0.70
        let faceDetail = max(red, green, blue) < 110 && column < original.width * 2 / 5
            && row > original.height * 3 / 20 && row < original.height * 11 / 20
        if row < original.height * 3 / 4 && (warm || faceDetail) {
            bounds = bounds.union(CGRect(x: column, y: row, width: 1, height: 1))
            retained += 1
        } else {
            for channel in 0..<4 { pixels[offset + channel] = 0 }
        }
    }
}
var visited = [Bool](repeating: false, count: original.width * original.height)
var largest: [Int] = []
for pixel in 0..<visited.count where !visited[pixel] && pixels[pixel * 4 + 3] > 0 {
    var component = [pixel]
    visited[pixel] = true
    var next = 0
    while next < component.count {
        let current = component[next]
        next += 1
        let column = current % original.width
        let row = current / original.width
        for (horizontal, vertical) in [(column - 1, row), (column + 1, row),
                                       (column, row - 1), (column, row + 1)] {
            guard horizontal >= 0, horizontal < original.width,
                  vertical >= 0, vertical < original.height else { continue }
            let neighbor = vertical * original.width + horizontal
            if !visited[neighbor] && pixels[neighbor * 4 + 3] > 0 {
                visited[neighbor] = true
                component.append(neighbor)
            }
        }
    }
    if component.count > largest.count { largest = component }
}
var selected = [Bool](repeating: false, count: visited.count)
bounds = .null
for pixel in largest {
    selected[pixel] = true
    bounds = bounds.union(CGRect(x: pixel % original.width, y: pixel / original.width, width: 1, height: 1))
}
for pixel in 0..<selected.count where !selected[pixel] {
    for channel in 0..<4 { pixels[pixel * 4 + channel] = 0 }
}
retained = largest.count
guard let extracted = artwork.makeImage()?.cropping(to: bounds), retained > 10000 else {
    fatalError("Cannot extract original pig pixels")
}

func save(_ image: CGImage, named name: String) {
    let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL,
                                                     UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}

save(extracted, named: "bamboo-pig-preview-artwork.png")

let width = 960
let height = 640
let scale: CGFloat = 2
let canvas = CGContext(data: nil, width: width * 2, height: height * 2,
                       bitsPerComponent: 8, bytesPerRow: width * 8,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
canvas.scaleBy(x: scale, y: scale)
canvas.setFillColor(NSColor.white.cgColor)
canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))

let anchor = CGPoint(x: 215, y: 510)
let controlStart = CGPoint(x: 80, y: 270)
let controlEnd = CGPoint(x: 180, y: 170)
let tip = CGPoint(x: 620, y: 225)
func point(at progress: CGFloat) -> CGPoint {
    let inverse = 1 - progress
    return CGPoint(x: inverse * inverse * inverse * anchor.x
                   + 3 * inverse * inverse * progress * controlStart.x
                   + 3 * inverse * progress * progress * controlEnd.x
                   + progress * progress * progress * tip.x,
                   y: inverse * inverse * inverse * anchor.y
                   + 3 * inverse * inverse * progress * controlStart.y
                   + 3 * inverse * progress * progress * controlEnd.y
                   + progress * progress * progress * tip.y)
}

let bamboo = CGMutablePath()
bamboo.move(to: anchor)
bamboo.addCurve(to: tip, control1: controlStart, control2: controlEnd)
canvas.setLineCap(.round)
canvas.addPath(bamboo)
canvas.setLineWidth(24)
canvas.setStrokeColor(NSColor(calibratedRed: 0.33, green: 0.57, blue: 0.18, alpha: 1).cgColor)
canvas.strokePath()
canvas.saveGState()
canvas.translateBy(x: -2, y: 3)
canvas.addPath(bamboo)
canvas.setLineWidth(15)
canvas.setStrokeColor(NSColor(calibratedRed: 0.48, green: 0.69, blue: 0.27, alpha: 1).cgColor)
canvas.strokePath()
canvas.restoreGState()
canvas.saveGState()
canvas.translateBy(x: -4, y: 4)
canvas.addPath(bamboo)
canvas.setLineWidth(3)
canvas.setStrokeColor(NSColor(calibratedRed: 0.64, green: 0.79, blue: 0.38, alpha: 1).cgColor)
canvas.strokePath()
canvas.restoreGState()

for progress in stride(from: CGFloat(0.08), through: 0.98, by: 0.15) {
    let location = point(at: progress)
    let previous = point(at: max(0, progress - 0.001))
    let next = point(at: min(1, progress + 0.001))
    let angle = atan2(next.y - previous.y, next.x - previous.x)
    canvas.saveGState()
    canvas.translateBy(x: location.x, y: location.y)
    canvas.rotate(by: angle)
    let joint = CGMutablePath()
    joint.move(to: CGPoint(x: -1, y: -11))
    joint.addCurve(to: CGPoint(x: -1, y: 11), control1: CGPoint(x: 4, y: -5),
                   control2: CGPoint(x: 4, y: 5))
    canvas.addPath(joint)
    canvas.setLineWidth(4)
    canvas.setStrokeColor(NSColor(calibratedRed: 0.89, green: 0.86, blue: 0.48, alpha: 1).cgColor)
    canvas.strokePath()
    canvas.restoreGState()
}

func leaf(from stem: CGPoint, to end: CGPoint, width: CGFloat) {
    let middle = CGPoint(x: (stem.x + end.x) / 2, y: (stem.y + end.y) / 2)
    let distance = hypot(end.x - stem.x, end.y - stem.y)
    let normal = CGPoint(x: -(end.y - stem.y) / distance * width,
                         y: (end.x - stem.x) / distance * width)
    let leafPath = CGMutablePath()
    leafPath.move(to: stem)
    leafPath.addQuadCurve(to: end, control: CGPoint(x: middle.x + normal.x, y: middle.y + normal.y))
    leafPath.addQuadCurve(to: stem, control: CGPoint(x: middle.x - normal.x, y: middle.y - normal.y))
    canvas.addPath(leafPath)
    canvas.setFillColor(NSColor(calibratedRed: 0.43, green: 0.66, blue: 0.23, alpha: 1).cgColor)
    canvas.fillPath()
}

canvas.setLineWidth(2)
canvas.setStrokeColor(NSColor(calibratedRed: 0.32, green: 0.52, blue: 0.20, alpha: 1).cgColor)
canvas.move(to: CGPoint(x: 600, y: 225))
canvas.addLine(to: CGPoint(x: 639, y: 269))
canvas.strokePath()
leaf(from: CGPoint(x: 627, y: 255), to: CGPoint(x: 633, y: 303), width: 11)
leaf(from: CGPoint(x: 630, y: 259), to: CGPoint(x: 683, y: 276), width: 12)
leaf(from: CGPoint(x: 605, y: 217), to: CGPoint(x: 641, y: 173), width: 11)

let pigWidth: CGFloat = 235
let pigHeight = pigWidth * CGFloat(extracted.height) / CGFloat(extracted.width)
canvas.interpolationQuality = .high
canvas.draw(extracted, in: CGRect(x: 365, y: 170, width: pigWidth, height: pigHeight))

canvas.setFillColor(NSColor(calibratedWhite: 0.15, alpha: 1).cgColor)
canvas.fillEllipse(in: CGRect(x: anchor.x - 3, y: anchor.y - 3, width: 6, height: 6))
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
("鼠标连接点" as NSString).draw(at: CGPoint(x: anchor.x + 20, y: anchor.y - 5),
                              withAttributes: [.font: NSFont.systemFont(ofSize: 13),
                                               .foregroundColor: NSColor.darkGray])
NSGraphicsContext.restoreGraphicsState()

save(canvas.makeImage()!, named: "bamboo-mode-preview.png")
precondition(extracted.width > 0 && extracted.height > 0)
print("PASS: extracted \(retained) original pig pixels, transparent crop \(extracted.width)x\(extracted.height)")
print("Preview: \(output.appendingPathComponent("bamboo-mode-preview.png").path)")