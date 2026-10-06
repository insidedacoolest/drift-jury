local M = {}

M.flow = {
  countdownSeconds = 5,
  maxRunSeconds = 90,
  jumpStartSpeedKmh = 8, -- moving faster than this during the countdown invalidates the run
  spinAngleDeg = 105,
  spinGraceSeconds = 0.65,
  noProgressSeconds = 4,
  noProgressMeters = 8,
  -- Each rule below invalidates the run once its condition has held for the
  -- grace time, so a split-second blip (a transition, a bump) doesn't count.
  -- Driving against the course direction (velocity pointing back along the route).
  wrongWayMinSpeedKmh = 5,
  wrongWayGraceSeconds = 0.5,
  -- Straightening up (Drift Masters judging rules 2026, 1.7): once the drift
  -- has started, the angle dropping below straightenAngleDeg for a moment is
  -- a "short straightening (correction)" deduction; staying straight for
  -- stopDriftingSeconds is "stop drifting", an incomplete run. Neither counts
  -- in the last meters before the finish. The short grace lets a quick
  -- left/right transition pass through zero.
  straightenAngleDeg = 5,
  straightenGraceSeconds = 0.3,
  stopDriftingSeconds = 1.0,
  straightenDeduction = 5,
  -- Track limits: one or two wheels off is "tire off course" (deduction),
  -- three wheels off the marked track is an incomplete run.
  offTrackWheels = 3,
  offTrackGraceSeconds = 0.25,
  tireOffWheels = 1,
  tireOffDeduction = 5,
  -- Stopping: speed below this, once the car has launched (passed launchedSpeedKmh).
  launchedSpeedKmh = 15,
  stopSpeedKmh = 5,
  stopGraceSeconds = 1.0,
  -- Contact with a wall or another car never voids the run; each one takes
  -- points off, more for a harder hit. Hardness is the speed lost in the
  -- moments after the contact starts. Contacts within contactMergeSeconds
  -- of each other (a scrape along a wall) count once.
  contactMergeSeconds = 0.5,
  contactMeasureSeconds = 0.4,
  contactMediumLossKmh = 5,
  contactHardLossKmh = 15,
  contactLightPenalty = 5,
  contactMediumPenalty = 10,
  contactHardPenalty = 20,
  -- Accel/decel map: heavy footbrake or handbrake inside a green zone takes
  -- points off once per episode (thresholds in M.scoring, mapHeavy*).
  greenBrakeGraceSeconds = 0.15,
  greenBrakeDeduction = 5
}

M.scoring = {
  -- Qualifying scoring, Drift Masters judging rules 2026 (1.6/1.7): line 60,
  -- angle 20, style 20 = initiation 5 + fluidity 10 + commitment 5.
  leadLinePoints = 60,
  leadAnglePoints = 20,
  leadStyleSpeedPoints = 20,
  styleInitiationPoints = 5,
  styleFluidityPoints = 10,
  styleCommitmentPoints = 5,
  -- Line: every outer zone and inner clip is worth an equal share of the
  -- line points; staying on the drawn route ("off line") weighs this much.
  lineOffLineWeight = 0.10,
  -- Initiation (early, rate to angle, smooth). Early: the drift (minimum
  -- angle) is established within initiationFullMeters past the start
  -- exclusion, nothing after initiationZeroMeters. Rate to angle: meters from
  -- there to initiationRateAngleShare of the target angle. Smooth: angle given
  -- back inside the initiation window. Dropping out of the drift and
  -- initiating again in that window is a double initiation (scores 0).
  initiationFullMeters = 12,
  initiationZeroMeters = 40,
  initiationWindowMeters = 20,
  initiationRateAngleShare = 0.80,
  initiationRateFullMeters = 4,
  initiationRateZeroMeters = 16,
  initiationSmoothDropRangeDeg = 30,
  doubleInitiationFactor = 0,
  -- Fluidity: settled car (few abrupt corrections) and transitions that
  -- rotate quickly from high angle to high angle (lock to lock).
  fluidityTransitionWeight = 0.50,
  transitionFullMeters = 3,
  transitionZeroMeters = 12,
  transitionLockWindowMeters = 6,
  -- Commitment: pace (speed against the target), keeping that pace (no big
  -- speed drops) and consistent throttle.
  commitmentPaceWeight = 0.50,
  commitmentConsistencyWeight = 0.25,
  commitmentThrottleWeight = 0.25,
  commitmentDropRange = 0.35,
  commitmentThrottleOn = 0.60,
  commitmentFullThrottleShare = 0.70,
  -- Accuracy to the accel/decel map (Drift Masters 1.7, part of fluidity),
  -- only on layouts that have green or orange zones. Green: keep or gain
  -- speed with the throttle on. Orange: partial throttle or a small speed
  -- adjustment. Neither allows a heavy footbrake or handbrake. Red: free to
  -- slow down, not judged.
  fluidityMapWeight = 0.30,
  mapGreenSpeedToleranceKmh = 3,
  mapGreenMinThrottle = 0.30,
  mapOrangeMaxDropKmh = 12,
  mapHeavyBrake = 0.50,
  mapHeavyHandbrake = 0.50,
  progressBinMeters = 1,
  pathCorridorOutsideToleranceMeters = 3,
  progressSearchBackSegments = 2,
  progressSearchForwardSegments = 8,
  progressBacktrackToleranceMeters = 3,
  outerZoneFullDepthMeters = 0.35,
  outerZoneBoundaryQuality = 0.85,
  outerZoneOutsideToleranceMeters = 1,
  outerZonePlacementWeight = 0.70,
  outerZoneHoldWeight = 0.30,
  outerZoneBestAdjacentBins = 3,
  outerZoneFullHoldCoverage = 0.50,
  outerZoneCoverageQualityThreshold = 0.10,
  innerClipWindowMeters = 6,
  innerClipAdjacentBins = 3,
  minimumAngleDeg = 20,
  targetAngleDeg = 55,
  targetSpeedKmh = 90,
  startExclusionMeters = 8,
  finishExclusionMeters = 5,
  judgedFeatureWindowMeters = 8,
  transitionGraceMeters = 4,
  styleMinimumDriftAngleDeg = 15,
  styleFullDriftAngleDeg = 30,
  steeringDeadband = 8,
  throttleDeadband = 10,
  angleChangeDeadbandDeg = 4,
  steeringCorrectionRange = 64,
  throttleCorrectionRange = 80,
  angleCorrectionRangeDeg = 25,
  innerClipMaxDistanceMeters = 8
}

M.editor = {
  defaultPathCorridorHalfWidthMeters = 4,
  pathRecordingSpacingMeters = 5,
  pathRecordingStopExtraPointMinDistanceMeters = 1,
  startRadiusMeters = 2.5,
  finishWidthMeters = 14,
  clipRadiusMeters = 2
}

function M.newLayout(track, layout)
  return {
    version = 5,
    track = track or '',
    layout = layout or 'open',
    pathCorridorHalfWidthMeters = M.editor.defaultPathCorridorHalfWidthMeters,
    scoringOverrides = {},
    carScoringProfiles = {},
    leadStart = nil,
    finishGate = nil,
    pathWaypoints = {},
    outerZones = {},
    innerClips = {},
    speedZones = {}
  }
end

return M
