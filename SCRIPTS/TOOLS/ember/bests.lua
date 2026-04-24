-- Dirt-simple persistence. One line per drill:
--   drill_id,bestScore,bestCombo,bestHits,bestStreakSeconds,totalRuns
-- Read on startup into memory; rewritten on completion.

local PATH = "/SCRIPTS/TOOLS/ember/bests.txt"

local M = {
  records = {}  -- keyed by drill id
}

local function parseLine(line)
  local parts = {}
  for p in string.gmatch(line, "([^,]+)") do parts[#parts + 1] = p end
  if #parts < 6 then return nil end
  return parts[1], {
    bestScore  = tonumber(parts[2]) or 0,
    bestCombo  = tonumber(parts[3]) or 0,
    bestHits   = tonumber(parts[4]) or 0,
    bestStreak = tonumber(parts[5]) or 0,
    totalRuns  = tonumber(parts[6]) or 0,
  }
end

function M.load()
  M.records = {}
  local f = io.open(PATH, "r")
  if not f then return end
  local content = io.read(f, 4096) or ""
  io.close(f)
  for line in string.gmatch(content, "[^\r\n]+") do
    local id, rec = parseLine(line)
    if id then M.records[id] = rec end
  end
end

function M.get(drillId)
  return M.records[drillId] or {
    bestScore = 0, bestCombo = 0, bestHits = 0,
    bestStreak = 0, totalRuns = 0
  }
end

-- Apply a run result. Returns a flags table showing which fields improved.
function M.apply(drillId, result)
  local r = M.get(drillId)
  local flags = { score = false, combo = false, hits = false, streak = false }
  if result.score   > r.bestScore  then r.bestScore  = result.score;       flags.score  = true end
  if result.combo   > r.bestCombo  then r.bestCombo  = result.combo;       flags.combo  = true end
  if result.hits    > r.bestHits   then r.bestHits   = result.hits;        flags.hits   = true end
  if result.streak  > r.bestStreak then r.bestStreak = result.streak;      flags.streak = true end
  r.totalRuns = r.totalRuns + 1
  M.records[drillId] = r
  M.save()
  return flags, r
end

function M.save()
  local f = io.open(PATH, "w")
  if not f then return end
  for id, r in pairs(M.records) do
    local line = string.format(
      "%s,%d,%d,%d,%.2f,%d\n",
      id, r.bestScore, r.bestCombo, r.bestHits, r.bestStreak, r.totalRuns
    )
    io.write(f, line)
  end
  io.close(f)
end

return M
