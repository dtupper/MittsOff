-- Runs every spec. From the AddOns folder: lua MittsOff/tests/run.lua
local dir = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local H = dofile(dir .. "/harness.lua")
for _, spec in ipairs({ "rules_spec.lua", "addon_spec.lua" }) do
	local chunk = loadfile(dir .. "/" .. spec)
	if chunk then chunk(H) end
end
H.finish()
