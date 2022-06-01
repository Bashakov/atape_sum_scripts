local sqlite3 = require "lsqlite3"
local OOP = require 'OOP'
local csv = require 'read_csv'
local mark_helper = require 'sum_mark_helper'


local function _sql_assert(db, val, msg)
	if val then return val end
	local msg = string.format('%s(%s) %s', db:errcode(), db:errmsg(), msg or '')
	error(msg)
end


local function _load_iso(fnContinueCalc)
	local db = sqlite3.open('C:\\ApBAZE.db')
	local sql = [[
		SELECT
			i.KM, i.M, i.ID
		FROM
			ISO as i
		JOIN
			WAY AS w ON i.UP_NOM = w.UP_NOM
		WHERE
			w.ASSETNUM = :ASSETNUM
		ORDER BY
			CAST(i.KM AS REAL), CAST(i.M AS REAL)
	]]
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

local COL_ISO_N =
{
	name = "N",
	align = 'r',
	width = 40,
	get_text = function(row_n, obj)
		return row_n
	end,
}

local COL_ISO_PATH =
{
	name = "Положение",
	align = 'r',
	width = 100,
	get_text = function(row_n, obj)
		return string.format("%d.%03d", obj.KM, obj.M)
	end,
	on_dbl_click = function(row_n, obj)
		_jump_path(obj.KM, obj.M)
	end,
}


local ISO = OOP.class
{
	name = "Изостыки",
	columns =
	{
		COL_ISO_N,
		COL_ISO_PATH,
	},
	ctor = function (self, fnContinueCalc)
		self.objects = _load_iso(fnContinueCalc)
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
        ISO,
    }
}
