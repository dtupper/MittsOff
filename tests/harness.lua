-- Minimal test harness. Run with: lua MittsOff/tests/run.lua
local H = { passed = 0, failed = 0 }

H.root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\][^/\\]*$") or "."

-- Loads an addon file the way the game does: chunk(addonName, namespace).
function H.load(file, ns)
	local chunk = assert(loadfile(H.root .. "/" .. file))
	chunk("MittsOff", ns)
	return ns
end

local function show(value)
	if type(value) ~= "table" then return tostring(value) end
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = key .. "=" .. show(value[key] == nil and value[tonumber(key)] or value[key])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end
H.show = show

function H.eq(actual, expected, label)
	if show(actual) ~= show(expected) then error(("%s: expected %s, got %s"):format(label or "value", show(expected), show(actual)), 2) end
end

function H.ok(value, label)
	if not value then error((label or "value") .. ": expected truthy, got " .. show(value), 2) end
end

function H.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		H.passed = H.passed + 1
	else
		H.failed = H.failed + 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end

function H.finish()
	print(("%d passed, %d failed"):format(H.passed, H.failed))
	os.exit(H.failed == 0 and 0 or 1)
end

return H
