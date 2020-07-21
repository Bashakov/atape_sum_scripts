

local column_user_code_ekasui = 
{
	name = 'ЕКАСУИ', 
	width = 85, 
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		return mark.ext.CODE_EKASUI
	end,
	sorter = function(mark)
		return mark.ext.CODE_EKASUI
	end
}

local column_user_name = 
{
	name = 'Тип', 
	width = 120, 
	align = 'l',
	text = function(row)
		local mark = work_marks_list[row]
		local desc = mark.prop.Description
		local p = desc:find('\n')
		if p then desc = desc:sub(1, p-1) end
		return desc
	end,
	sorter = function(mark)
		local desc = mark.prop.Description
		local p = desc:find('\n')
		if p then desc = desc:sub(1, p-1) end
		return desc
	end
}

local filters = 
{
	{	
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', 'СТЫКИ'},
		name = 'Введенные пользователем',
		columns = {
			column_num,
			column_path_coord, 
			column_rail,
			column_user_code_ekasui,
			column_user_name, 
			column_pov_common,
			column_pov_operator,
			column_pov_ekasui,
			column_pov_report,
			column_pov_rejected,
		}, 
		GUIDS = {
			"{3601038C-A561-46BB-8B0F-F896C2130001}",
			"{3601038C-A561-46BB-8B0F-F896C2130002}",
			"{3601038C-A561-46BB-8B0F-F896C2130003}",
			"{3601038C-A561-46BB-8B0F-F896C2130004}",
			"{3601038C-A561-46BB-8B0F-F896C2130005}",
			"{3601038C-A561-46BB-8B0F-F896C2130006}",
		}
	},
}

return filters