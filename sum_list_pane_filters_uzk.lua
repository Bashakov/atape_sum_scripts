local filters = 
{
	{	
		group = {'Группа Магнитные', 'Группа Стыки'},
		name = 'Магнитные Стыки',
		columns = {
			column_num,
			column_path_coord, 
			column_rail,
			column_mag_use_recog,
			}, 
		GUIDS = {
			"{19253263-2C0B-41EE-8EAA-000000000010}",
			"{19253263-2C0B-41EE-8EAA-000000000040}",}
	},
	
	{
		group = {'Группа УЗ'},
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
	
	{
		name = 'Видимые', 
		columns = {
			column_num, 
			column_path_coord, 
			column_length,
			--column_rail,
			column_rail_lr,
			column_mark_type_name,
			column_recogn_video_channel,
			}, 
		visible = true,
	},
}

return filters
