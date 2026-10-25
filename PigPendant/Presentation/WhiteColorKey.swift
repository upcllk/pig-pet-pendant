import Foundation

enum WhiteColorKey {
    static func retainedCoverage(red: Double, green: Double, blue: Double) -> Double {
        let minimum = min(red, green, blue)
        let chroma = max(red, green, blue) - minimum
        guard chroma <= 0.22 else { return 1 }
        if minimum >= 0.78 { return 0 }
        if minimum <= 0.68 { return 1 }
        let transition = (minimum - 0.68) / 0.10
        return 1 - transition * transition * (3 - 2 * transition)
    }

    static func apply(to pixels: inout [UInt8], width: Int, height: Int) {
        let source = pixels
        var eligible = [Bool](repeating: false, count: width * height)
        var visited = eligible
        var distance = [Int](repeating: 4, count: width * height)
        var queue: [Int] = []
        for pixel in eligible.indices {
            let index = pixel * 4
            let alpha = Double(source[index + 3])
            if alpha == 0 {
                visited[pixel] = true
                distance[pixel] = 0
                queue.append(pixel)
            } else {
                eligible[pixel] = retainedCoverage(red: Double(source[index]) / alpha,
                                                   green: Double(source[index + 1]) / alpha,
                                                   blue: Double(source[index + 2]) / alpha) < 1
            }
        }
        let transparentCount = queue.count
        var next = 0
        while next < queue.count {
            let pixel = queue[next]
            next += 1
            guard distance[pixel] < 3 else { continue }
            let x = pixel % width
            let y = pixel / width
            for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                guard (0..<width).contains(x + dx), (0..<height).contains(y + dy) else { continue }
                let neighbor = (y + dy) * width + x + dx
                if distance[neighbor] > distance[pixel] + 1 {
                    distance[neighbor] = distance[pixel] + 1
                    queue.append(neighbor)
                }
            }
        }
        queue.removeSubrange(transparentCount..<queue.count)
        next = 0
        while next < queue.count {
            let pixel = queue[next]
            next += 1
            let x = pixel % width
            let y = pixel / width
            for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                guard (0..<width).contains(x + dx), (0..<height).contains(y + dy) else { continue }
                let neighbor = (y + dy) * width + x + dx
                if !visited[neighbor] && eligible[neighbor] && distance[neighbor] <= 3 {
                    visited[neighbor] = true
                    queue.append(neighbor)
                }
            }
        }
        for index in stride(from: 0, to: pixels.count, by: 4) {
            guard visited[index / 4] else { continue }
            let alpha = Double(pixels[index + 3])
            guard alpha > 0 else { continue }
            let coverage = retainedCoverage(red: Double(pixels[index]) / alpha,
                                            green: Double(pixels[index + 1]) / alpha,
                                            blue: Double(pixels[index + 2]) / alpha)
            guard coverage < 1 else { continue }
            for channel in 0..<4 {
                pixels[index + channel] = UInt8((Double(pixels[index + channel]) * coverage).rounded())
            }
            let remainingAlpha = Double(pixels[index + 3])
            if remainingAlpha > 0 &&
                retainedCoverage(red: Double(pixels[index]) / remainingAlpha,
                                 green: Double(pixels[index + 1]) / remainingAlpha,
                                 blue: Double(pixels[index + 2]) / remainingAlpha) == 0 {
                for channel in 0..<4 { pixels[index + channel] = 0 }
            }
        }
    }
}
