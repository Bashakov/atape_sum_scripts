local sqlite3 = require "lsqlite3"
local OOP = require 'OOP'
local ext_obj_utils = require 'list_ext_obj_utils'

local function _sql_assert(db, val, msg)
	if val then return val end
	local msg = string.format('%s(%s) %s', db:errcode(), db:errmsg(), msg or '')
	error(msg)
end

local function _load_kriv_db(fnContinueCalc, kms)
	local db = sqlite3.open('C:\\ApBAZE.db')
	local sql = [[
		SELECT *
		FROM CURVES
		WHERE ASSETNUM = :ASSETNUM
		ORDER BY CAST(BEGIN_KM AS REAL), CAST(BEGIN_M AS REAL)]]
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


local COL_KRIV_N =
{
	name = "N",
	align = 'r',
	width = 40,
	get_text = function(row_n, obj)
		return row_n
	end,
}

local function jump_kriv(obj, begin)
	local path = begin and {obj.BEGIN_KM, obj.BEGIN_M, 0} or {obj.END_KM, obj.END_M, 0} 
	local mark = {
		description = begin and "Начало кривой" or "Конец кривой",
		vert_line = 1,
		filename = 'Images/SUM.bmp',
		src_rect = {(begin and 6 or 7) * 16, 32, 16, 16}
	}
	local ok, err = Driver:JumpPath(path, {mark=mark})
	if not ok then
		local msg = string.format("Не удалось перейти на координату %d km %d m\n%s", path[1], path[2], err)
		iup.Message("ATape", msg)
	end
end

local COL_KRIV_PATH_START =
{
	name = "Начало",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return string.format("%d.%03d", obj.BEGIN_KM, obj.BEGIN_M)
	end,
	on_dbl_click = function(row_n, obj)
		jump_kriv(obj, true)
	end,
}

local COL_KRIV_PATH_END =
{
	name = "Конец",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return string.format("%d.%03d", obj.END_KM, obj.END_M)
	end,
	on_dbl_click = function(row_n, obj)
		jump_kriv(obj, false)
	end,
}

local COL_KRIV_DIRECTION =
{
	name = "Напр",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return obj.NAPR
	end,
}

local COL_KRIV_LEN =
{
	name = "Протяж",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return obj.LEN
	end,
}

local KRIV = OOP.class
{
	name = "Кривые",
	columns =
	{
		COL_KRIV_N,
		COL_KRIV_PATH_START,
		COL_KRIV_PATH_END,
		COL_KRIV_DIRECTION,
		COL_KRIV_LEN,
	},
	ctor = function (self, fnContinueCalc)
		local kms = ext_obj_utils.get_data_kms(fnContinueCalc)
		self.objects = _load_kriv_db(fnContinueCalc, kms)
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
    end
}

return
{
    filters = {
        KRIV,
    }
}
