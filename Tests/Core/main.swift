import Foundation

typealias Check = (name: String, run: () throws -> Void)
let settings = SettingsTests()
let simulation = SimulationTests()
let settingsChecks: [Check] = [
    ("settings.defaults-and-storage-keys", settings.testDefaultsAndOriginalStorageKeys),
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
