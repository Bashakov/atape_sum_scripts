local OOP = require 'OOP'
local ext_obj_utils = require 'list_ext_obj_utils'


local function _load_str(fnContinueCalc, kms)
	if Passport.TRACK_CODE == '' then
		return {}
	end
	-- https://bt.abisoft.spb.ru/view.php?id=981
	local sql = [[
		SELECT
			a.BEGIN_KM, a.BEGIN_M, a.END_KM, a.END_M, c.TYPE, a.NUM, b.CHIEF_NAME, a.ID_PODR
		FROM
			PODRGR a
		INNER JOIN
			PODR b on a.SITEID=b.SITEID AND a.NUM=b.NUM AND a.TYPE=b.TYPE AND a.TYPE=5
		INNER JOIN
			SPR_PODR c on a.TYPE=c.ID
		INNER JOIN
			WAY d on a.SITEID=d.SITEID AND a.UP_NOM=d.UP_NOM AND a.PUT_NOM=d.NOM
		WHERE
			d.ASSETNUM=:asset
		ORDER by
			a.BEGIN_KM, a.BEGIN_M
		]]
	local min_km, max_km
	if kms then
		for km, _ in pairs(kms) do
			min_km = min_km and math.min(min_km, km) or km
			max_km = max_km and math.max(max_km, km) or km
		end
	end
	local filter = true
	return ext_obj_utils.load_objects(sql, {asset=Passport.TRACK_CODE}, function (row)
		-- return true
		return not (
			filter and
			min_km and
			(min_km > row.END_KM or max_km < row.BEGIN_KM) )
	end)
end

local COL_N =
{
	name = "N",
	align = 'r',
	width = 30,
	get_text = function(row_n, _)
		return row_n
	end,
}

local function jump_pch(obj, begin)
	local path = begin and {obj.BEGIN_KM, obj.BEGIN_M, 0} or {obj.END_KM, obj.END_M, 0}
	ext_obj_utils.jump_path(path)
end

local COL_BEGIN =
{
	name = "Начало",
	align = 'r',
	width = 70,
	get_text = function(row_n, obj)
		return string.format("%d.%03d", obj.BEGIN_KM, obj.BEGIN_M)
	end,
	on_dbl_click = function(row_n, obj)
		jump_pch(obj, true)
	end,
}

local COL_END =
{
	name = "Конец",
	align = 'r',
	width = 70,
	get_text = function(row_n, obj)
		return string.format("%d.%03d", obj.END_KM, obj.END_M)
	end,
	on_dbl_click = function(row_n, obj)
		jump_pch(obj, false)
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

local COL_CHIEF =
{
	name = "Начальник",
	align = 'l',
	width = 120,
	get_text = function(row_n, obj)
		return obj.CHIEF_NAME
	end,
}

local COL_NOM  =
{
	name = "Номер",
	align = 'r',
	width = 50,
	get_text = function(row_n, obj)
		return obj.NUM
	end,
}

local COL_ID_PODR =
{
	name = "Подразделение",
	align = 'r',
	width = 50,
	get_text = function(row_n, obj)
		return obj.ID_PODR
	end,
}

local PCH = OOP.class
{
	name = "ПЧ",
	columns =
	{
		COL_N,
		COL_BEGIN,
		COL_END,
		COL_TYPE,
		COL_NOM,
		COL_ID_PODR,
		COL_CHIEF,
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
			local name = string.format("ПЧ %s (%s) %d.%03d - %d.%03d", obj.NUM, obj.ID_PODR, obj.BEGIN_KM, obj.BEGIN_M, obj.END_KM, obj.END_M)
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
        PCH,
    }
}
