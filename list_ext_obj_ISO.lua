local OOP = require 'OOP'
local ext_obj_utils = require 'list_ext_obj_utils'

local function _load_iso(fnContinueCalc, kms)
	if Passport.TRACK_CODE == '' then
		return {}
	end
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
	return ext_obj_utils.load_objects(sql, {ASSETNUM=Passport.TRACK_CODE}, function (row)
		return not kms or kms[row.KM]
	end)
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

local COL_ISO_ID =
{
	name = "ID",
	align = 'r',
	width = 70,
	get_text = function(row_n, obj)
		return string.format("%d", obj.ID)
	end,
}


local ISO = OOP.class
{
	name = "Изостыки",
	columns =
	{
		COL_ISO_N,
		COL_ISO_PATH,
		COL_ISO_ID,
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
		ext_obj_utils.jump_path{obj.KM, obj.M, 0}
	end,
	GetExtObjMarks = function (self)
		local res = {}
		for i, obj in ipairs(self.objects) do
			res[i] = {
				path={obj.KM, obj.M},
				description = string.format("ИзоСтык (%d)\n%d км %d м", obj.ID, obj.KM, obj.M),
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
        ISO,
    }
}
