-- Offset Chase: realistic FPV-flight target pattern.
-- Channel-based, mode-aware. Throttle modulates heavily, roll
-- modulates medium, pitch + yaw are small. Pilot follows with both
-- sticks. Dual-target tracking: 10 pts/sec one-on, 25 pts/sec both-on,
-- plus streak bonus on completion.

local osd = assert(loadScript("/SCRIPTS/TOOLS/ember/osd.lua"))()
local input = assert(loadScript("/SCRIPTS/TOOLS/ember/input.lua"))()
local metrics = assert(loadScript("/SCRIPTS/TOOLS/ember/metrics.lua"))()

local M = { id = "offset_chase", name = "OFFSET CHASE", type = "tracking_dual" }

local TOL = 0.22

local state = {}

-- Channel pattern generators, t in seconds.
local function throttleValue(t)
  return 0.80 * math.sin(t * 1.3) + 0.15 * math.sin(t * 3.1) + 0.05 * math.sin(t * 5.4)
end
local function pitchValue(t)
  return 0.40 * math.sin(t * 0.5) + 0.10 * math.sin(t * 1.7)
end
local function rollValue(t)
  return 0.85 * math.sin(t * 0.4) + 0.15 * math.sin(t * 1.1)
end
local function yawValue(t)
  return 0.40 * math.sin(t * 0.6) + 0.10 * math.sin(t * 1.4)
end

-- Build per-stick (x,y) target given elapsed time + channel map.
local function targetFor(side, t, map)
  local x, y = 0, 0
  local channels = {
    throttle = throttleValue(t),
    pitch    = pitchValue(t),
    roll     = rollValue(t),
    yaw      = yawValue(t),
  }
  for ch, loc in pairs(map) do
    if loc.side == side then
      if loc.axis == "x" then x = channels[ch] else y = channels[ch] end
    end
  end
  return x, y
end

function M.start()
  state = {
    elapsed = 0,
    map = input.channelMap(),
    leftOn = false,
    rightOn = false,
  }
  metrics.reset()
end

function M.update(dt)
  state.elapsed = state.elapsed + dt

  local ltx, lty = targetFor("left", state.elapsed, state.map)
  local rtx, rty = targetFor("right", state.elapsed, state.map)

  local lx, ly = input.readStick("left", state.map)
  local rx, ry = input.readStick("right", state.map)

  state.leftOn  = input.dist(lx, ly, ltx, lty) <= TOL
  state.rightOn = input.dist(rx, ry, rtx, rty) <= TOL

  metrics.accumulateTrackingDual(dt, state.leftOn, state.rightOn)

  state._lx, state._ly, state._rx, state._ry = lx, ly, rx, ry
  state._ltx, state._lty, state._rtx, state._rty = ltx, lty, rtx, rty
end

function M.draw()
  osd.gimbalWell(osd.LEFT)
  osd.gimbalWell(osd.RIGHT)

  osd.target(osd.LEFT,  state._ltx or 0, state._lty or 0, state.leftOn)
  osd.target(osd.RIGHT, state._rtx or 0, state._rty or 0, state.rightOn)

  if state._lx then osd.thumb(osd.LEFT,  state._lx, state._ly) end
  if state._rx then osd.thumb(osd.RIGHT, state._rx, state._ry) end

  local both = state.leftOn and state.rightOn
  local either = state.leftOn or state.rightOn
  local multLabel = both and "x2.5" or (either and "x1.0" or "x0")

  osd.scoreRow({
    { label = "ON",     value = string.format("%.0f%%", metrics.timeOnTargetPercent()) },
    { label = "MULT",   value = multLabel, highlight = both },
    { label = "STREAK", value = string.format("%.1fs", metrics.currentStreak), highlight = metrics.currentStreak >= 2 },
  })
end

function M.result()
  metrics.finalizeTrackingScoreDual()
  return {
    score  = metrics.score,
    combo  = 0,
    hits   = 0,
    streak = metrics.maxStreak,
  }
end

return M
