local filters = 
{
	{	
		group = {'РАСПОЗНАВАНИЕ МАГНИТНОГО', 'СТЫКИ'},
		name = 'Магнитные Стыки',
		columns = {
			column_num,
			column_path_coord, 
			column_rail,
			column_length,
			column_mark_type_name,
			column_mag_use_recog,
			}, 
		GUIDS = {
			"{19253263-2C0B-41EE-8EAA-000000000010}",
			"{19253263-2C0B-41EE-8EAA-000000000040}",}
	},
}

return filters
