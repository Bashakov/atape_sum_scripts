local OOP = require 'OOP'

COL_NUM =
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
		self.records = Driver:GetNoteRecords()
		return #self.records
	end,
	get_object = function (self, row)
		return self.records[row]
	end,
    OnMouse = function(self, act, flags, cell, pos_client, pos_screen)
        local object = self:get_object(cell.row)
        if act == 'left_dbl_click' and object then
            Driver:JumpNoteRec(object:GetNoteID())
        end
    end

}

return
{
    filters = {
        Notebook,
    }
}
