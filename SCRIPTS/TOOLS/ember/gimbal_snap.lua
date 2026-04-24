-- Gimbal Snap: both sticks, X-axis target alternates per-side.
-- Discrete/hit drill. On iOS this uses release-based miss detection,
-- but physical sticks don't "release" — spring return is automatic.
-- Here we use overshoot detection: if the stick crosses the target
-- axis and lands on the wrong side (or well off-target), miss.
--
-- Rule: hit when stick enters the target zone. A miss is registered
-- if the stick reaches |x| >= 0.5 but is NOT on the current target
-- within the tolerance zone — i.e. you committed to a direction but
-- missed the target.

local osd = assert(loadScript("/SCRIPTS/TOOLS/ember/osd.lua"))()
local input = assert(loadScript("/SCRIPTS/TOOLS/ember/input.lua"))()
local metrics = assert(loadScript("/SCRIPTS/TOOLS/ember/metrics.lua"))()

local M = { id = "gimbal_snap", name = "GIMBAL SNAP", type = "discrete" }

local TOL = 0.26
local MAG = 0.75
local COMMIT = 0.5   -- |x| above this = you've committed to a direction

local state = {}

function M.start()
  state = {
    leftSign = -1, rightSign = -1,
    -- "armed" = stick has been near center since last hit/miss; needed
    -- so we don't re-fire miss while thumb loiters in wrong position.
    leftArmed = true, rightArmed = true,
    leftInZone = false, rightInZone = false,
  }
  metrics.reset()
end

local function tick(side, raw_x)
  local sign = side == "left" and state.leftSign or state.rightSign
  local targetX = sign * MAG
  local inZone = math.abs(raw_x - targetX) <= TOL

  -- Flag zone entry → hit.
  local prev = side == "left" and state.leftInZone or state.rightInZone
  if inZone and not prev then
    metrics.registerHit()
    playTone(1000, 60, 0, 0)
    if side == "left" then state.leftSign = -state.leftSign else state.rightSign = -state.rightSign end
    -- Disarm miss detection until the thumb returns toward center.
    if side == "left" then state.leftArmed = false else state.rightArmed = false end
  end

  -- Commit detection: if the pilot pushed the stick past COMMIT in the
  -- wrong direction (or far from target), and miss-detection is armed,
  -- register a miss and re-arm only once they center again.
  local committed = math.abs(raw_x) >= COMMIT
  local onTargetSide = (raw_x * sign) > 0
  local armed = side == "left" and state.leftArmed or state.rightArmed

  if committed and not inZone and armed then
    if not onTargetSide then
      -- Clear miss: pushed the opposite way.
      metrics.registerMiss()
      playTone(300, 80, 30, 0)
      playTone(250, 80, 0, 0)
      playHaptic(10, 2, 0)
      if side == "left" then state.leftArmed = false else state.rightArmed = false end
    end
  end

  -- Re-arm when thumb has returned near center.
  if math.abs(raw_x) < 0.15 then
    if side == "left" then state.leftArmed = true else state.rightArmed = true end
  end

  if side == "left" then state.leftInZone = inZone else state.rightInZone = inZone end
end

function M.update(dt)
  local lx, ly = input.readStick("left")
  local rx, ry = input.readStick("right")
  tick("left", lx)
  tick("right", rx)
  state._lx, state._ly = lx, ly
  state._rx, state._ry = rx, ry
end

function M.draw()
  osd.gimbalWell(osd.LEFT)
  osd.gimbalWell(osd.RIGHT)

  -- Targets
  local lt = state.leftSign * MAG
  local rt = state.rightSign * MAG
  osd.target(osd.LEFT,  lt, 0, state.leftInZone)
  osd.target(osd.RIGHT, rt, 0, state.rightInZone)

  -- Thumb dots
  if state._lx then osd.thumb(osd.LEFT,  state._lx, state._ly) end
  if state._rx then osd.thumb(osd.RIGHT, state._rx, state._ry) end

  osd.scoreRow({
    { label = "HITS",  value = tostring(metrics.hits) },
    { label = "COMBO", value = "x" .. metrics.currentCombo, highlight = metrics.currentCombo >= 3 },
    { label = "SCORE", value = tostring(metrics.score) },
  })
end

function M.result()
  return {
    score  = metrics.score,
    combo  = metrics.maxCombo,
    hits   = metrics.hits,
    streak = 0,
  }
end

return M
