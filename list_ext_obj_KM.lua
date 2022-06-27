local sqlite3 = require "lsqlite3"
local OOP = require 'OOP'
local ext_obj_utils = require 'list_ext_obj_utils'


local function _sql_assert(db, val, msg)
	if val then return val end
	local msg = string.format('%s(%s) %s', db:errcode(), db:errmsg(), msg or '')
	error(msg)
end


local function _load_km(fnContinueCalc, kms)
	if Passport.TRACK_CODE == '' then
		return {}
	end
	local db = sqlite3.open('C:\\ApBAZE.db')
	local sql = [[
		SELECT
			k.ID, k.KM, k.BEGIN_M, k.END_M, k.LENGT
		FROM KM AS k
		JOIN WAY as w ON
			k.UP_NOM = w.UP_NOM and k.PUT_NOM = w.NOM and k.SITEID = w.SITEID
		WHERE
			w.ASSETNUM = :ASSETNUM
		ORDER BY
			k.KM
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
	width = 40,
	get_text = function(row_n, obj)
		return row_n
	end,
}

local COL_KM =
{
	name = "KM",
	align = 'r',
	width = 50,
	get_text = function(row_n, obj)
		return string.format("%d", obj.KM)
	end,
}

local COL_LEN =
{
	name = "Длн",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return string.format("%d", obj.LENGT)
	end,
}

local COL_M =
{
	name = "нач-кон",
	align = 'r',
	width = 70,
	get_text = function(row_n, obj)
		return string.format("%d -> %d", obj.BEGIN_M, obj.END_M)
	end,
}

local KM = OOP.class
{
	name = "KM",
	columns =
	{
		COL_N,
		COL_KM,
		COL_LEN,
		COL_M,
	},
	ctor = function (self, fnContinueCalc)
		local kms = ext_obj_utils.get_data_kms(fnContinueCalc)
		self.objects = _load_km(fnContinueCalc, kms)
		return #self.objects
	end,
	get_object = function (self, row)
		return self.objects[row]
	end,
	OnMouse = function(self, act, flags, cell, pos_client, pos_screen)
        local obj  = self:get_object(cell.row)
        if act == 'left_dbl_click' and obj then
			local ok, err = Driver:JumpPath({obj.KM, obj.BEGIN_M-1, 0})
			if not ok then
				local msg = string.format("Не удалось перейти на координату %d km %d m\n%s", obj.KM, obj.BEGIN_M-1, err)
				iup.Message("ATape", msg)
			end
        end
    end,
	GetExtObjMarks = function (self)
		local res = {}
		for i, obj in ipairs(self.objects) do
			res[i] = {
				path={obj.KM, obj.BEGIN_M-1},
				description = string.format("Столб %d км", obj.KM),
				vert_line = 1,
				icon_file = 'Images/SUM.bmp',
				icon_rect = {13*16, 0, 16, 16},
				id = i,
			}
		end
		return res
	end,
}

return
{
    filters = {
        KM,
    }
}
