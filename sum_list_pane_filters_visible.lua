local filters = 
{
	{
		group = {'НПУ','ВИДЕОРАСПОЗНАВАНИЕ', "Пользовательский фильтр"},
		name = 'Глобальный фильтр', 
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
