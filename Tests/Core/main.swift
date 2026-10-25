import Foundation
@testable import PigPendantCore

typealias Check = (name: String, run: () throws -> Void)
let settings = SettingsTests()
let simulation = SimulationTests()
let audio = AudioReactiveTests()
let character = RopeCharacterAnimationTests()
let halo = HaloAnimationTests()
let ghost = GhostBlinkTests()
let settingsChecks: [Check] = [
    ("settings.defaults-and-storage-keys", settings.testDefaultsAndOriginalStorageKeys),
    ("settings.editable-mode-defaults", settings.testEditableConfigurationProvidesModeSpecificRestoreDefaults),
    ("settings.legacy-configuration-wave-mode-migration",
     settings.testLegacyConfigurationAddsWaveGhostDefaultsWithoutReplacingCustomValues),
    ("settings.halo-spacing-independent-persistence",
     settings.testHaloSpacingPersistsIndependentlyByModeAndClampsToRange),
    ("settings.halo-size-independent-persistence",
     settings.testHaloSizePersistsIndependentlyByModeAndClampsToRange),
    ("settings.invalid-editable-defaults", settings.testInvalidEditableConfigurationIsRejected),
    ("settings.audio-reactive-scale-bounds", {
        try expectEqual(AudioReactiveScale.minimumScale, CGFloat(0.73))
        try expectEqual(AudioReactiveScale.maximumScale, CGFloat(1.6))
        try expectEqual(AudioReactiveScale.scale(forBeatStrength: 0, elapsed: 0),
                        AudioReactiveScale.minimumScale)
        try expectEqual(AudioReactiveScale.scale(forBeatStrength: 1, elapsed: 0),
                        AudioReactiveScale.maximumScale)
        let decayed = AudioReactiveScale.scale(forBeatStrength: 1, elapsed: 0.28)
        try expectGreaterThan(decayed, AudioReactiveScale.minimumScale)
        try expectLessThan(decayed, AudioReactiveScale.maximumScale)
        let rising = AudioReactiveScale.smoothed(current: 1, target: AudioReactiveScale.maximumScale,
                                                 elapsed: 1.0 / 60.0)
        let falling = AudioReactiveScale.smoothed(current: AudioReactiveScale.maximumScale,
                                                  target: AudioReactiveScale.minimumScale,
                                                  elapsed: 1.0 / 60.0)
        try expectGreaterThan(rising, CGFloat(1))
        try expectLessThan(rising, AudioReactiveScale.maximumScale)
        try expectGreaterThan(falling, AudioReactiveScale.minimumScale)
        try expectLessThan(falling, AudioReactiveScale.maximumScale)
    }),
    ("settings.finite-bounds", settings.testFiniteValuesClampAtBothBounds),
    ("settings.nonfinite-rejection", settings.testNonFiniteValuesAreRejectedWithoutChangingState),
    ("settings.mode-specific-parameter-roundtrip", settings.testRoundTripAndModeChangesPreserveIndependentParameters),
    ("settings.legacy-parameter-migration", settings.testLegacySharedParametersMigrateToEachMode),
    ("settings.new-mode-defaults-preserve-saved-values", settings.testNewWaveModeDefaultsDoNotTriggerLegacyMigrationForSavedModes),
    ("settings.ghost-offset-roundtrip", settings.testGhostOffsetsRoundTripIndependentlyOfMode),
    ("settings.single-key-save", settings.testSavingOneParameterDoesNotPopulateOtherKeys),
    ("settings.corrupt-saved-values", settings.testCorruptSavedValuesUseDefaultsAndFiniteValuesClamp),
    ("settings.mode-specific-labels", settings.testModeSpecificLabelsDoNotChangeStorageKeys)
]
let audioChecks: [Check] = [
    ("audio.repeated-kick-onsets", audio.testRepeatedLowFrequencyHitsProduceSeparatePulses),
    ("audio.steady-tone-does-not-repeat-beats", audio.testSteadyToneDoesNotProduceRepeatedPulses)
]
let simulationChecks: [Check] = [
    ("ghost.random-blinks-and-closed-hold", ghost.testRandomBlinksHaveClosedHoldAndIdenticalRest),
    ("ghost.seed-frame-rates-invalid-clock", ghost.testSeedFrameRatesAndInvalidClock),
    ("ghost.body-lag-continuity-settling", ghost.testBodyLagContinuityAndSettling),
    ("ghost.continuous-hem-frame-rates-loop-seam", ghost.testHemFlowsWithoutBlinksAcrossFrameRatesAndLoopSeam),
    ("ghost.hem-speed-response-frame-rates-recovery", ghost.testHemSpeedResponseContinuityFrameRatesAndRecovery),
    ("ghost.both-modes-mouse-speed-directions-resume", ghost.testBothGhostModesUseMouseSpeedInAllDirectionsAndResetMotion),
    ("ghost.independent-blink-halo-idle-resume", ghost.testGhostIdleUpdatesBlinkAndHaloWithoutRopeIntegration),
    ("ghost.wave-mode-independent-blink-halo-idle", ghost.testWaveGhostIdleUpdatesBlinkAndHaloWithoutRopeIntegration),
    ("halo.lag-rebound-settling-frame-rates", halo.testLagReboundAndSettlingAcrossFrameRates),
    ("halo.idle-spacing-invalid-input", halo.testIdleSpacingAndInvalidInput),
    ("halo.random-head-plane-directions", halo.testRandomIdleTravelsAcrossHeadPlane),
    ("halo.simulation-scheduling-resume-mode-reset", halo.testSimulationSchedulingResumeAndModeReset),
    ("simulation.eight-balloon-anchor-and-activity", simulation.testEightBalloonsShareAnchorAndNonFirstActivityPreventsIdle),
    ("simulation.count-extremes-and-mode-directions", simulation.testBalloonCountExtremesAndNonBalloonModesUseOneRope),
    ("simulation.net-idle-animation", simulation.testNetAnimationContinuesWithoutIntegratingSettledRope),
    ("simulation.settled-rope-nudge-swing", simulation.testSettledRopeNudgeTriggersSwingOnlyDuringStretchAction),
    ("simulation.rope-swing-amplitude", simulation.testSettledRopeSwingAmplitudeScalesAndCanBeDisabled),
    ("simulation.rope-idle-animation", simulation.testRopeCharacterAnimationContinuesWithoutIntegratingSettledRope),
    ("simulation.rope-animation-clock-and-physics", simulation.testRopeAnimationClockAndPhysicsAcrossFrameRates),
    ("simulation.local-characters-independent-of-physics", simulation.testLocalCharactersAnimateWithoutWakingPhysics),
    ("character.local-pose-continuity", character.testLocalPoseReturnsSmoothlyToRest),
    ("character.local-blink-progression-and-hold", character.testLocalBlinkHasProgressiveClosureHoldAndReopening),
    ("character.random-idle-gaps-and-actions", character.testIdleActionsHaveRandomGapsAndDoNotRepeat),
    ("character.movement-and-falling-reactions", character.testMouseMovementAndBobFallingTriggerDifferentActions),
    ("character.continuous-seam-weights", character.testTransitionsHaveContinuousWeightsAndNeverWrapLastToFirst),
    ("character.seeded-scheduling-and-frame-rates", character.testSchedulingIsSeededAndFrameRateIndependent),
    ("character.invalid-clock-and-reset", character.testInvalidClockDoesNotChangePlaybackAndResetReturnsToRest),
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
for check in settingsChecks + audioChecks + simulationChecks {
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
print("Core checks: \(settingsChecks.count + audioChecks.count + simulationChecks.count) cases, \(failures) failures")
exit(failures == 0 ? 0 : 1)
