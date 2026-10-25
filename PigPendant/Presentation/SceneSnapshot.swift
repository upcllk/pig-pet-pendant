import AppKit

struct RopeSnapshot {
    let nodes: [V2]
    let endPoint: V2
    let endAngle: CGFloat
    let width: CGFloat
    let characterImage: NSImage?
}

struct SceneSnapshot {
    let mode: DisplayMode
    let isVisible: Bool
    let pigSize: CGFloat
    let displayImage: NSImage
    let nextDisplayImage: NSImage?
    let imageBlend: CGFloat
    let haloImage: NSImage?
    let haloCenter: CGPoint
    let haloPose: HaloPose
    let ropes: [RopeSnapshot]
    let bambooPose: BambooPose?
    let ghostPosition: V2?
    let bounds: NSRect

    var imageAspect: CGFloat { displayImage.size.height / max(displayImage.size.width, 1) }

    init(simulation: PendantSimulation, artwork: ArtworkCatalog, isVisible: Bool) {
        let mode = simulation.settings.mode
        self.mode = mode
        self.isVisible = isVisible
        pigSize = CGFloat(simulation.settings[.size])
        displayImage = mode == .bamboo ? artwork.bambooCharacter.image(for: simulation.ropeAnimation.localPose)
            : mode == .net ? artwork.netCharacter.image(for: simulation.ropeAnimation.localPose)
            : mode == .hanging ? artwork.hangingCharacter.image(for: simulation.ropeAnimation.localPose)
            : artwork.image(mode: mode, frameIndex: simulation.artworkFrameIndex)
        let sample = simulation.ropeAnimation.sample
        nextDisplayImage = mode == .rope && sample.firstIndex != sample.secondIndex
            ? artwork.rope.frames[sample.secondIndex] : nil
        imageBlend = mode == .rope ? CGFloat(sample.fraction) : 0
        haloImage = mode == .hanging ? artwork.hangingLayers.halo : nil
        haloCenter = artwork.hangingLayers.center
        haloPose = simulation.haloAnimation.pose
        ropes = simulation.activeRopes.enumerated().map { index, rope in
            RopeSnapshot(nodes: rope.nodes, endPoint: rope.endPoint, endAngle: rope.endAngle,
                         width: simulation.balloonWidth(at: index),
                         characterImage: mode == .balloon
                            ? artwork.balloonCharacter.image(for: simulation.balloonAnimations[index].localPose) : nil)
        }
        bambooPose = mode == .bamboo ? simulation.bambooPose : nil
        ghostPosition = mode == .ghost ? simulation.ghostPosition : nil
        let nodes = bambooPose?.points ?? ghostPosition.map { [$0] } ?? ropes.flatMap(\.nodes)
        let padding = max(pigSize * (mode == .bamboo ? 3 : 1.2)
                          * max(1, displayImage.size.height / max(displayImage.size.width, 1)), 48) + 16
        let minX = nodes.map(\.x).min() ?? 0
        let maxX = nodes.map(\.x).max() ?? 0
        let minY = nodes.map(\.y).min() ?? 0
        let maxY = nodes.map(\.y).max() ?? 0
        bounds = NSRect(x: minX - padding, y: minY - padding,
                        width: maxX - minX + padding * 2, height: maxY - minY + padding * 2)
    }
}
