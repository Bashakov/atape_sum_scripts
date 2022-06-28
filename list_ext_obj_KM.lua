local OOP = require 'OOP'
local ext_obj_utils = require 'list_ext_obj_utils'


local function jump_KM(km, m)
	local ok, err
	for o = 0, 10 do
		ok, err = Driver:JumpPath({km, m+o, 0})
		if ok then
			return
		end
	end
	local msg = string.format("Не удалось перейти %d километр:\n%s", km, err or '')
	iup.Message("ATape", msg)
end

local function _load_km(fnContinueCalc, kms)
	if Passport.TRACK_CODE == '' then
		return {}
	end

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
	return ext_obj_utils.load_objects(sql, {ASSETNUM=Passport.TRACK_CODE}, function (row)
		return not kms or kms[row.KM]
	end)
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
		return string.format("%4d -> %4d", obj.BEGIN_M, obj.END_M)
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
			jump_KM(obj.KM, obj.BEGIN_M-1)
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
