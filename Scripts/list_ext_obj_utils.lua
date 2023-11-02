local sqlite3 = require "lsqlite3"
local apbase = require "ApBaze"

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

local function get_psp_km_range()
	local rng = {}
	for i, v in ipairs{Passport.START_CHOORD, Passport.END_CHOORD} do
		rng[i] = tonumber(string.match(v, '^(-?%d+):'))
	end
	if rng[1] > rng[2] then rng[1], rng[2] = rng[2], rng[1] end

	local res = {}
	for km = rng[1], rng[2] do
		res[km] = true
	end
	return res
end

local function get_data_kms(fnContinueCalc)
	local sys_begin, sys_end = Driver:GetSysCoordRange()
    if not sys_begin then
        iup.Message("ATape", "отсутсвует функция Driver:GetSysCoordRange, требуется обновление ATape")
        return
    end
	if sys_begin == 0 and sys_end == 0 then  -- test
		return get_psp_km_range()
	end
	sys_end = sys_end + 1
	local step = (sys_end - sys_begin) / 1000
	step = math.max(step, 30000)
	step = math.min(step, 300000)
	local kms = {}
	local c = sys_begin
	while c < sys_end do
		local km, _, _ = Driver:GetPathCoord(c, {["AskSwitch"] = false})
		if km then
			kms[km-1] = true
			kms[km] = true
			kms[km+1] = true
			if fnContinueCalc and not fnContinueCalc((c-sys_begin) / (sys_end-sys_begin)) then
				return {}
			end
		end
		c = c + step
	end
	return kms
end

local function jump_path(path)
	local ok, err = Driver:JumpPath(path)
	if not ok then
		local msg = string.format("Не удалось перейти на координату %s km %s m:\n%s", path[1], path[2] or 0, err or '')
		iup.Message("ATape", msg)
	end
end


-- ========================================================= --

return
{
	get_data_kms = get_data_kms,
	jump_path = jump_path,
	open_db = apbase.open_db,
	load_objects = apbase.load_objects,
}
