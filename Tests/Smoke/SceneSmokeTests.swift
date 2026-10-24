import AppKit

extension PendantCoordinator {
    func smokeCheckSceneIsolation() {
        let scale = CGFloat(1.5)
        let baseScene = SceneSnapshot(simulation: simulation, artwork: artwork, isVisible: isVisible)
        let scaledScene = SceneSnapshot(simulation: simulation, artwork: artwork,
                                        isVisible: isVisible, musicScale: scale)
        precondition(scaledScene.pigSize == baseScene.pigSize * scale)
        precondition(scaledScene.ropes.map(\.width) == baseScene.ropes.map { $0.width * scale })
        precondition(scaledScene.bounds.width > baseScene.bounds.width
                     && scaledScene.bounds.height > baseScene.bounds.height)
        let snapshot = sceneSnapshot()
        let heldNodes = snapshot.ropes.map(\.nodes)
        let heldBounds = snapshot.bounds
        if mode == .ghost {
            guard let heldPosition = snapshot.ghostPosition else {
                preconditionFailure("Ghost scene is missing its follow position")
            }
            let originalAnchor = ropeAnchor()
            validationAnchor = originalAnchor + V2(100, -80)
            simulation.advance(anchor: ropeAnchor(), elapsed: 1.0 / 60.0)
            let changed = sceneSnapshot()
            guard let changedPosition = changed.ghostPosition else {
                preconditionFailure("Updated ghost scene is missing its follow position")
            }
            precondition(snapshot.ghostPosition.map { ($0 - heldPosition).magnitude == 0 } ?? false)
            precondition((changedPosition - heldPosition).magnitude > 0)
            precondition(snapshot.bounds == heldBounds && changed.bounds != heldBounds)
            validationAnchor = originalAnchor
            reset()
            NSLog("PASS: ghost scene snapshots retain positions and bounds independently of mutable simulation")
            return
        }
        for rope in activeRopes { rope.reset(anchor: ropeAnchor() + V2(100, -80)) }
        let changed = sceneSnapshot()
        precondition(changed.ropes.count == heldNodes.count)
        for (index, rope) in snapshot.ropes.enumerated() {
            precondition(zip(rope.nodes, heldNodes[index]).allSatisfy { ($0 - $1).magnitude == 0 })
            precondition((changed.ropes[index].nodes[0] - rope.nodes[0]).magnitude > 100)
        }
        precondition(snapshot.bounds == heldBounds)
        precondition(changed.bounds != heldBounds)
        reset()
        NSLog("PASS: scene snapshots retain geometry and bounds independently of mutable simulation")
    }
}
