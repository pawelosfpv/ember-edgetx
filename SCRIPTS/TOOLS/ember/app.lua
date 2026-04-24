-- Ember app state machine: picker → countdown → drill → complete.
-- EXIT rules:
--   EXIT during drill  → abort (no score saved, back to picker)
--   EXIT on completion → back to picker
--   EXIT on picker     → back to system

local root = ...
local osd   = assert(loadScript(root .. "osd.lua"))()
local bests = assert(loadScript(root .. "bests.lua"))()

-- Drill modules are loaded lazily so the picker is cheap.
local DRILLS = {
  { id = "gimbal_snap",  name = "GIMBAL SNAP",  file = root .. "gimbal_snap.lua",
    blurb = "Snap L, R, L, R. Both sticks." },
  { id = "offset_chase", name = "OFFSET CHASE", file = root .. "offset_chase.lua",
    blurb = "Fly the sticks. Heavy throttle, subtle pitch/yaw." },
  { id = "corner_storm", name = "CORNER STORM", file = root .. "corner_storm.lua",
    blurb = "Four corners. Both sticks on corner to advance." },
}

local DRILL_DURATION = 60.0   -- seconds

-- ---------------------------------------------------------------------------
-- State machine

local STATE_PICKER    = 1
local STATE_COUNTDOWN = 2
local STATE_DRILL     = 3
local STATE_COMPLETE  = 4

local app = {
  state = STATE_PICKER,
  pickerIndex = 1,
  currentDrill = nil,     -- loaded drill module
  currentDrillDef = nil,  -- DRILLS entry
  countdownStart = 0,
  drillStart = 0,
  lastTick = 0,
  lastResult = nil,
  lastFlags = nil,
  lastRecord = nil,
  shouldExit = false,
}

-- getTime() returns centiseconds. Convert to seconds.
local function now()
  return getTime() / 100
end

-- ---------------------------------------------------------------------------
-- Picker

local function drawPicker()
  osd.clear()
  osd.topHUD("", "EMBER")
  osd.text(10, 40, "FPV muscle-memory drills", osd.col.dim, SMLSIZE)

  local y = 70
  for i, d in ipairs(DRILLS) do
    local selected = (i == app.pickerIndex)
    local col = selected and osd.col.accent or osd.col.text
    local bg = selected and osd.col.panel or nil
    if bg then osd.rect(8, y - 4, osd.W - 16, 42, bg) end
    osd.text(16, y, (selected and "> " or "  ") .. d.name, col, MIDSIZE)
    osd.text(32, y + 20, d.blurb, osd.col.dim, SMLSIZE)

    local rec = bests.get(d.id)
    if rec.totalRuns > 0 then
      local bestLabel = d.id == "offset_chase"
        and string.format("BEST %d  RUNS %d", rec.bestScore, rec.totalRuns)
        or  string.format("BEST %d  RUNS %d", rec.bestScore, rec.totalRuns)
      osd.text(osd.W - 200, y + 8, bestLabel, osd.col.dim, SMLSIZE)
    end
    y = y + 54
  end

  osd.text(10, osd.H - 22, "[ENTER] start   [EXIT] back", osd.col.dim, SMLSIZE)
end

local function pickerEvent(event)
  if event == EVT_VIRTUAL_EXIT then
    app.shouldExit = true
    return
  end
  if event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_DEC then
    app.pickerIndex = math.max(1, app.pickerIndex - 1)
  elseif event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_INC then
    app.pickerIndex = math.min(#DRILLS, app.pickerIndex + 1)
  elseif event == EVT_VIRTUAL_ENTER then
    local def = DRILLS[app.pickerIndex]
    app.currentDrillDef = def
    app.currentDrill = assert(loadScript(def.file))()
    app.state = STATE_COUNTDOWN
    app.countdownStart = now()
    playTone(880, 60, 0, 0)
  end
end

-- ---------------------------------------------------------------------------
-- Countdown (3-2-1)

local function drawCountdown()
  osd.clear()
  osd.topHUD("", app.currentDrillDef.name)
  local elapsed = now() - app.countdownStart
  local n = 3 - math.floor(elapsed)
  if n < 1 then n = 1 end
  osd.centerTitle(100, tostring(n), osd.col.accent, DBLSIZE)
  osd.centerTitle(150, "GET READY", osd.col.dim, 0)
end

local function countdownEvent(event)
  if event == EVT_VIRTUAL_EXIT then
    app.state = STATE_PICKER
    return
  end
  local elapsed = now() - app.countdownStart
  if elapsed >= 3.0 then
    app.state = STATE_DRILL
    app.drillStart = now()
    app.lastTick = app.drillStart
    app.currentDrill.start()
    playTone(1320, 100, 0, 0)
  end
  -- Tick beeps each second.
  local secondIdx = math.floor(elapsed) + 1
  if app._lastCountBeep ~= secondIdx and secondIdx <= 3 then
    app._lastCountBeep = secondIdx
    playTone(660, 50, 0, 0)
  end
end

-- ---------------------------------------------------------------------------
-- Drill

local function drawDrill()
  osd.clear()
  local remaining = DRILL_DURATION - (now() - app.drillStart)
  if remaining < 0 then remaining = 0 end
  osd.topHUD(string.format("%.0fs", remaining), app.currentDrillDef.name)
  app.currentDrill.draw()
end

local function drillEvent(event)
  if event == EVT_VIRTUAL_EXIT then
    -- Abort — no score saved.
    app.currentDrill = nil
    app.state = STATE_PICKER
    return
  end

  local t = now()
  local dt = t - app.lastTick
  app.lastTick = t

  app.currentDrill.update(dt)

  if t - app.drillStart >= DRILL_DURATION then
    local r = app.currentDrill.result()
    local flags, record = bests.apply(app.currentDrillDef.id, r)
    app.lastResult = r
    app.lastFlags = flags
    app.lastRecord = record
    app.state = STATE_COMPLETE
    playTone(1760, 120, 40, 0)
    playTone(1320, 120, 0, 0)
  end
end

-- ---------------------------------------------------------------------------
-- Complete

local function drawComplete()
  osd.clear()
  osd.topHUD("", "DRILL COMPLETE")
  osd.centerTitle(50, app.currentDrillDef.name, osd.col.text, DBLSIZE)

  local r = app.lastResult
  local isTracking = (app.currentDrillDef.id == "offset_chase")
  local y = 100

  if isTracking then
    osd.text(60,  y, string.format("SCORE   %d",   r.score),  osd.col.text, MIDSIZE)
    osd.text(60,  y + 30, string.format("STREAK  %.1fs", r.streak), osd.col.text, MIDSIZE)
    osd.text(260, y, string.format("BEST    %d",   app.lastRecord.bestScore), osd.col.dim, MIDSIZE)
  else
    osd.text(60,  y, string.format("HITS    %d",   r.hits),   osd.col.text, MIDSIZE)
    osd.text(60,  y + 30, string.format("COMBO   x%d",  r.combo),  osd.col.text, MIDSIZE)
    osd.text(60,  y + 60, string.format("SCORE   %d",   r.score),  osd.col.text, MIDSIZE)
    osd.text(260, y, string.format("BEST    %d",   app.lastRecord.bestScore), osd.col.dim, MIDSIZE)
  end

  if app.lastFlags and (app.lastFlags.score or app.lastFlags.combo or app.lastFlags.hits or app.lastFlags.streak) then
    osd.centerTitle(osd.H - 60, "NEW BEST", osd.col.accent, MIDSIZE)
  end
  osd.text(10, osd.H - 22, "[EXIT] back to picker", osd.col.dim, SMLSIZE)
end

local function completeEvent(event)
  if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then
    app.currentDrill = nil
    app.state = STATE_PICKER
  end
end

-- ---------------------------------------------------------------------------
-- EdgeTX hooks

local function init()
  bests.load()
  app.state = STATE_PICKER
  app.pickerIndex = 1
  app.lastTick = now()
end

local function run(event)
  if app.shouldExit then return 2 end  -- nonzero return quits the tool

  if app.state == STATE_PICKER then
    drawPicker()
    pickerEvent(event)
  elseif app.state == STATE_COUNTDOWN then
    drawCountdown()
    countdownEvent(event)
  elseif app.state == STATE_DRILL then
    drawDrill()
    drillEvent(event)
  elseif app.state == STATE_COMPLETE then
    drawComplete()
    completeEvent(event)
  end

  return 0
end

local function background()
  -- No telemetry work needed when the tool isn't foreground.
end

return {
  init = init,
  run = run,
  background = background,
}
