-- Ember: FPV muscle-memory drills for EdgeTX.
-- Single-file Tool. Tested on TX16S Mk2, EdgeTX 2.7.1+.
-- MIT licensed. https://github.com/pawelosfpv/ember-edgetx

local BESTS_PATH = "/SCRIPTS/TOOLS/ember_bests.txt"
local DRILL_DURATION = 60.0

-- ---------------------------------------------------------------------------
-- OSD / drawing

local W, H = LCD_W or 480, LCD_H or 272

local COL = {
  bg     = lcd.RGB(10, 18, 24),
  text   = lcd.RGB(230, 235, 240),
  dim    = lcd.RGB(130, 145, 155),
  accent = lcd.RGB(74, 222, 128),
  warn   = lcd.RGB(239, 68, 68),
  panel  = lcd.RGB(20, 30, 38),
  border = lcd.RGB(60, 80, 92),
}

local LEFT  = { x = 120, y = 170, r = 80 }
local RIGHT = { x = 360, y = 170, r = 80 }

local function setCol(c) lcd.setColor(CUSTOM_COLOR, c) end

local function drawText(x, y, s, color, size)
  setCol(color or COL.text)
  lcd.drawText(x, y, s, (size or 0) + CUSTOM_COLOR)
end

local function drawRect(x, y, w, h, color)
  setCol(color or COL.panel)
  lcd.drawFilledRectangle(x, y, w, h, CUSTOM_COLOR)
end

local function drawCircle(cx, cy, r, color)
  setCol(color or COL.border)
  local segs = 28
  local px, py
  for i = 0, segs do
    local a = (i / segs) * 2 * math.pi
    local x = cx + math.cos(a) * r
    local y = cy + math.sin(a) * r
    if px then lcd.drawLine(px, py, x, y, SOLID, CUSTOM_COLOR) end
    px, py = x, y
  end
end

local function drawGimbalWell(well)
  drawCircle(well.x, well.y, well.r, COL.border)
  setCol(COL.border)
  lcd.drawLine(well.x - well.r, well.y, well.x + well.r, well.y, DOTTED, CUSTOM_COLOR)
  lcd.drawLine(well.x, well.y - well.r, well.x, well.y + well.r, DOTTED, CUSTOM_COLOR)
end

local function stickToScreen(well, nx, ny)
  return well.x + nx * well.r, well.y - ny * well.r
end

local function drawTarget(well, nx, ny, isHit)
  local x, y = stickToScreen(well, nx, ny)
  local c = isHit and COL.accent or COL.text
  drawCircle(x, y, 14, c)
  setCol(c)
  lcd.drawFilledRectangle(x - 2, y - 2, 5, 5, CUSTOM_COLOR)
end

local function drawThumb(well, nx, ny)
  local x, y = stickToScreen(well, nx, ny)
  setCol(COL.text)
  lcd.drawFilledRectangle(x - 4, y - 4, 9, 9, CUSTOM_COLOR)
end

local function drawTopHUD(timerLabel, drillName)
  drawRect(0, 0, W, 32, COL.panel)
  drawText(10, 8, drillName, COL.text, MIDSIZE)
  if timerLabel and timerLabel ~= "" then
    drawText(W - 80, 8, timerLabel, COL.accent, MIDSIZE)
  end
end

local function drawScoreRow(items)
  local y, x = 38, 10
  for _, it in ipairs(items) do
    local c = it.highlight and COL.accent or COL.text
    drawText(x, y, it.label, COL.dim, SMLSIZE)
    drawText(x + 48, y, it.value, c, 0)
    x = x + 110
  end
end

local function drawCenter(y, s, color, size)
  local approxW = #s * ((size == MIDSIZE) and 10 or (size == DBLSIZE) and 14 or 6)
  drawText(math.floor((W - approxW) / 2), y, s, color, size)
end

local function clearScreen()
  lcd.clear(COL.bg)
end

-- ---------------------------------------------------------------------------
-- Input: raw sticks + mode-aware channel map

-- Read raw sticks (physical position per radio's mode config).
-- thr/ele/ail/rud already account for stick mode.
local function readThr() return getValue("thr") / 1024 end
local function readEle() return getValue("ele") / 1024 end
local function readAil() return getValue("ail") / 1024 end
local function readRud() return getValue("rud") / 1024 end

-- Channel -> {side, axis} for the pilot's current stick mode.
-- stickMode: 0=M1, 1=M2, 2=M3, 3=M4
local function channelMap()
  local gs = getGeneralSettings()
  local mode = (gs and gs.stickMode) or 1
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
  else  -- Mode 2 default
    return {
      throttle = { side = "left",  axis = "y" },
      pitch    = { side = "right", axis = "y" },
      roll     = { side = "right", axis = "x" },
      yaw      = { side = "left",  axis = "x" },
    }
  end
end

local function readStick(side, map)
  map = map or channelMap()
  local x, y = 0, 0
  local function src(ch)
    if ch == "throttle" then return readThr() end
    if ch == "pitch"    then return readEle() end
    if ch == "roll"     then return readAil() end
    if ch == "yaw"      then return readRud() end
  end
  for ch, loc in pairs(map) do
    if loc.side == side then
      if loc.axis == "x" then x = src(ch) else y = src(ch) end
    end
  end
  return x, y
end

local function dist(x1, y1, x2, y2)
  local dx, dy = x1 - x2, y1 - y2
  return math.sqrt(dx * dx + dy * dy)
end

-- ---------------------------------------------------------------------------
-- Metrics

local metrics = {}
local OFF_TARGET_GRACE = 0.4

local function resetMetrics()
  metrics.hits = 0
  metrics.currentCombo = 0
  metrics.maxCombo = 0
  metrics.score = 0
  metrics.totalElapsed = 0
  metrics.timeOnTarget = 0
  metrics.timeOnBoth = 0
  metrics.currentStreak = 0
  metrics.maxStreak = 0
  metrics.offAcc = 0
end

local function registerHit()
  metrics.hits = metrics.hits + 1
  metrics.score = metrics.score + metrics.currentCombo + 1
  metrics.currentCombo = metrics.currentCombo + 1
  if metrics.currentCombo > metrics.maxCombo then metrics.maxCombo = metrics.currentCombo end
end

local function registerMiss()
  metrics.currentCombo = 0
end

local function accumulateDual(delta, leftOn, rightOn)
  metrics.totalElapsed = metrics.totalElapsed + delta
  local either = leftOn or rightOn
  local both = leftOn and rightOn
  if either then metrics.timeOnTarget = metrics.timeOnTarget + delta end
  if both then
    metrics.timeOnBoth = metrics.timeOnBoth + delta
    metrics.currentStreak = metrics.currentStreak + delta
    if metrics.currentStreak > metrics.maxStreak then metrics.maxStreak = metrics.currentStreak end
  else
    metrics.currentStreak = 0
  end
end

local function timeOnPct()
  if metrics.totalElapsed <= 0 then return 0 end
  return (metrics.timeOnTarget / metrics.totalElapsed) * 100
end

local function finalizeDualScore()
  local timeOnOne = math.max(0, metrics.timeOnTarget - metrics.timeOnBoth)
  metrics.score = math.floor(timeOnOne * 10)
                + math.floor(metrics.timeOnBoth * 25)
                + math.floor(metrics.maxStreak * 20)
end

-- ---------------------------------------------------------------------------
-- Bests persistence

local bests = {}  -- records[drillId] = {bestScore, bestCombo, bestHits, bestStreak, totalRuns}

local function defaultRecord()
  return { bestScore = 0, bestCombo = 0, bestHits = 0, bestStreak = 0, totalRuns = 0 }
end

local function loadBests()
  bests = {}
  local f = io.open(BESTS_PATH, "r")
  if not f then return end
  local content = io.read(f, 4096) or ""
  io.close(f)
  for line in string.gmatch(content, "[^\r\n]+") do
    local parts = {}
    for p in string.gmatch(line, "([^,]+)") do parts[#parts + 1] = p end
    if #parts >= 6 then
      bests[parts[1]] = {
        bestScore  = tonumber(parts[2]) or 0,
        bestCombo  = tonumber(parts[3]) or 0,
        bestHits   = tonumber(parts[4]) or 0,
        bestStreak = tonumber(parts[5]) or 0,
        totalRuns  = tonumber(parts[6]) or 0,
      }
    end
  end
end

local function saveBests()
  local f = io.open(BESTS_PATH, "w")
  if not f then return end
  for id, r in pairs(bests) do
    io.write(f, string.format(
      "%s,%d,%d,%d,%.2f,%d\n",
      id, r.bestScore, r.bestCombo, r.bestHits, r.bestStreak, r.totalRuns
    ))
  end
  io.close(f)
end

local function getBest(id)
  return bests[id] or defaultRecord()
end

local function applyRun(id, result)
  local r = bests[id] or defaultRecord()
  local flags = {}
  if result.score  > r.bestScore  then r.bestScore  = result.score;  flags.score  = true end
  if result.combo  > r.bestCombo  then r.bestCombo  = result.combo;  flags.combo  = true end
  if result.hits   > r.bestHits   then r.bestHits   = result.hits;   flags.hits   = true end
  if result.streak > r.bestStreak then r.bestStreak = result.streak; flags.streak = true end
  r.totalRuns = r.totalRuns + 1
  bests[id] = r
  saveBests()
  return flags, r
end

-- ---------------------------------------------------------------------------
-- Drill: Gimbal Snap

local gs_state = {}
local GS_TOL, GS_MAG, GS_COMMIT = 0.26, 0.75, 0.5

local function gs_start()
  gs_state = {
    leftSign = -1, rightSign = -1,
    leftArmed = true, rightArmed = true,
    leftInZone = false, rightInZone = false,
  }
  resetMetrics()
end

local function gs_tickSide(side, raw_x)
  local sign = side == "left" and gs_state.leftSign or gs_state.rightSign
  local targetX = sign * GS_MAG
  local inZone = math.abs(raw_x - targetX) <= GS_TOL
  local prev = side == "left" and gs_state.leftInZone or gs_state.rightInZone

  if inZone and not prev then
    registerHit()
    playTone(1000, 60, 0, 0)
    if side == "left" then gs_state.leftSign = -gs_state.leftSign else gs_state.rightSign = -gs_state.rightSign end
    if side == "left" then gs_state.leftArmed = false else gs_state.rightArmed = false end
  end

  local committed = math.abs(raw_x) >= GS_COMMIT
  local onTargetSide = (raw_x * sign) > 0
  local armed = side == "left" and gs_state.leftArmed or gs_state.rightArmed
  if committed and not inZone and armed and not onTargetSide then
    registerMiss()
    playTone(300, 80, 30, 0)
    playTone(250, 80, 0, 0)
    playHaptic(10, 2, 0)
    if side == "left" then gs_state.leftArmed = false else gs_state.rightArmed = false end
  end

  if math.abs(raw_x) < 0.15 then
    if side == "left" then gs_state.leftArmed = true else gs_state.rightArmed = true end
  end

  if side == "left" then gs_state.leftInZone = inZone else gs_state.rightInZone = inZone end
end

local function gs_update(dt)
  local lx, ly = readStick("left")
  local rx, ry = readStick("right")
  gs_tickSide("left", lx)
  gs_tickSide("right", rx)
  gs_state._lx, gs_state._ly = lx, ly
  gs_state._rx, gs_state._ry = rx, ry
end

local function gs_draw()
  drawGimbalWell(LEFT); drawGimbalWell(RIGHT)
  drawTarget(LEFT,  gs_state.leftSign  * GS_MAG, 0, gs_state.leftInZone)
  drawTarget(RIGHT, gs_state.rightSign * GS_MAG, 0, gs_state.rightInZone)
  if gs_state._lx then drawThumb(LEFT,  gs_state._lx, gs_state._ly) end
  if gs_state._rx then drawThumb(RIGHT, gs_state._rx, gs_state._ry) end
  drawScoreRow({
    { label = "HITS",  value = tostring(metrics.hits) },
    { label = "COMBO", value = "x" .. metrics.currentCombo, highlight = metrics.currentCombo >= 3 },
    { label = "SCORE", value = tostring(metrics.score) },
  })
end

local function gs_result()
  return { score = metrics.score, combo = metrics.maxCombo, hits = metrics.hits, streak = 0 }
end

-- ---------------------------------------------------------------------------
-- Drill: Offset Chase (dual-target tracking)

local oc_state = {}
local OC_TOL = 0.22

local function oc_start()
  oc_state = { elapsed = 0, map = channelMap(), leftOn = false, rightOn = false }
  resetMetrics()
end

local function oc_targetFor(side, t, map)
  local x, y = 0, 0
  local ch = {
    throttle = 0.80 * math.sin(t * 1.3) + 0.15 * math.sin(t * 3.1) + 0.05 * math.sin(t * 5.4),
    pitch    = 0.40 * math.sin(t * 0.5) + 0.10 * math.sin(t * 1.7),
    roll     = 0.85 * math.sin(t * 0.4) + 0.15 * math.sin(t * 1.1),
    yaw      = 0.40 * math.sin(t * 0.6) + 0.10 * math.sin(t * 1.4),
  }
  for name, loc in pairs(map) do
    if loc.side == side then
      if loc.axis == "x" then x = ch[name] else y = ch[name] end
    end
  end
  return x, y
end

local function oc_update(dt)
  oc_state.elapsed = oc_state.elapsed + dt
  local ltx, lty = oc_targetFor("left",  oc_state.elapsed, oc_state.map)
  local rtx, rty = oc_targetFor("right", oc_state.elapsed, oc_state.map)
  local lx, ly = readStick("left",  oc_state.map)
  local rx, ry = readStick("right", oc_state.map)
  oc_state.leftOn  = dist(lx, ly, ltx, lty) <= OC_TOL
  oc_state.rightOn = dist(rx, ry, rtx, rty) <= OC_TOL
  accumulateDual(dt, oc_state.leftOn, oc_state.rightOn)
  oc_state._lx, oc_state._ly, oc_state._rx, oc_state._ry = lx, ly, rx, ry
  oc_state._ltx, oc_state._lty, oc_state._rtx, oc_state._rty = ltx, lty, rtx, rty
end

local function oc_draw()
  drawGimbalWell(LEFT); drawGimbalWell(RIGHT)
  drawTarget(LEFT,  oc_state._ltx or 0, oc_state._lty or 0, oc_state.leftOn)
  drawTarget(RIGHT, oc_state._rtx or 0, oc_state._rty or 0, oc_state.rightOn)
  if oc_state._lx then drawThumb(LEFT,  oc_state._lx, oc_state._ly) end
  if oc_state._rx then drawThumb(RIGHT, oc_state._rx, oc_state._ry) end
  local both = oc_state.leftOn and oc_state.rightOn
  local either = oc_state.leftOn or oc_state.rightOn
  local mult = both and "x2.5" or (either and "x1.0" or "x0")
  drawScoreRow({
    { label = "ON",     value = string.format("%.0f%%", timeOnPct()) },
    { label = "MULT",   value = mult, highlight = both },
    { label = "STREAK", value = string.format("%.1fs", metrics.currentStreak), highlight = metrics.currentStreak >= 2 },
  })
end

local function oc_result()
  finalizeDualScore()
  return { score = metrics.score, combo = 0, hits = 0, streak = metrics.maxStreak }
end

-- ---------------------------------------------------------------------------
-- Drill: Corner Storm

local cs_state = {}
local CS_CORNERS = {
  { x = -0.78, y =  0.78 },
  { x =  0.78, y =  0.78 },
  { x =  0.78, y = -0.78 },
  { x = -0.78, y = -0.78 },
}
local CS_TOL, CS_COMMIT = 0.28, 0.5

local function cs_start()
  cs_state = { index = 1, armed = true, leftIn = false, rightIn = false }
  resetMetrics()
end

local function cs_update(dt)
  local lx, ly = readStick("left")
  local rx, ry = readStick("right")
  local t = CS_CORNERS[cs_state.index]

  cs_state.leftIn  = dist(lx, ly, t.x, t.y) <= CS_TOL
  cs_state.rightIn = dist(rx, ry, t.x, t.y) <= CS_TOL

  if cs_state.leftIn and cs_state.rightIn then
    registerHit()
    playTone(1000, 60, 0, 0)
    cs_state.index = (cs_state.index % #CS_CORNERS) + 1
    cs_state.armed = false
  end

  local committed = (math.abs(lx) >= CS_COMMIT or math.abs(ly) >= CS_COMMIT)
                 or (math.abs(rx) >= CS_COMMIT or math.abs(ry) >= CS_COMMIT)
  local sameX = (lx * t.x) > 0 and (rx * t.x) > 0
  local sameY = (ly * t.y) > 0 and (ry * t.y) > 0
  if committed and cs_state.armed and not (sameX and sameY) then
    registerMiss()
    playTone(300, 80, 30, 0)
    playTone(250, 80, 0, 0)
    playHaptic(10, 2, 0)
    cs_state.armed = false
  end

  if math.abs(lx) < 0.15 and math.abs(ly) < 0.15
     and math.abs(rx) < 0.15 and math.abs(ry) < 0.15 then
    cs_state.armed = true
  end

  cs_state._lx, cs_state._ly, cs_state._rx, cs_state._ry = lx, ly, rx, ry
end

local function cs_draw()
  drawGimbalWell(LEFT); drawGimbalWell(RIGHT)
  local t = CS_CORNERS[cs_state.index]
  drawTarget(LEFT,  t.x, t.y, cs_state.leftIn)
  drawTarget(RIGHT, t.x, t.y, cs_state.rightIn)
  if cs_state._lx then drawThumb(LEFT,  cs_state._lx, cs_state._ly) end
  if cs_state._rx then drawThumb(RIGHT, cs_state._rx, cs_state._ry) end
  drawScoreRow({
    { label = "CORNERS", value = tostring(metrics.hits) },
    { label = "COMBO",   value = "x" .. metrics.currentCombo, highlight = metrics.currentCombo >= 4 },
    { label = "SCORE",   value = tostring(metrics.score) },
  })
end

local function cs_result()
  return { score = metrics.score, combo = metrics.maxCombo, hits = metrics.hits, streak = 0 }
end

-- ---------------------------------------------------------------------------
-- Drill registry

local DRILLS = {
  { id = "gimbal_snap",  name = "GIMBAL SNAP",  blurb = "Snap L, R, L, R. Both sticks.",
    start = gs_start, update = gs_update, draw = gs_draw, result = gs_result, tracking = false },
  { id = "offset_chase", name = "OFFSET CHASE", blurb = "Fly the sticks. Heavy throttle, subtle pitch/yaw.",
    start = oc_start, update = oc_update, draw = oc_draw, result = oc_result, tracking = true },
  { id = "corner_storm", name = "CORNER STORM", blurb = "Four corners. Both sticks on corner.",
    start = cs_start, update = cs_update, draw = cs_draw, result = cs_result, tracking = false },
}

-- ---------------------------------------------------------------------------
-- State machine

local STATE_PICKER, STATE_COUNTDOWN, STATE_DRILL, STATE_COMPLETE = 1, 2, 3, 4

local app = {
  state = STATE_PICKER,
  pickerIndex = 1,
  drill = nil,
  countdownStart = 0,
  drillStart = 0,
  lastTick = 0,
  lastResult = nil,
  lastFlags = nil,
  lastRecord = nil,
  countBeepIdx = 0,
  shouldExit = false,
}

local function now() return getTime() / 100 end

-- Picker ---------------------------------------------------------------------

local function drawPicker()
  clearScreen()
  drawTopHUD("", "EMBER")
  drawText(10, 40, "FPV muscle-memory drills", COL.dim, SMLSIZE)
  local y = 70
  for i, d in ipairs(DRILLS) do
    local selected = (i == app.pickerIndex)
    if selected then drawRect(8, y - 4, W - 16, 42, COL.panel) end
    local c = selected and COL.accent or COL.text
    drawText(16, y, (selected and "> " or "  ") .. d.name, c, MIDSIZE)
    drawText(32, y + 20, d.blurb, COL.dim, SMLSIZE)
    local rec = getBest(d.id)
    if rec.totalRuns > 0 then
      drawText(W - 200, y + 8,
        string.format("BEST %d  RUNS %d", rec.bestScore, rec.totalRuns),
        COL.dim, SMLSIZE)
    end
    y = y + 54
  end
  drawText(10, H - 22, "[ENTER] start  [EXIT] back", COL.dim, SMLSIZE)
end

local function pickerEvent(event)
  if event == EVT_VIRTUAL_EXIT then
    app.shouldExit = true
  elseif event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_DEC
      or event == EVT_ROT_LEFT  or event == EVT_VIRTUAL_PREV_PAGE then
    app.pickerIndex = math.max(1, app.pickerIndex - 1)
  elseif event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_INC
      or event == EVT_ROT_RIGHT or event == EVT_VIRTUAL_NEXT_PAGE then
    app.pickerIndex = math.min(#DRILLS, app.pickerIndex + 1)
  elseif event == EVT_VIRTUAL_ENTER then
    app.drill = DRILLS[app.pickerIndex]
    app.state = STATE_COUNTDOWN
    app.countdownStart = now()
    app.countBeepIdx = 0
    playTone(880, 60, 0, 0)
  end
end

-- Countdown ------------------------------------------------------------------

local function drawCountdown()
  clearScreen()
  drawTopHUD("", app.drill.name)
  local elapsed = now() - app.countdownStart
  local n = 3 - math.floor(elapsed)
  if n < 1 then n = 1 end
  drawCenter(100, tostring(n), COL.accent, DBLSIZE)
  drawCenter(150, "GET READY", COL.dim, 0)
end

local function countdownEvent(event)
  if event == EVT_VIRTUAL_EXIT then
    app.state = STATE_PICKER
    return
  end
  local elapsed = now() - app.countdownStart
  local secIdx = math.floor(elapsed) + 1
  if secIdx ~= app.countBeepIdx and secIdx <= 3 then
    app.countBeepIdx = secIdx
    playTone(660, 50, 0, 0)
  end
  if elapsed >= 3.0 then
    app.state = STATE_DRILL
    app.drillStart = now()
    app.lastTick = app.drillStart
    app.drill.start()
    playTone(1320, 100, 0, 0)
  end
end

-- Drill ----------------------------------------------------------------------

local function drawDrill()
  clearScreen()
  local remaining = DRILL_DURATION - (now() - app.drillStart)
  if remaining < 0 then remaining = 0 end
  drawTopHUD(string.format("%.0fs", remaining), app.drill.name)
  app.drill.draw()
end

local function drillEvent(event)
  if event == EVT_VIRTUAL_EXIT then
    app.drill = nil
    app.state = STATE_PICKER
    return
  end
  local t = now()
  local dt = t - app.lastTick
  app.lastTick = t
  app.drill.update(dt)
  if t - app.drillStart >= DRILL_DURATION then
    local r = app.drill.result()
    local flags, record = applyRun(app.drill.id, r)
    app.lastResult = r
    app.lastFlags = flags
    app.lastRecord = record
    app.state = STATE_COMPLETE
    playTone(1760, 120, 40, 0)
    playTone(1320, 120, 0, 0)
  end
end

-- Complete -------------------------------------------------------------------

local function drawComplete()
  clearScreen()
  drawTopHUD("", "DRILL COMPLETE")
  drawCenter(50, app.drill.name, COL.text, DBLSIZE)
  local r = app.lastResult
  local y = 100
  if app.drill.tracking then
    drawText(60,  y,      string.format("SCORE   %d",    r.score),  COL.text, MIDSIZE)
    drawText(60,  y + 30, string.format("STREAK  %.1fs", r.streak), COL.text, MIDSIZE)
    drawText(260, y,      string.format("BEST    %d",    app.lastRecord.bestScore), COL.dim, MIDSIZE)
  else
    drawText(60,  y,      string.format("HITS    %d",  r.hits),  COL.text, MIDSIZE)
    drawText(60,  y + 30, string.format("COMBO   x%d", r.combo), COL.text, MIDSIZE)
    drawText(60,  y + 60, string.format("SCORE   %d",  r.score), COL.text, MIDSIZE)
    drawText(260, y,      string.format("BEST    %d",  app.lastRecord.bestScore), COL.dim, MIDSIZE)
  end
  if app.lastFlags and (app.lastFlags.score or app.lastFlags.combo or app.lastFlags.hits or app.lastFlags.streak) then
    drawCenter(H - 60, "NEW BEST", COL.accent, MIDSIZE)
  end
  drawText(10, H - 22, "[EXIT] back to picker", COL.dim, SMLSIZE)
end

local function completeEvent(event)
  if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then
    app.drill = nil
    app.state = STATE_PICKER
  end
end

-- ---------------------------------------------------------------------------
-- EdgeTX entry points

local function init()
  loadBests()
  app.state = STATE_PICKER
  app.pickerIndex = 1
  app.lastTick = now()
  app.shouldExit = false
end

local function run(event)
  if app.shouldExit then return 2 end
  if app.state == STATE_PICKER then
    drawPicker(); pickerEvent(event)
  elseif app.state == STATE_COUNTDOWN then
    drawCountdown(); countdownEvent(event)
  elseif app.state == STATE_DRILL then
    drawDrill(); drillEvent(event)
  elseif app.state == STATE_COMPLETE then
    drawComplete(); completeEvent(event)
  end
  return 0
end

return { init = init, run = run }
