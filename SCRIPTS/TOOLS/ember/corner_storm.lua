-- Corner Storm: cycle through 4 corners, both sticks together.
-- Discrete drill. Target advances when BOTH thumbs land on the active
-- corner. Miss = after committing (either stick into a commit zone)
-- without both landing.

local osd = assert(loadScript("/SCRIPTS/TOOLS/ember/osd.lua"))()
local input = assert(loadScript("/SCRIPTS/TOOLS/ember/input.lua"))()
local metrics = assert(loadScript("/SCRIPTS/TOOLS/ember/metrics.lua"))()

local M = { id = "corner_storm", name = "CORNER STORM", type = "discrete" }

local CORNERS = {
  { x = -0.78, y =  0.78 },
  { x =  0.78, y =  0.78 },
  { x =  0.78, y = -0.78 },
  { x = -0.78, y = -0.78 },
}
local TOL = 0.28
local COMMIT = 0.5

local state = {}

function M.start()
  state = { index = 1, armed = true, leftIn = false, rightIn = false }
  metrics.reset()
end

local function inZone(sx, sy, target)
  return input.dist(sx, sy, target.x, target.y) <= TOL
end

function M.update(dt)
  local lx, ly = input.readStick("left")
  local rx, ry = input.readStick("right")
  local target = CORNERS[state.index]

  state.leftIn  = inZone(lx, ly, target)
  state.rightIn = inZone(rx, ry, target)

  if state.leftIn and state.rightIn then
    metrics.registerHit()
    playTone(1000, 60, 0, 0)
    state.index = (state.index % #CORNERS) + 1
    state.armed = false
  end

  -- Commit detection: if either stick is hard into a quadrant that
  -- isn't the target's quadrant, count a miss.
  local committed = (math.abs(lx) >= COMMIT or math.abs(ly) >= COMMIT) or
                    (math.abs(rx) >= COMMIT or math.abs(ry) >= COMMIT)
  local sameSignX = (lx * target.x) > 0 and (rx * target.x) > 0
  local sameSignY = (ly * target.y) > 0 and (ry * target.y) > 0

  if committed and state.armed and not (sameSignX and sameSignY) then
    metrics.registerMiss()
    playTone(300, 80, 30, 0)
    playTone(250, 80, 0, 0)
    playHaptic(10, 2, 0)
    state.armed = false
  end

  if math.abs(lx) < 0.15 and math.abs(ly) < 0.15
     and math.abs(rx) < 0.15 and math.abs(ry) < 0.15 then
    state.armed = true
  end

  state._lx, state._ly, state._rx, state._ry = lx, ly, rx, ry
end

function M.draw()
  osd.gimbalWell(osd.LEFT)
  osd.gimbalWell(osd.RIGHT)

  local t = CORNERS[state.index]
  osd.target(osd.LEFT,  t.x, t.y, state.leftIn)
  osd.target(osd.RIGHT, t.x, t.y, state.rightIn)

  if state._lx then osd.thumb(osd.LEFT,  state._lx, state._ly) end
  if state._rx then osd.thumb(osd.RIGHT, state._rx, state._ry) end

  osd.scoreRow({
    { label = "CORNERS", value = tostring(metrics.hits) },
    { label = "COMBO",   value = "x" .. metrics.currentCombo, highlight = metrics.currentCombo >= 4 },
    { label = "SCORE",   value = tostring(metrics.score) },
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
