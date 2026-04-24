-- Drawing helpers: OSD aesthetic for 480x272 color LCD.
-- Two gimbal circles at the bottom, HUD strip at top.

local M = {}

M.W, M.H = LCD_W or 480, LCD_H or 272

-- Palette (approximated Betaflight OSD)
M.col = {
  bg      = lcd.RGB(10, 18, 24),
  text    = lcd.RGB(230, 235, 240),
  dim     = lcd.RGB(130, 145, 155),
  accent  = lcd.RGB(74, 222, 128),   -- active / hit
  warn    = lcd.RGB(239, 68, 68),    -- miss
  panel   = lcd.RGB(20, 30, 38),
  border  = lcd.RGB(60, 80, 92),
}

-- Gimbal circle centers + radius. Picked to fit 480x272 with top HUD.
M.LEFT  = { x = 120, y = 170, r = 80 }
M.RIGHT = { x = 360, y = 170, r = 80 }

function M.clear()
  lcd.clear(M.col.bg)
end

function M.text(x, y, str, color, size)
  lcd.setColor(CUSTOM_COLOR, color or M.col.text)
  lcd.drawText(x, y, str, (size or 0) + CUSTOM_COLOR)
end

-- Draw a filled rectangle.
function M.rect(x, y, w, h, color)
  lcd.setColor(CUSTOM_COLOR, color or M.col.panel)
  lcd.drawFilledRectangle(x, y, w, h, CUSTOM_COLOR)
end

-- Draw a rectangle border.
function M.border(x, y, w, h, color)
  lcd.setColor(CUSTOM_COLOR, color or M.col.border)
  lcd.drawRectangle(x, y, w, h, CUSTOM_COLOR)
end

-- Draw a circle approximation using line segments.
-- 24 segments is plenty at this radius.
function M.circle(cx, cy, r, color)
  lcd.setColor(CUSTOM_COLOR, color or M.col.border)
  local segs = 24
  local prevX, prevY
  for i = 0, segs do
    local a = (i / segs) * 2 * math.pi
    local x = cx + math.cos(a) * r
    local y = cy + math.sin(a) * r
    if prevX then
      lcd.drawLine(prevX, prevY, x, y, SOLID, CUSTOM_COLOR)
    end
    prevX, prevY = x, y
  end
end

-- Draw the gimbal well (circle outline).
function M.gimbalWell(well)
  M.circle(well.x, well.y, well.r, M.col.border)
  -- Crosshair
  lcd.setColor(CUSTOM_COLOR, M.col.border)
  lcd.drawLine(well.x - well.r, well.y, well.x + well.r, well.y, DOTTED, CUSTOM_COLOR)
  lcd.drawLine(well.x, well.y - well.r, well.x, well.y + well.r, DOTTED, CUSTOM_COLOR)
end

-- Convert stick value (-1 .. +1, y-up) to screen coords inside a gimbal well.
function M.stickToScreen(well, nx, ny)
  return well.x + nx * well.r, well.y - ny * well.r
end

-- Draw a target marker at normalized stick coords in a well.
function M.target(well, nx, ny, isHit)
  local x, y = M.stickToScreen(well, nx, ny)
  local color = isHit and M.col.accent or M.col.text
  lcd.setColor(CUSTOM_COLOR, color)
  -- Outer ring
  M.circle(x, y, 14, color)
  -- Inner filled dot
  lcd.drawFilledRectangle(x - 2, y - 2, 5, 5, CUSTOM_COLOR)
end

-- Draw the pilot's thumb dot inside a well.
function M.thumb(well, nx, ny)
  local x, y = M.stickToScreen(well, nx, ny)
  lcd.setColor(CUSTOM_COLOR, M.col.text)
  lcd.drawFilledRectangle(x - 4, y - 4, 9, 9, CUSTOM_COLOR)
end

-- Top HUD strip.
function M.topHUD(timerLabel, drillName)
  M.rect(0, 0, M.W, 32, M.col.panel)
  M.text(10, 8, drillName, M.col.text, MIDSIZE)
  M.text(M.W - 80, 8, timerLabel, M.col.accent, MIDSIZE)
end

-- Score line just below the top HUD. Pass a list of {label, value, highlight}.
function M.scoreRow(items)
  local y = 38
  local x = 10
  for _, item in ipairs(items) do
    local color = item.highlight and M.col.accent or M.col.text
    M.text(x, y, item.label, M.col.dim, SMLSIZE)
    M.text(x + 48, y, item.value, color, 0)
    x = x + 110
  end
end

-- Centered title (used by picker + completion).
function M.centerTitle(y, str, color, size)
  local width = #str * ((size == MIDSIZE) and 10 or (size == DBLSIZE) and 14 or 6)
  M.text(math.floor((M.W - width) / 2), y, str, color, size)
end

-- Miss flash: red border flash for one frame.
function M.missFlash()
  M.border(0, 0, M.W, M.H, M.col.warn)
  M.border(1, 1, M.W - 2, M.H - 2, M.col.warn)
end

return M
