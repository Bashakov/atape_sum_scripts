local sqlite3 = require "lsqlite3"
local OOP = require 'OOP'
local ext_obj_utils = require 'list_ext_obj_utils'


local function _sql_assert(db, val, msg)
	if val then return val end
	local msg = string.format('%s(%s) %s', db:errcode(), db:errmsg(), msg or '')
	error(msg)
end


local function _load_issoext(fnContinueCalc, kms)
	if Passport.TRACK_CODE == '' then
		return {}
	end
	local db = sqlite3.open('C:\\ApBAZE.db')
	local sql = [[
		SELECT
			i.BEGIN_KM, i.BEGIN_M, i.END_KM, i.END_M, i.TYPE
		FROM
			ISSOEXT as i, WAY AS w
		WHERE
			i.UP_NOM = w.UP_NOM and i.siteid = w.siteid and w.ASSETNUM = :ASSETNUM
		ORDER BY
			CAST(i.BEGIN_KM AS REAL), CAST(i.BEGIN_M AS REAL)
		]]
	local stmt = _sql_assert(db, db:prepare(sql))
	_sql_assert(db, stmt:bind_names({ASSETNUM=Passport.TRACK_CODE}))
	local res = {}
	for row in stmt:nrows() do
		if not kms or kms[row.BEGIN_KM] or kms[row.END_KM] then
			table.insert(res, row)
		end
	end
	return res
end

local COL_N =
{
	name = "N",
	align = 'r',
	width = 40,
	get_text = function(row_n, obj)
		return row_n
	end,
}

local function jump(obj, begin)
	local path = begin and {obj.BEGIN_KM, obj.BEGIN_M, 0} or {obj.END_KM, obj.END_M, 0}
	local ok, err = Driver:JumpPath(path)
	if not ok then
		local msg = string.format("Не удалось перейти на координату %d km %d m\n%s", path[1], path[2], err)
		iup.Message("ATape", msg)
	end
end

local COL_PATH_START =
{
	name = "Начало",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return string.format("%d.%03d", obj.BEGIN_KM, obj.BEGIN_M)
	end,
	on_dbl_click = function(row_n, obj)
		jump(obj, true)
	end,
	get_color = function(row_n, obj)
        return {0x000000, 0xfffff0}
    end
}

local COL_PATH_END =
{
	name = "Конец",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return string.format("%d.%03d", obj.END_KM, obj.END_M)
	end,
	on_dbl_click = function(row_n, obj)
		jump(obj, false)
	end,
	get_color = function(row_n, obj)
        return {0x000000, 0xf0fff0}
    end
}


local COL_TYPE =
{
	name = "Тип",
	align = 'l',
	width = 150,
	get_text = function(row_n, obj)
		local t = obj.TYPE
		if t == 0 then return "не определено (возможно мост)" end
		if t == 1 then return "мост безбалластный" end
		if t == 2 then return "мост балластный" end
		if t == 3 then return "тоннель" end
		if t == 4 then return "путепровод" end
		if t == 5 then return "переезд" end
		if t == 6 then return "мост смешанного типа" end
	end,
}

local ISSOEXT = OOP.class
{
	name = "мосты и прочие",
	columns =
	{
		COL_N,
		COL_PATH_START,
		COL_PATH_END,
		COL_TYPE,
	},
	ctor = function (self, fnContinueCalc)
		local kms = ext_obj_utils.get_data_kms(fnContinueCalc)
		self.objects = _load_issoext(fnContinueCalc, kms)
		return #self.objects
	end,
	get_object = function (self, row)
		return self.objects[row]
	end,
	OnMouse = function(self, act, flags, cell, pos_client, pos_screen)
        local object = self:get_object(cell.row)
		local column = self.columns[cell.col]
        if act == 'left_dbl_click' and object then
			if column and column.on_dbl_click then
				column.on_dbl_click(cell.row, object)
			end
        end
    end,
	GetExtObjMarks = function (self)
		local res = {}
		for i, obj in ipairs(self.objects) do
			local name = string.format("%s %d.%03d - %d.%03d", COL_TYPE.get_text(0, obj), obj.BEGIN_KM, obj.BEGIN_M, obj.END_KM, obj.END_M)
			for begin = 0, 1 do
				local id = i*2+begin
				local description = begin==0 and "Начало " or "Конец "
				local path = begin==0 and {obj.BEGIN_KM, obj.BEGIN_M, 0} or {obj.END_KM, obj.END_M, 0}
				res[id] = {
					path = path,
					description = description .. name,
					vert_line = 1,
					icon_file = 'Images/SUM.bmp',
					icon_rect = {(begin==0 and 6 or 7) * 16, 32, 16, 16},
					id = id,
				}
			end
		end
		return res
	end,
}

return
{
    filters = {
        ISSOEXT,
    }
}
