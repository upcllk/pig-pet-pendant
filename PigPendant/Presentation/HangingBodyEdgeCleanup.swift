import Foundation

enum HangingBodyEdgeCleanup {
    static func apply(to pixels: inout [UInt8], width: Int, height: Int) {
        let source = pixels
        func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }
        func isWhite(_ index: Int) -> Bool {
            let alpha = Double(source[index + 3])
            guard alpha > 0 else { return false }
            let values = (0..<3).map { Double(source[index + $0]) / alpha }
            return values.min()! > 0.65 && values.max()! > 0.82 && values.max()! - values.min()! < 0.28
        }
        var distances = [Int](repeating: 4, count: width * height)
        var queue: [Int] = []
        for y in 0..<height {
            for x in 0..<width where source[offset(x, y) + 3] == 0 {
                distances[y * width + x] = 0
                queue.append(y * width + x)
            }
        }
        var next = 0
        while next < queue.count {
            let pixel = queue[next]
            next += 1
            let distance = distances[pixel] + 1
            guard distance <= 3 else { continue }
            let x = pixel % width
            let y = pixel / width
            for dy in -1...1 {
                for dx in -1...1 where (0..<width).contains(x + dx) && (0..<height).contains(y + dy) {
                    let neighbor = (y + dy) * width + x + dx
                    if distance < distances[neighbor] {
                        distances[neighbor] = distance
                        queue.append(neighbor)
                    }
                }
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                let index = offset(x, y)
                let distance = distances[y * width + x]
                guard distance > 0 && distance <= 3, isWhite(index) else { continue }
                var nearest: Int?
                var best = Int.max
                for dy in -10...10 {
                    for dx in -10...10 where (0..<width).contains(x + dx) && (0..<height).contains(y + dy) {
                        let candidate = offset(x + dx, y + dy)
                        let squared = dx * dx + dy * dy
                        let alpha = Double(source[candidate + 3])
                        let red = Double(source[candidate]) / max(1, alpha)
                        let green = Double(source[candidate + 1]) / max(1, alpha)
                        let blue = Double(source[candidate + 2]) / max(1, alpha)
                        guard squared < best, alpha > 240, red > 0.8, green > 0.55,
                              red - blue > 0.18,
                              distances[(y + dy) * width + x + dx] >= 4 else { continue }
                        nearest = candidate
                        best = squared
                    }
                }
                guard let nearest = nearest else { continue }
                let coverage = distance == 1 ? 0.35 : distance == 2 ? 0.8 : 1
                let alpha = Double(source[index + 3]) * coverage
                for channel in 0..<3 {
                    pixels[index + channel] = UInt8((Double(source[nearest + channel])
                        / Double(source[nearest + 3]) * alpha).rounded())
                }
                pixels[index + 3] = UInt8(alpha.rounded())
            }
        }
    }
}
