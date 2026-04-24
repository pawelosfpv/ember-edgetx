-- Stick input + mode-aware channel resolution.
-- Raw stick values are read by physical position (thr/ele/ail/rud is
-- already the correct stick per the radio's mode config — EdgeTX does
-- the mapping for us).

local M = {}

-- Read all four sticks normalized to [-1, 1].
function M.readSticks()
  local thr = getValue("thr") / 1024
  local ele = getValue("ele") / 1024
  local ail = getValue("ail") / 1024
  local rud = getValue("rud") / 1024
  return thr, ele, ail, rud
end

-- Map each channel to its physical stick+axis given current stick mode.
-- Returns: { throttle={side, axis}, pitch=..., roll=..., yaw=... }
-- side: "left" | "right"   axis: "x" | "y"
--
-- stickMode value from getGeneralSettings():
--   0 = Mode 1, 1 = Mode 2, 2 = Mode 3, 3 = Mode 4
function M.channelMap()
  local gs = getGeneralSettings()
  local mode = (gs and gs.stickMode) or 1  -- default Mode 2
  if mode == 0 then
    return {
      throttle = { side = "right", axis = "y" },
      pitch    = { side = "left",  axis = "y" },
      roll     = { side = "right", axis = "x" },
      yaw      = { side = "left",  axis = "x" },
    }
  elseif mode == 2 then
    return {
      throttle = { side = "right", axis = "y" },
      pitch    = { side = "left",  axis = "y" },
      roll     = { side = "left",  axis = "x" },
      yaw      = { side = "right", axis = "x" },
    }
  elseif mode == 3 then
    return {
      throttle = { side = "left",  axis = "y" },
      pitch    = { side = "right", axis = "y" },
      roll     = { side = "left",  axis = "x" },
      yaw      = { side = "right", axis = "x" },
    }
  else
    -- Mode 2 (default)
    return {
      throttle = { side = "left",  axis = "y" },
      pitch    = { side = "right", axis = "y" },
      roll     = { side = "right", axis = "x" },
      yaw      = { side = "left",  axis = "x" },
    }
  end
end

-- Read a stick's normalized (x, y) position given a side.
-- Uses the mode-aware map so we know which raw sources feed which stick.
-- Returns two numbers in [-1, 1], y-up.
function M.readStick(side, map)
  map = map or M.channelMap()
  -- Find which channels live on this side.
  local x, y = 0, 0
  local function src(channel)
    if channel == "throttle" then return getValue("thr") / 1024
    elseif channel == "pitch" then return getValue("ele") / 1024
    elseif channel == "roll"  then return getValue("ail") / 1024
    elseif channel == "yaw"   then return getValue("rud") / 1024
    end
  end
  for ch, loc in pairs(map) do
    if loc.side == side then
      if loc.axis == "x" then x = src(ch) else y = src(ch) end
    end
  end
  return x, y
end

-- Distance between two normalized points.
function M.dist(x1, y1, x2, y2)
  local dx, dy = x1 - x2, y1 - y2
  return math.sqrt(dx * dx + dy * dy)
end

return M
