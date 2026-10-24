import AppKit

struct ArtworkCatalog {
    static let ropeAttachment = NSPoint(x: 153.0 / 297, y: 29.0 / 266)

    let pig: NSImage
    let balloon: NSImage
    let bamboo: NSImage
    let hanging: NSImage
    let ghost: NSImage
    let net: AnimatedArtwork
    let rope: AnimatedArtwork

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
        hanging = try image("hanging-pig.png")
        ghost = try image("ghost-pig.png")
        net = try animation("net-pig.png")
        let ropeAnimation = try animation("rope-pig.png")
        guard ropeAnimation.frames.count == 75 else {
            throw ArtworkError.unreadable(directory.appendingPathComponent("rope-pig.png"))
        }
        rope = ropeAnimation
    }

    func image(mode: DisplayMode, frameIndex: Int) -> NSImage {
        switch mode {
        case .rope: return rope.frames[frameIndex]
        case .balloon: return balloon
        case .net: return net.frames[frameIndex]
        case .bamboo: return bamboo
        case .hanging: return hanging
        case .ghost: return ghost
        }
    }
}

enum ArtworkError: LocalizedError {
    case unreadable(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): return "无法读取或解码素材：\(url.lastPathComponent)"
        }
    }
}
