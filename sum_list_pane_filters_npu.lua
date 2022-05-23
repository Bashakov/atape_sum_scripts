local filters = 
{
	{
		group = {'НПУ'},
		name = 'Нпу', 
		columns = {
			column_num, 
			column_path_coord, 
			column_length_npu,
			--column_rail,
			column_rail_lr,
			column_npu_type,
			column_mark_desc,
			}, 
		GUIDS = NPU_guids,
	},

}

return filters
