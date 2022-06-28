local sqlite3 = require "lsqlite3"

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end


local function get_data_kms(fnContinueCalc)
	local sys_begin, sys_end = Driver:GetSysCoordRange()
    if not sys_begin then
        iup.Message("ATape", "отсутсвует функция Driver:GetSysCoordRange, требуется обновление ATape")
        return
    end
	if sys_begin == 0 and sys_end == 0 then  -- test
		return
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
		local msg = string.format("Не удалось перейти на координату %d km %d m:\n%s", path[1], path[2] or 0, err or '')
		iup.Message("ATape", msg)
	end
end

local function get_db_path()
	local path = EKASUI_PARAMS.ApBAZE or "D:/ATapeXP/Tools/GBPD/ApBAZE.db"
	return path
end

local function is_file_exists(path)
	local f = io.open(path, 'rb')
	if f then f:close() end
	return f
end

local function open_db()
	local path = get_db_path()
	if not is_file_exists(path) then
		local msg = string.format("file [%s] not exist", path)
		error(msg)
	end

	local flags = sqlite3.SQLITE_OPEN_READONLY
	local db = assert(sqlite3.open(path, flags))
	return db
end

local function load_objects(sql, bind_values, filter_row)
	local db = open_db()
	local stmt = db:prepare(sql)
	if not stmt then
		local msg = string.format('%s(%s) on %s', db:errcode(), db:errmsg(), sql)
		error(msg)
	end
	stmt:bind_names(bind_values)
	local res = {}
	for row in stmt:nrows() do
		if not filter_row or filter_row(row) then
			table.insert(res, row)
		end
	end
	db:close()
	return res
end

-- ========================================================= --

return
{
	get_data_kms = get_data_kms,
	jump_path = jump_path,
	get_db_path = get_db_path,
	open_db = open_db,
	load_objects = load_objects,
}
