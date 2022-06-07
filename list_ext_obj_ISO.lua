local sqlite3 = require "lsqlite3"
local OOP = require 'OOP'
local ext_obj_utils = require 'list_ext_obj_utils'


local function _sql_assert(db, val, msg)
	if val then return val end
	local msg = string.format('%s(%s) %s', db:errcode(), db:errmsg(), msg or '')
	error(msg)
end


local function _load_iso(fnContinueCalc, kms)
	local db = sqlite3.open('C:\\ApBAZE.db')
	local sql = [[
		SELECT
			i.KM, i.M, i.ID
		FROM
			ISO as i, WAY AS w
		WHERE
			i.UP_NOM = w.UP_NOM and i.PUT_NOM = w.NOM and w.ASSETNUM = :ASSETNUM
		ORDER BY
			CAST(i.KM AS REAL), CAST(i.M AS REAL)
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
		local kms = ext_obj_utils.get_data_kms(fnContinueCalc)
		self.objects = _load_iso(fnContinueCalc, kms)
		return #self.objects
	end,
	get_object = function (self, row)
		return self.objects[row]
	end,
	OnMouse = function(self, act, flags, cell, pos_client, pos_screen)
        local object = self:get_object(cell.row)
        if act == 'left_dbl_click' and object then
			self:JumpIso(object)
        end
    end,
	JumpIso = function(self, obj)
		local mark = {
			description = string.format("ИзоСтык (%d)\n%d км %d м", obj.ID, obj.KM, obj.M),
			vert_line = 1,
			filename = 'Images/SUM.bmp',
			src_rect = {16, 32, 16, 16}
		}
		local ok, err = Driver:JumpPath({obj.KM, obj.M, 0}, {mark=mark})
		if not ok then
			local msg = string.format("Не удалось перейти на координату %d km %d m\n%s", obj.KM, obj.M, err)
			iup.Message("ATape", msg)
		end
	end,
}

return
{
    filters = {
        ISO,
    }
}
