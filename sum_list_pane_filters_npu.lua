local filters = 
{
	{
		group = {'НПУ'},
		name = 'НПУ', 
		columns = {
			column_num, 
			column_path_coord, 
			column_length_npu,
			--column_rail,
			column_rail_lr,
			column_npu_type,
			}, 
		GUIDS = NPU_guids,
		on_context_menu = function(row, col)
			local mark = work_marks_list[row]
			local prop = mark.prop
			local pos = table_find(NPU_guids, prop.Guid)
			if pos == 1 and MarkTable:PopupMenu({"Подтвр. НПУ"}) == 1 then
				prop.Guid = NPU_guids[2]
				mark:Save()
				MarkTable:Invalidate(row)
				Driver:RedrawView()
			elseif pos == 2 and MarkTable:PopupMenu({"Возможн. НПУ"}) == 1 then
				prop.Guid = NPU_guids[1]
				mark:Save()
				MarkTable:Invalidate(row)
				Driver:RedrawView()
			end
		end,
	},

}

return filters
