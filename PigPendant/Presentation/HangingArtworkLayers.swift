import AppKit

struct HangingArtworkLayers {
    let body: NSImage
    let halo: NSImage
    let center: CGPoint

    init(image: NSImage) throws {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width == 360, cg.height == 384 else { throw ArtworkError.invalidHangingLayers }
        let width = cg.width
        let height = cg.height
        let bitmap = NSBitmapImageRep(cgImage: cg)
        var visited = [Bool](repeating: false, count: width * height)
        var mask = visited
        var bounds = CGRect.null
        for first in visited.indices where !visited[first] {
            guard (bitmap.colorAt(x: first % width, y: first / width)?.alphaComponent ?? 0) > 0 else {
                visited[first] = true
                continue
            }
            var component = [first]
            var index = 0
            var componentBounds = CGRect.null
            visited[first] = true
            while index < component.count {
                let pixel = component[index]
                index += 1
                let x = pixel % width
                let y = pixel / width
                componentBounds = componentBounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                for dy in -1...1 {
                    for dx in -1...1 where (0..<width).contains(x + dx) && (0..<height).contains(y + dy) {
                        let next = (y + dy) * width + x + dx
                        guard !visited[next] else { continue }
                        visited[next] = true
                        if (bitmap.colorAt(x: x + dx, y: y + dy)?.alphaComponent ?? 0) > 0 {
                            component.append(next)
                        }
                    }
                }
            }
            if CGRect(x: 235, y: 201, width: 121, height: 143).contains(componentBounds) {
                bounds = bounds.union(componentBounds)
                for pixel in component { mask[pixel] = true }
            }
        }
        guard mask.filter({ $0 }).count > 4000, !bounds.isNull else {
            throw ArtworkError.invalidHangingLayers
        }
        center = CGPoint(x: bounds.midX / CGFloat(width), y: 1 - bounds.midY / CGFloat(height))
        func layer(halo: Bool) throws -> NSImage {
            let alphaMask: [UInt8] = mask.map { $0 == halo ? 0 : 255 }
            guard let provider = CGDataProvider(data: Data(alphaMask) as CFData),
                  let imageMask = CGImage(maskWidth: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                                          bytesPerRow: width, provider: provider, decode: nil, shouldInterpolate: false),
                  let resultImage = cg.masking(imageMask) else { throw ArtworkError.invalidHangingLayers }
            return NSImage(cgImage: resultImage, size: image.size)
        }
        body = try layer(halo: false)
        halo = try layer(halo: true)
    }
}
