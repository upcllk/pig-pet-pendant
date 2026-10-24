import AppKit

struct ArtworkCatalog {
    let pig: NSImage
    let balloon: NSImage
    let bamboo: NSImage
    let hanging: NSImage
    let ghost: NSImage
    let net: AnimatedArtwork

    init(resourceURL: URL) throws {
        let directory = resourceURL.deletingLastPathComponent()
        func image(_ name: String) throws -> NSImage {
            let url = directory.appendingPathComponent(name)
            guard let image = NSImage(contentsOf: url) else { throw ArtworkError.unreadable(url) }
            return image
        }
        pig = try image("pig.png")
        balloon = try image("balloon.png")
        bamboo = try image("bamboo-pig.png")
        hanging = try image("hanging-pig.png")
        ghost = try image("ghost-pig.png")
        let netURL = directory.appendingPathComponent("net-pig.png")
        guard let animation = AnimatedArtwork(url: netURL) else { throw ArtworkError.unreadable(netURL) }
        net = animation
    }

    func image(mode: DisplayMode, frameIndex: Int) -> NSImage {
        switch mode {
        case .rope: return pig
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
