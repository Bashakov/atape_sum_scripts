local sqlite3 = require "lsqlite3"
local OOP = require 'OOP'
local ext_obj_utils = require 'list_ext_obj_utils'


local function _sql_assert(db, val, msg)
	if val then return val end
	local msg = string.format('%s(%s) %s', db:errcode(), db:errmsg(), msg or '')
	error(msg)
end


local function _load_str(fnContinueCalc, kms)
	if Passport.TRACK_CODE == '' then
		return {}
	end
	local db = sqlite3.open('C:\\ApBAZE.db')
	local sql = [[
			SELECT
				s.KM, s.M, t.TYPE, p.TYPE as POSH, s.ID_OB, s.NOM
			FROM 
				STR as s
			JOIN
				WAY as w ON w.UP_NOM = s.UP_NOM AND w.siteid = s.siteid
			JOIN
				SPR_STR AS t ON s.TYPE = t.ID
			JOIN
				SPR_STRPOSH AS p ON s.POSH = p.ID
			WHERE
				w.assetnum = :ASSETNUM
			ORDER BY
				CAST(s.KM AS REAL), CAST(s.M AS REAL)
		]]
	local stmt = _sql_assert(db, db:prepare(sql))
	_sql_assert(db, stmt:bind_names({ASSETNUM=Passport.TRACK_CODE}))
	local res = {}
	for row in stmt:nrows() do
		if not kms or kms[row.KM] then
			table.insert(res, row)
		end
	end
	return res
end

local COL_N =
{
	name = "N",
	align = 'r',
	width = 30,
	get_text = function(row_n, obj)
		return row_n
	end,
}

local COL_PATH =
{
	name = "Положение",
	align = 'r',
	width = 70,
	get_text = function(row_n, obj)
		return string.format("%d.%03d", obj.KM, obj.M)
	end,
}

local COL_TYPE =
{
	name = "Тип",
	align = 'l',
	width = 50,
	get_text = function(row_n, obj)
		return obj.TYPE
	end,
}


local COL_POSH =
{
	name = "Пошерстно",
	align = 'l',
	width = 120,
	get_text = function(row_n, obj)
		return obj.POSH
	end,
}

local COL_NOM  =
{
	name = "Номер ",
	align = 'r',
	width = 50,
	get_text = function(row_n, obj)
		return obj.NOM
	end,
}

local COL_ID_OB  =
{
	name = "ID_OB ",
	align = 'r',
	width = 50,
	get_text = function(row_n, obj)
		return string.format("%d", obj.ID_OB)
	end,
}


local STR = OOP.class
{
	name = "Стрелки",
	columns =
	{
		COL_N,
		COL_PATH,
		COL_TYPE,
		COL_POSH,
		COL_NOM,
		COL_ID_OB,
	},
	ctor = function (self, fnContinueCalc)
		local kms = ext_obj_utils.get_data_kms(fnContinueCalc)
		self.objects = _load_str(fnContinueCalc, kms)
		return #self.objects
	end,
	get_object = function (self, row)
		return self.objects[row]
	end,
	OnMouse = function(self, act, flags, cell, pos_client, pos_screen)
        local object = self:get_object(cell.row)
        if act == 'left_dbl_click' and object then
			self:Jump(object)
        end
    end,
	Jump = function(self, obj)
		local ok, err = Driver:JumpPath({obj.KM, obj.M, 0})
		if not ok then
			local msg = string.format("Не удалось перейти на координату %d km %d m\n%s", obj.KM, obj.M, err)
			iup.Message("ATape", msg)
		end
	end,
	GetExtObjMarks = function (self)
		local res = {}
		for i, obj in ipairs(self.objects) do
			res[i] = {
				path={obj.KM, obj.M},
				description = string.format("стрелка: %s\n%d км %d м", obj.TYPE, obj.KM, obj.M),
				vert_line = 1,
				icon_file = 'Images/SUM.bmp',
				icon_rect = {16, 32, 16, 16},
				id = i,
			}
		end
		return res
	end,
}

return
{
    filters = {
        STR,
    }
}
