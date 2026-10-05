local M = {}

M.flow = {
  countdownSeconds = 5,
  maxRunSeconds = 90,
  jumpStartSpeedKmh = 8,
  jumpStartPenaltyPoints = 10,
  spinAngleDeg = 105,
  spinGraceSeconds = 0.65,
  noProgressSeconds = 4,
  noProgressMeters = 8
}

M.scoring = {
  leadLinePoints = 35,
  leadAnglePoints = 35,
  leadStyleSpeedPoints = 30,
  progressBinMeters = 1,
  outerZoneLineWeight = 0.60,
  innerClipLineWeight = 0.30,
  pathLineWeight = 0.10,
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
  speedStyleWeight = 0.65,
  fluidityStyleWeight = 0.35,
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
    innerClips = {}
  }
end

return M
