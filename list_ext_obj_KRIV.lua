local sqlite3 = require "lsqlite3"
local OOP = require 'OOP'
local csv = require 'read_csv'
local mark_helper = require 'sum_mark_helper'


local function _sql_assert(db, val, msg)
	if val then return val end
	local msg = string.format('%s(%s) %s', db:errcode(), db:errmsg(), msg or '')
	error(msg)
end


local function _load_kriv_db(fnContinueCalc)
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
		table.insert(res, row)
	end
	return res
end


local function _jump_path(km, m)
	if not Driver:JumpPath(km, m, 0) then
		local msg = string.format("Не удалось перейти на координату %d km %d m", km, m)
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
		_jump_path(obj.BEGIN_KM, obj.BEGIN_M)
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
		_jump_path(obj.END_KM, obj.END_M)
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
		COL_KRIV_PATH_START,
		COL_KRIV_PATH_END,
		COL_KRIV_DIRECTION,
		COL_KRIV_LEN,
	},
	ctor = function (self, fnContinueCalc)
		self.objects = _load_kriv_db(fnContinueCalc)
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
