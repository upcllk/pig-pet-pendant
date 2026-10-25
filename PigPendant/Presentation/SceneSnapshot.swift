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
    let haloSpacing: CGFloat
    let haloScale: CGFloat
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
            : mode == .ghost ? artwork.ghostCharacters[simulation.ghostBlink.sample.firstIndex].image(for: simulation.ghostBody.pose)
            : mode == .ghostWave ? artwork.ghostWaveCharacter.image(for: simulation.ghostBody.pose,
                                                                     blinkSample: simulation.ghostBlink.sample)
            : mode == .net ? artwork.netCharacter.image(for: simulation.ropeAnimation.localPose)
            : mode == .hanging ? artwork.hangingCharacter.image(for: simulation.ropeAnimation.localPose)
            : artwork.image(mode: mode, frameIndex: simulation.artworkFrameIndex)
        let sample = mode == .ghost || mode == .ghostWave
            ? simulation.ghostBlink.sample : simulation.ropeAnimation.sample
        let frames = mode == .ghost ? artwork.ghostBlink.frames : artwork.rope.frames
        nextDisplayImage = mode == .ghost && sample.firstIndex != sample.secondIndex
            ? artwork.ghostCharacters[sample.secondIndex].image(for: simulation.ghostBody.pose)
            : mode == .rope && sample.firstIndex != sample.secondIndex ? frames[sample.secondIndex] : nil
        imageBlend = mode == .rope || mode == .ghost ? CGFloat(sample.fraction) : 0
        haloImage = mode == .ghost || mode == .ghostWave ? artwork.ghostHalo
            : mode == .hanging ? artwork.hangingLayers.halo : nil
        haloCenter = mode == .ghost || mode == .ghostWave
            ? artwork.ghostHaloCenter : artwork.hangingLayers.center
        haloPose = simulation.haloAnimation.pose
        haloSpacing = CGFloat(simulation.settings[haloSpacingFor: mode])
        haloScale = CGFloat(simulation.settings[haloSizeFor: mode] / HaloSize.defaultValue)
        ropes = simulation.activeRopes.enumerated().map { index, rope in
            RopeSnapshot(nodes: rope.nodes, endPoint: rope.endPoint, endAngle: rope.endAngle,
                         width: simulation.balloonWidth(at: index),
                         characterImage: mode == .balloon
                            ? artwork.balloonCharacter.image(for: simulation.balloonAnimations[index].localPose) : nil)
        }
        bambooPose = mode == .bamboo ? simulation.bambooPose : nil
        ghostPosition = simulation.isGhostMode ? simulation.ghostPosition : nil
        let nodes = bambooPose?.points ?? ghostPosition.map { [$0] } ?? ropes.flatMap(\.nodes)
        let imageAspect = displayImage.size.height / max(displayImage.size.width, 1)
        let padding = max(pigSize * (mode == .bamboo ? 3 : 1.2)
                          * max(1, imageAspect), 48)
            + 16 + abs(haloSpacing)
            + max(pigSize, pigSize * imageAspect) * max(0, haloScale - 1)
        let minX = nodes.map(\.x).min() ?? 0
        let maxX = nodes.map(\.x).max() ?? 0
        let minY = nodes.map(\.y).min() ?? 0
        let maxY = nodes.map(\.y).max() ?? 0
        bounds = NSRect(x: minX - padding, y: minY - padding,
                        width: maxX - minX + padding * 2, height: maxY - minY + padding * 2)
    }
}
