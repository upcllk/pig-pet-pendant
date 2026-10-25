import AppKit

struct ArtworkCatalog {
    static let ropeAttachment = NSPoint(x: 153.0 / 297, y: 29.0 / 266)

    let pig: NSImage
    let balloon: NSImage
    let bamboo: NSImage
    let hanging: NSImage
    let netImage: NSImage
    let ghost: NSImage
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
        ghost = try image("ghost-pig.png")
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
