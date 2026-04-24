-- Per-run scoring state. Mirrors the iOS DrillMetrics model.
-- One singleton instance; reset() before each drill.

local M = {
  hits = 0,
  currentCombo = 0,
  maxCombo = 0,
  score = 0,
  -- Tracking drill state
  totalElapsed = 0,
  timeOnTarget = 0,
  timeOnBoth = 0,
  currentStreak = 0,
  maxStreak = 0,
  offTargetAccumulator = 0,
}

local OFF_TARGET_GRACE = 0.4  -- seconds

function M.reset()
  M.hits = 0
  M.currentCombo = 0
  M.maxCombo = 0
  M.score = 0
  M.totalElapsed = 0
  M.timeOnTarget = 0
  M.timeOnBoth = 0
  M.currentStreak = 0
  M.maxStreak = 0
  M.offTargetAccumulator = 0
end

function M.registerHit()
  M.hits = M.hits + 1
  M.score = M.score + M.currentCombo + 1
  M.currentCombo = M.currentCombo + 1
  if M.currentCombo > M.maxCombo then M.maxCombo = M.currentCombo end
end

function M.registerMiss()
  M.currentCombo = 0
end

-- Single-target tracking (unused in v1 drills but ready for later).
function M.accumulateTracking(delta, onTarget)
  M.totalElapsed = M.totalElapsed + delta
  if onTarget then
    M.timeOnTarget = M.timeOnTarget + delta
    M.currentStreak = M.currentStreak + delta
    M.offTargetAccumulator = 0
    if M.currentStreak > M.maxStreak then M.maxStreak = M.currentStreak end
  else
    M.offTargetAccumulator = M.offTargetAccumulator + delta
    if M.offTargetAccumulator >= OFF_TARGET_GRACE and M.currentStreak > 0 then
      M.currentStreak = 0
    end
  end
end

-- Dual-target tracking: streak breaks instantly on either off.
function M.accumulateTrackingDual(delta, leftOn, rightOn)
  M.totalElapsed = M.totalElapsed + delta
  local either = leftOn or rightOn
  local both = leftOn and rightOn
  if either then M.timeOnTarget = M.timeOnTarget + delta end
  if both then
    M.timeOnBoth = M.timeOnBoth + delta
    M.currentStreak = M.currentStreak + delta
    if M.currentStreak > M.maxStreak then M.maxStreak = M.currentStreak end
  else
    M.currentStreak = 0
  end
end

function M.timeOnTargetPercent()
  if M.totalElapsed <= 0 then return 0 end
  return (M.timeOnTarget / M.totalElapsed) * 100
end

function M.finalizeTrackingScore()
  local pctPart = math.floor(M.timeOnTargetPercent() * 10)
  local streakPart = math.floor(M.maxStreak * 20)
  M.score = pctPart + streakPart
end

function M.finalizeTrackingScoreDual()
  local timeOnOne = math.max(0, M.timeOnTarget - M.timeOnBoth)
  local onePart = math.floor(timeOnOne * 10)
  local bothPart = math.floor(M.timeOnBoth * 25)
  local streakPart = math.floor(M.maxStreak * 20)
  M.score = onePart + bothPart + streakPart
end

return M
