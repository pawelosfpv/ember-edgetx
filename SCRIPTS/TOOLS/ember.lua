-- Ember: FPV muscle-memory drills on your transmitter.
-- Entry point. EdgeTX picks this up under SYS -> Tools.

local root = "/SCRIPTS/TOOLS/ember/"
local app = assert(loadScript(root .. "app.lua"))(root)

return {
  init = app.init,
  run = app.run,
  background = app.background,
}
