local defect_codes = require 'report_defect_codes'

local filters = 
{
	{
		group = {'UIC'},
		name = 'Surface Defects', 
		--videogram_defect_codes = {'090004012001'},
		columns = {
			--column_mark_id,
			column_num, 
			column_path_coord, 
			column_rail_hun,
			--column_surf_defect_type,
			column_surf_defect_area,
			column_surf_defect_len,
			column_surf_defect_wdh,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_uic_surface_defects,
	},	
	
	{
		group = {'UIC'},
		name = 'Visible in filter panel', 
		columns = {
			column_num, 
			column_path_coord, 
			---- column_length,
			column_rail_hun,
			column_mark_type_name,
			column_recogn_video_channel,
			}, 
		visible = true,
	},

	{
		group = {'UIC'},
		name = 'Recog Lanch',
		columns = {
			column_num,
			column_recog_run_date,
			column_recog_run_type,
			column_recog_dll_ver
			}, 
		GUIDS = {"{1D5095ED-AF51-43C2-AA13-6F6C86302FB0}"},
	},	
	
}

return filters
