import Foundation
@testable import PigPendantCore

typealias Check = (name: String, run: () throws -> Void)
let settings = SettingsTests()
let simulation = SimulationTests()
let settingsChecks: [Check] = [
    ("settings.defaults-and-storage-keys", settings.testDefaultsAndOriginalStorageKeys),
    ("settings.audio-reactive-scale-bounds", {
        try expectEqual(AudioReactiveScale.scale(forRMS: 0), CGFloat(0.55))
        try expectEqual(AudioReactiveScale.scale(forRMS: 1), CGFloat(1.4))
        try expectGreaterThan(AudioReactiveScale.scale(forRMS: 0.1), AudioReactiveScale.scale(forRMS: 0.001))
        let rising = AudioReactiveScale.smoothed(current: 1, target: 1.4, elapsed: 1.0 / 60.0)
        let falling = AudioReactiveScale.smoothed(current: 1.4, target: 0.55, elapsed: 1.0 / 60.0)
        try expectGreaterThan(rising, CGFloat(1))
        try expectLessThan(rising, CGFloat(1.4))
        try expectGreaterThan(falling, CGFloat(0.55))
        try expectLessThan(falling, CGFloat(1.4))
    }),
    ("settings.finite-bounds", settings.testFiniteValuesClampAtBothBounds),
    ("settings.nonfinite-rejection", settings.testNonFiniteValuesAreRejectedWithoutChangingState),
    ("settings.mode-specific-parameter-roundtrip", settings.testRoundTripAndModeChangesPreserveIndependentParameters),
    ("settings.legacy-parameter-migration", settings.testLegacySharedParametersMigrateToEachMode),
    ("settings.ghost-offset-roundtrip", settings.testGhostOffsetsRoundTripIndependentlyOfMode),
    ("settings.single-key-save", settings.testSavingOneParameterDoesNotPopulateOtherKeys),
    ("settings.corrupt-saved-values", settings.testCorruptSavedValuesUseDefaultsAndFiniteValuesClamp),
    ("settings.mode-specific-labels", settings.testModeSpecificLabelsDoNotChangeStorageKeys)
]
let simulationChecks: [Check] = [
    ("simulation.eight-balloon-anchor-and-activity", simulation.testEightBalloonsShareAnchorAndNonFirstActivityPreventsIdle),
    ("simulation.count-extremes-and-mode-directions", simulation.testBalloonCountExtremesAndNonBalloonModesUseOneRope),
    ("simulation.net-idle-animation", simulation.testNetAnimationContinuesWithoutIntegratingSettledRope),
    ("simulation.ghost-nearby-follow", simulation.testGhostFollowsNearbyWithoutUsingRopeMotion),
    ("simulation.bamboo-transition-before-idle", simulation.testBambooBendMustCompleteBeforeIdleAndMovementWakesIt),
    ("simulation.bamboo-large-vertical-shakes", simulation.testBambooVerticalShakesHaveNoPoseCuts),
    ("simulation.length-smooth-transition", simulation.testLengthChangesPreservePoseAndTransitionSmoothly),
    ("simulation.mode-specific-parameters-and-count", simulation.testApplyingModeUsesIndependentParametersAndRetainsCount),
    ("timeline.frame-order-duration-loop", simulation.testTimelineOriginalFrameOrderDurationAndLooping),
    ("timeline.elapsed-clamp-and-reset", simulation.testTimelineClampsElapsedAndResetStartsAtFirstFrame),
    ("physics.original-regression", simulation.testExistingPhysicsAndBambooRegression)
]

var failures = 0
for check in settingsChecks + simulationChecks {
    do {
        if settingsChecks.contains(where: { $0.name == check.name }) {
            try settings.setUpWithError()
            defer {
                do { try settings.tearDown() } catch {
                    failures += 1
                    fputs("FAIL: \(check.name) cleanup: \(error)\n", stderr)
                }
            }
            try check.run()
        } else {
            try check.run()
        }
        print("PASS: \(check.name)")
    } catch {
        failures += 1
        fputs("FAIL: \(check.name): \(error)\n", stderr)
    }
}
print("Core checks: \(settingsChecks.count + simulationChecks.count) cases, \(failures) failures")
exit(failures == 0 ? 0 : 1)
