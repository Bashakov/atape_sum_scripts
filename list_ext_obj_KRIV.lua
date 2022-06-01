local OOP = require 'OOP'
local csv = require 'read_csv'
local mark_helper = require 'sum_mark_helper'


local function _load_kriv(fnContinueCalc)
	local res = {}
	local way_code = Passport.TRACK_CODE
	local path_csv = 'KRIV.csv'
	local expect_line = 50000
	for num, row in csv.iter_csv(path_csv, ';', true) do
		if row.SOURCEASSETNUM == way_code then
			table.insert(res, row)
		end
		if num % 100 == 0 and not fnContinueCalc(math.fmod(num / expect_line, 1.0)) then
			return {}
		end
	end
	res = mark_helper.sort_marks(res, function (row)
		return {tonumber(row.S_KM), tonumber(row.S_M)}
	end)
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
		return string.format("%d.%03d", obj.S_KM, obj.S_M)
	end,
	on_dbl_click = function(row_n, obj)
		_jump_path(obj.S_KM, obj.S_M)
	end,
}

local COL_KRIV_PATH_END =
{
	name = "Конец",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return string.format("%d.%03d", obj.E_KM, obj.E_M)
	end,
	on_dbl_click = function(row_n, obj)
		_jump_path(obj.E_KM, obj.E_M)
	end,
}

local COL_KRIV_DIRECTION =
{
	name = "Напр",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return obj.RNAPRKRIV
	end,
}

local COL_KRIV_LEN =
{
	name = "Протяж",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return obj.KLENGTH
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
		self.objects = _load_kriv(fnContinueCalc)
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
