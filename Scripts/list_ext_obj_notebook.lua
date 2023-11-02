local OOP = require 'OOP'
local ntb = require 'notebook_xml_utils'

local COL_NUM =
{
	name = "N",
	align = 'r',
	width = 40,
	get_text = function(row_n, obj)
		return string.format("%d", row_n)
	end,
}

local COL_NOTE_PATH_KM =
{
	name = "КМ",
	align = 'r',
	width = 30,
	get_text = function(row_n, obj)
		local km, m, mm = obj:GetPath()
		if km then
			return string.format("%d", km)
		end
	end,
}

local COL_NOTE_INCLUDED =
{
	name = "Вкл",
	align = 'c',
	width = 30,
	get_text = function(row_n, obj)
		local incl = obj:GetIncluded()
		return incl and "да" or "нет"
	end,
    get_color = function(row_n, obj)
        local incl = obj:GetIncluded()
        return incl and {0xff0000, 0xffffff} or {0xaaaaaa, 0xffffff}
    end
}

local COL_NOTE_PATH_M =
{
	name = "метр",
	align = 'r',
	width = 50,
	get_text = function(row_n, obj)
		local km, m, mm = obj:GetPath()
		if m and mm then
			return string.format("%.2f", (m+mm/1000))
		end
	end,
}

local COL_NOTE_PLACMENT =
{
	name = "Привязка",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return obj:GetPlacement()
	end,
}

local COL_NOTE_ACTION =
{
	name = "Тип осмотра",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return obj:GetAction()
	end,
}

local COL_NOTE_DESCRIPTION =
{
	name = "Описание",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return obj:GetDescription()
	end,
}

local Notebook = OOP.class
{
	name = "Записная книжка",
	columns =
	{
		COL_NUM,
		COL_NOTE_PATH_KM,
		COL_NOTE_PATH_M,
		COL_NOTE_INCLUDED,
        COL_NOTE_PLACMENT,
        COL_NOTE_ACTION,
        COL_NOTE_DESCRIPTION
	},
	ctor = function (self)
		local rawNtb = Driver:GetRawNotebook()
		self.records = ntb.load_str(rawNtb)
		return #self.records
	end,
	get_object = function (self, row)
		return self.records[row]
	end,
    OnMouse = function(self, act, flags, cell, pos_client, pos_screen)
        local object = self:get_object(cell.row)
        if act == 'left_dbl_click' and object then
			Driver:JumpSysCoord(object:GetLeftCoord(), {scale=object:GetScale(), border='l'})
        end
    end,
	GetExtObjMarks = function (self)
		local res = {}
		for i, obj in ipairs(self.records) do
			local incuded = obj:GetIncluded()
			res[i] = {
				sys_coord=obj:GetMarkCoord(),
				description = string.format("%s\n%s\n%s", obj:GetPlacement(), obj:GetAction(), obj:GetDescription()),
				vert_line = 1,
				icon_file = 'Images/SUM.bmp',
				icon_rect = {(incuded and 1 or 7) * 16, 32, 16, 16},
				id = i,
			}
		end
		return res
	end,

}

return
{
    filters = {
        Notebook,
    }
}
