import AppKit

struct ArtworkCatalog {
    static let ropeAttachment = NSPoint(x: 153.0 / 297, y: 29.0 / 266)

    let pig: NSImage
    let balloon: NSImage
    let bamboo: NSImage
    let hanging: NSImage
    let netImage: NSImage
    let ghost: NSImage
    let ghostBlink: AnimatedArtwork
    let ghostCharacters: [LocalCharacterArtwork]
    let ghostHalo: NSImage
    let ghostHaloCenter: CGPoint
    let net: AnimatedArtwork
    let rope: AnimatedArtwork
    let balloonCharacter: LocalCharacterArtwork
    let bambooCharacter: LocalCharacterArtwork
    let hangingCharacter: LocalCharacterArtwork
    let netCharacter: LocalCharacterArtwork
    let hangingLayers: HangingArtworkLayers

    init(resourceURL: URL) throws {
        let directory = resourceURL.deletingLastPathComponent()
        func image(_ name: String) throws -> NSImage {
            let url = directory.appendingPathComponent(name)
            guard let image = NSImage(contentsOf: url) else { throw ArtworkError.unreadable(url) }
            return image
        }
        func animation(_ name: String) throws -> AnimatedArtwork {
            let url = directory.appendingPathComponent(name)
            guard let animation = AnimatedArtwork(url: url) else { throw ArtworkError.unreadable(url) }
            return animation
        }
        pig = try image("pig.png")
        balloon = try image("balloon.png")
        bamboo = try image("bamboo-pig.png")
        let hangingSource = try image("hanging-pig-custom.png")
        let netSource = try image("net-pig-custom.png")
        guard let netCG = netSource.cgImage(forProposedRect: nil, context: nil, hints: nil),
              netCG.width == 768, netCG.height == 768,
              let cropped = netCG.cropping(to: CGRect(x: 256, y: 0, width: 512, height: 768)) else {
            throw ArtworkError.unreadable(directory.appendingPathComponent("net-pig-custom.png"))
        }
        netImage = NSImage(cgImage: cropped, size: NSSize(width: 512, height: 768))
        let ghostAnimation = try animation("ghost-blink.png")
        guard ghostAnimation.frames.count == 8,
              ghostAnimation.frames.allSatisfy({ $0.size == NSSize(width: 768, height: 1152) }) else {
            throw ArtworkError.unreadable(directory.appendingPathComponent("ghost-blink.png"))
        }
        ghostBlink = ghostAnimation
        ghostCharacters = try ghostAnimation.frames.map { try LocalCharacterArtwork(image: $0, mode: .ghost) }
        let haloImage = try image("ghost-halo.png")
        guard let haloCG = haloImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              haloCG.width == 768 && haloCG.height == 1152 else {
            throw ArtworkError.unreadable(directory.appendingPathComponent("ghost-halo.png"))
        }
        ghostHalo = haloImage
        let haloPixels = NSBitmapImageRep(cgImage: haloCG)
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0
        var total: CGFloat = 0
        for y in 0..<haloCG.height {
            for x in 0..<haloCG.width {
                let alpha = haloPixels.colorAt(x: x, y: y)?.alphaComponent ?? 0
                weightedX += CGFloat(x) * alpha
                weightedY += CGFloat(y) * alpha
                total += alpha
            }
        }
        guard total > 0 else { throw ArtworkError.unreadable(directory.appendingPathComponent("ghost-halo.png")) }
        ghostHaloCenter = CGPoint(x: weightedX / total / 768, y: 1 - weightedY / total / 1152)
        let composite = NSImage(size: ghostAnimation.frames[0].size)
        composite.lockFocus()
        let ghostRect = NSRect(origin: .zero, size: composite.size)
        ghostAnimation.frames[0].draw(in: ghostRect)
        haloImage.draw(in: ghostRect)
        composite.unlockFocus()
        ghost = composite
        net = try animation("net-pig.png")
        let ropeAnimation = try animation("rope-pig.png")
        guard ropeAnimation.frames.count == 75 else {
            throw ArtworkError.unreadable(directory.appendingPathComponent("rope-pig.png"))
        }
        rope = ropeAnimation
        hanging = try HangingBandTint.image(hangingSource, ropeReference: ropeAnimation.frames[0])
        balloonCharacter = try LocalCharacterArtwork(image: balloon, mode: .balloon)
        bambooCharacter = try LocalCharacterArtwork(image: bamboo, mode: .bamboo)
        let layers = try HangingArtworkLayers(image: hanging)
        hangingLayers = layers
        hangingCharacter = try LocalCharacterArtwork(image: layers.body, mode: .hanging)
        netCharacter = try LocalCharacterArtwork(image: netImage, mode: .net)
    }

    func image(mode: DisplayMode, frameIndex: Int) -> NSImage {
        switch mode {
        case .rope: return rope.frames[frameIndex]
        case .balloon: return balloon
        case .net: return netImage
        case .bamboo: return bamboo
        case .hanging: return hanging
        case .ghost: return ghost
        }
    }
}

enum ArtworkError: LocalizedError {
    case unreadable(URL)
    case invalidHangingLayers
    case invalidBandTint

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): return "无法读取或解码素材：\(url.lastPathComponent)"
        case .invalidHangingLayers: return "无法从猪上吊原素材安全分离光环，请检查素材尺寸及透明连通区域。"
        case .invalidBandTint: return "无法匹配绳子挂件绑绳颜色或定位猪上吊绑带，请检查参考素材。"
        }
    }
}
