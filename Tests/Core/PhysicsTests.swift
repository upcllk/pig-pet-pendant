import Foundation
import CoreGraphics
#if SWIFT_PACKAGE
@testable import PigPendantCore
#endif

func runPhysicsTests() {
    require(BambooPigPosition.clamped(-1) == 0, "bamboo position clamps at the root")
    require(BambooPigPosition.clamped(101) == 100, "bamboo position clamps at the tip")
    require(BambooPigPosition.clamped(.nan) == nil, "bamboo position rejects non-finite values")
    func require(_ condition: Bool, _ message: String) {
        if !condition { fatalError("FAIL: \(message)") }
    }
    var halfWay: [CGFloat] = []
    for rate in [30, 60, 120, 144] {
        var bend = BambooBend()
        for _ in 0..<(rate * 2) { bend.advance(elapsed: 1 / CGFloat(rate), moving: true) }
        require(bend.progress == 0 && abs(bend.angle) < 0.0001, "moving bamboo becomes horizontal")
        var previousAngle = bend.angle
        for index in 0..<(rate * 3) {
            bend.advance(elapsed: 1 / CGFloat(rate), moving: false)
            require(bend.angle <= previousAngle + 0.00001, "clockwise bend without reversal")
            previousAngle = bend.angle
            if index == rate - 1 { halfWay.append(bend.progress) }
        }
        require(bend.isSettled && abs(bend.angle + .pi / 2) < 0.0001, "stationary bamboo becomes vertical")
        for _ in 0..<(rate * 2) { bend.advance(elapsed: 1 / CGFloat(rate), moving: true) }
        require(bend.progress == 0, "bamboo returns horizontally on renewed motion")
    }
    require((halfWay.max()! - halfWay.min()!) < 0.025, "bamboo transition frame-rate independence")
    var interruptedBend = BambooBend(progress: 0.45)
    for _ in 0..<6 { interruptedBend.advance(elapsed: 1 / 60, moving: true) }
    let angleAtStop = interruptedBend.angle
    for _ in 0..<12 { interruptedBend.advance(elapsed: 1 / 60, moving: false) }
    require(abs(interruptedBend.angle - angleAtStop) < 0.2,
            "stopping at an oblique angle does not snap bamboo horizontal")
    let angleAfterPause = interruptedBend.angle
    for _ in 0..<60 { interruptedBend.advance(elapsed: 1 / 60, moving: false) }
    require(interruptedBend.angle < angleAfterPause, "bamboo bends down from its interrupted angle")

    var bambooSettings = PendantSettings()
    bambooSettings.mode = .bamboo
    let simulation = PendantSimulation(settings: bambooSettings,
                                      frameDurations: Array(repeating: 0.04, count: 62),
                                      ropeFrameDurations: Array(repeating: 0.04, count: 75))
    let jitterAnchor = V2(-500, 300)
    simulation.reset(anchor: jitterAnchor)
    simulation.bambooBend = BambooBend(progress: 0.45)
    for index in 0..<20 {
        let jitter = index.isMultiple(of: 2) ? CGFloat(0.25) : CGFloat(-0.25)
        simulation.advance(anchor: jitterAnchor + V2(jitter, 0), elapsed: 1.0 / 60.0)
    }
    require(simulation.bambooBend.progress > 0.45,
            "sub-point cursor jitter does not return bamboo to horizontal")

    let anchor = V2(-500, 300)
    var previousPigDistance = CGFloat.infinity
    for progress in (0...40).map({ CGFloat($0) / 40 }) {
        let pose = BambooPose(anchor: anchor, length: 180, bend: BambooBend(progress: progress), sway: 0)
        let pigDistance = pose.pigDistanceFromTip(width: 48)
        require(pigDistance <= previousPigDistance + 0.001, "pig slides toward bamboo tip as it bends")
        if progress == 0 {
            require(abs(pigDistance - 90) < 0.1, "default pig position is the bamboo midpoint")
            let quarterPosition = BambooPose(anchor: anchor, length: 180,
                                             bend: BambooBend(progress: 0), sway: 0,
                                             initialPosition: 0.25)
            require(abs(quarterPosition.pigDistanceFromTip(width: 48) - 135) < 0.1,
                    "bamboo position slider locates pig from the root percentage")
        }
        if progress == 1 {
            require(abs(pigDistance - 14.4) < 0.1, "pig settles near the bamboo tip")
        }
        previousPigDistance = pigDistance
        require((pose.points.first! - anchor).magnitude < 0.0001, "single bamboo begins at cursor anchor")
        require((pose.points.last! - pose.tip).magnitude < 0.0001, "single bamboo ends at pig attachment")
        let arcLength = zip(pose.points.dropFirst(), pose.points).reduce(CGFloat(0)) {
            $0 + ($1.0 - $1.1).magnitude
        }
        require(abs(arcLength - 180) < 1, "single curved bamboo preserves approximate arc length")
        require(pose.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "finite bamboo curve")
        for width: CGFloat in [16, 48, 88, 256] {
            for length in [width * 1.5, max(width * 1.5, 180), CGFloat(1200)] {
                let loaded = BambooPose(anchor: anchor, length: length,
                                        bend: BambooBend(progress: progress), sway: 0.4)
                let grip = loaded.grip(width: width)
                for foot in BambooPose.feet {
                    let contact = loaded.contact(for: foot, width: width)
                    if foot.x == BambooPose.frontFoot.x {
                        require(contact.y >= foot.y - 0.001 && contact.y < 0.19,
                                "bamboo crosses the original middle paw, not the torso")
                    } else {
                        require((contact - foot).magnitude < 0.001,
                                "original short front and rear feet stay attached without deformation")
                    }
                    let source = contact * width
                    let location = grip.origin + V2(source.x * cos(grip.angle) - source.y * sin(grip.angle),
                                                    source.x * sin(grip.angle) + source.y * cos(grip.angle))
                    let distance = zip(loaded.points, loaded.points.dropFirst()).map { start, end -> CGFloat in
                        let delta = end - start
                        let offset = location - start
                        let projection = max(0, min(1, (offset.x * delta.x + offset.y * delta.y)
                                                   / (delta.x * delta.x + delta.y * delta.y)))
                        return (location - start - delta * projection).magnitude
                    }.min()!
                    require(distance < 0.001, "all three pig feet stay on curved bamboo at all sizes")
                }
            }
        }
        if progress == 0.5 {
            let delta = pose.points[12] - (anchor + pose.tip) * 0.5
            require(delta.magnitude > 5, "intermediate bamboo visibly bends instead of rigid rotation")
        }
        if progress == 1 {
            let chord = pose.tip - anchor
            let middle = pose.points[12] - anchor
            let crossProduct: CGFloat = chord.x * middle.y - chord.y * middle.x
            let chordLength: CGFloat = chord.magnitude
            let deviation: CGFloat = abs(crossProduct) / chordLength
            require(deviation > 180 * 0.15, "settled bamboo keeps a visible loaded curve")
            let rootTangent = pose.points[1] - pose.points[0]
            let tipTangent = pose.points[24] - pose.points[23]
            require(rootTangent.x > abs(rootTangent.y) * 5, "settled bamboo root stays near horizontal")
            require(-tipTangent.y > abs(tipTangent.x) * 5, "settled bamboo tip hangs down")
        }
    }
    print("PASS: single bamboo curve, 41-phase original-proportion three-paw contact, clockwise bend, horizontal recovery, 30/60/120/144 Hz transition")
    func checkRope(_ rope: RopePhysics) {
        require(rope.nodes.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "finite nodes")
        for index in 0..<rope.segments {
            require((rope.nodes[index + 1] - rope.nodes[index]).magnitude <= rope.maximumSegmentLength + 0.001,
                    "bounded segment length")
        }
    }
    func trajectory(rate: Int, direction: V2 = V2(0, -1)) -> V2 {
        let rope = RopePhysics()
        rope.forceDirection = direction
        rope.reset(anchor: V2(-800, 250))
        for frame in 1...(rate * 2) {
            rope.advance(anchor: V2(-800 + 120 * CGFloat(frame) / CGFloat(rate), 250),
                         timeStep: 1 / CGFloat(rate))
            checkRope(rope)
        }
        return rope.endPoint
    }
    let reference = trajectory(rate: 120)
    for rate in [30, 60, 144] {
        require((trajectory(rate: rate) - reference).magnitude < 2, "frame-rate independence at \(rate) Hz")
    }
    let floatingReference = trajectory(rate: 120, direction: V2(0.5, 1))
    for rate in [30, 60, 144] {
        require((trajectory(rate: rate, direction: V2(0.5, 1)) - floatingReference).magnitude < 2,
                "balloon frame-rate independence at \(rate) Hz")
    }
    for horizontal: CGFloat in [-0.65, 0, 0.65] {
        for length: CGFloat in [20, 140, 1200] {
            let balloon = RopePhysics()
            balloon.forceDirection = V2(horizontal, 1)
            balloon.length = length
            balloon.reset(anchor: V2(-400, -300))
            require(balloon.endPoint.y > -300 && balloon.isSettled, "balloon floats above anchor")
            for frame in 0..<360 {
                balloon.advance(anchor: V2(-400 + sin(CGFloat(frame) / 8) * 250, -300),
                                timeStep: balloon.fixedStep)
                checkRope(balloon)
            }
            for _ in 0..<36000 {
                balloon.advance(anchor: V2(-400, -300), timeStep: balloon.fixedStep)
                checkRope(balloon)
            }
            require(balloon.isSettled && balloon.endPoint.y > -300, "floating rope settles above mouse")
        }
    }
    for length: CGFloat in [20, 60, 100, 140, 180, 220, 400, 600, 1200] {
        let rope = RopePhysics()
        rope.length = length
        rope.reset(anchor: V2(0, 0))
        let initialEnd = rope.endPoint
        let segmentLength = length / CGFloat(rope.segments)
        rope.advance(anchor: V2(0, -segmentLength * 0.5), timeStep: rope.fixedStep)
        require((rope.nodes[1] - rope.nodes[0]).magnitude < segmentLength * 0.75,
            "rope slackens instead of pushing")
        require((rope.endPoint - initialEnd).magnitude < 1, "bob retains inertia when rope slackens")
        for frame in 0..<1200 {
            let time = CGFloat(frame) / 120
            rope.advance(anchor: V2(sin(time * 15) * 400 - 1000, cos(time * 11) * 150), timeStep: 1 / 120)
            checkRope(rope)
        }
        rope.advance(anchor: V2(-3000, -900), timeStep: 1 / 60)
        checkRope(rope)
        let beforeLongFrame = rope.nodes
        let angleBeforeLongFrame = rope.endAngle
        rope.advance(anchor: V2(-2900, -900), timeStep: 2)
        require(abs(rope.endAngle - angleBeforeLongFrame) < 0.0001, "long frame preserves rope angle")
        for index in rope.nodes.indices {
            require((rope.nodes[index] - beforeLongFrame[index] - V2(100, 0)).magnitude < 0.001,
                    "long frame translates rope pose without resetting")
        }
        for _ in 0..<120 { rope.advance(anchor: V2(-2800, -900), timeStep: 1 / 120) }
        for _ in 0..<7200 { rope.advance(anchor: V2(-2800, -900), timeStep: 1 / 120) }
        require(rope.isSettled, "settles after motion at length \(length)")
    }
    for length: CGFloat in [20, 1200] {
        for gravity: CGFloat in [100, 10000] {
            for rate in [0.2, 8.0] {
                let rope = RopePhysics()
                rope.length = length
                rope.gravity = gravity
                rope.dampingPerFrame = CGFloat(exp(-rate / 60))
                rope.reset(anchor: V2(0, 0))
                for frame in 0..<240 {
                    rope.advance(anchor: V2(sin(CGFloat(frame) / 12) * 180, 0), timeStep: rope.fixedStep)
                    checkRope(rope)
                }
                for _ in 0..<36000 {
                    rope.advance(anchor: V2(0, 0), timeStep: rope.fixedStep)
                    checkRope(rope)
                }
                require(rope.isSettled, "settles across settings ranges")
            }
        }
    }
    func pullResponse(weight: CGFloat, elasticity: CGFloat) -> CGFloat {
        let rope = RopePhysics()
        rope.forceDirection = V2(0, 1)
        rope.weight = weight
        rope.elasticity = elasticity
        rope.reset(anchor: V2(0, 0))
        for _ in 0..<1200 { rope.advance(anchor: V2(0, 0), timeStep: rope.fixedStep) }
        let start = rope.endPoint
        for frame in 1...12 {
            rope.advance(anchor: V2(0, -CGFloat(frame) * 0.25), timeStep: rope.fixedStep)
            checkRope(rope)
        }
        return start.y - rope.endPoint.y
    }
    let light = pullResponse(weight: 0, elasticity: 65)
    let heavy = pullResponse(weight: 100, elasticity: 65)
        require(light > 0 && heavy >= 0 && heavy < light * 0.85,
            "heavy bob lags more: light=\(light), heavy=\(heavy)")
        let rigid = pullResponse(weight: 65, elasticity: 0)
        let elastic = pullResponse(weight: 65, elasticity: 100)
        require(elastic >= 0 && elastic < rigid * 0.85,
            "elastic rope delays pulling: rigid=\(rigid), elastic=\(elastic)")
        print(String(format: "Pull response in 0.1 s (3 pt input): light=%.3f heavy=%.3f rigid=%.3f elastic=%.3f pt",
             Double(light), Double(heavy), Double(rigid), Double(elastic)))
    for weight: CGFloat in [0, 100, 200] {
        for elasticity: CGFloat in [0, 100, 200] {
            let rope = RopePhysics()
            rope.forceDirection = V2(-0.65, 1)
            rope.length = 1200
            rope.weight = weight
            rope.elasticity = elasticity
            rope.gravity = 10000
            rope.dampingPerFrame = CGFloat(exp(-0.2 / 60))
            rope.reset(anchor: V2(0, 0))
            for frame in 0..<240 {
                rope.advance(anchor: V2(sin(CGFloat(frame) / 8) * 500, 0), timeStep: rope.fixedStep)
                checkRope(rope)
            }
            for _ in 0..<36000 {
                rope.advance(anchor: V2(0, 0), timeStep: rope.fixedStep)
                checkRope(rope)
            }
            require(rope.isSettled, "weight/elasticity extremes settle: \(weight)/\(elasticity)")
            let end = rope.endPoint
            rope.settle()
            require((rope.endPoint - end).magnitude < 0.00001, "idle preserves loaded rope shape")
        }
    }
    print("PASS: upward balloons, tilted buoyancy, fixed-step 30/60/120/144 Hz, rapid reversals, negative coordinates, 12% stretch cap, slack, heavy-bob lag, resume, settling; 9 rope lengths and expanded gravity/damping/weight/elasticity extremes")
}
