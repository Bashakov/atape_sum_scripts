local filters = 
{
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', 'СТЫКИ'},
		name = 'Стыковые зазоры', 
		columns = {
			column_num, 
			column_path_coord, 
			column_sys_coord, 
			column_rail,
			column_recogn_width_inactive,
			column_recogn_width_active,
			column_recogn_width_tread,
			column_recogn_width_user,
			column_recogn_bolt,
			column_recogn_video_channel,
			column_user_accept,
			}, 
		GUIDS = recognition_guids,
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', 'СТЫКИ'},
		name = 'Отсутствующие болты (вне норматива)', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_recogn_bolt,
			column_joint_speed_limit,
			--column_recogn_reability,
			column_recogn_video_channel,
			column_user_accept,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local valid_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
			return valid_on_half and valid_on_half < 2
		end,
		get_color = function(row, col)
			if col == 1 then
				return
			end
			local mark = work_marks_list[row]
			if not mark.user.color then
				local valid_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
				if valid_on_half and valid_on_half == 0 then
					mark.user.color = {0xff0000, 0xffffff}
				else
					mark.user.color = {0x000000, 0xffffff}
				end
			end
			return mark.user.color
		end
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Маячные отметки',
		columns = {
			column_num,
			column_path_coord, 
			column_rail,
			column_beacon_offset,
			column_user_accept,
			}, 
		GUIDS = {
			"{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}",
			"{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}",}
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Ненормативный объект', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_mark_desc,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_NonNormal_defects,
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Скрепления',
		columns = {
			column_num,
			column_path_coord, 
			column_rail,
			column_fastener_type,
			column_fastener_fault,
--			column_recogn_reability,
--			column_fastener_width,
			}, 
		GUIDS = {
			"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}",}
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Горизонтальные уступы', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_recogn_width,
			column_recogn_rail_gap_step,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local step = mark_helper.GetRailGapStep(mark)
			return step 
		end,
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Штепсельные соединители', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_rail_lr,
			column_connections_all,
			column_connections_defect,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local all, fault = mark_helper.GetConnectorsCount(mark)
			return all 
		end,
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Приварные соединители', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_rail_lr,
			column_weldedbond_status,
			--column_mark_id, для проверки
		}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local status = mark_helper.GetWeldedBondStatus(mark)
			return status 
		end,
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Поверхностные дефекты', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_surf_defect_type,
			column_surf_defect_area,
			column_surf_defect_len,
			column_surf_defect_wdh,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_surface_defects,
	},	
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ',},
		name = 'Дефекты накладок', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_fishplate_state,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local fault = mark_helper.GetFishplateState(mark)
			return fault > 0
		end,
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Шпалы(эпюра,перпедикулярность)',
		columns = {
			column_num,
			column_path_coord, 
			column_rail, 
			column_sleeper_angle,
			column_sleeper_meterial,
			column_recogn_video_channel,
			column_sleeper_dist_prev,
			column_sleeper_dist_next,
			column_sys_coord,
			}, 
		GUIDS = {
			"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}"},
		post_load = function(marks)
			local prev_pos = nil
			marks = sort_stable(marks, column_sys_coord.sorter, true)
			for left, cur, right in mark_helper.enum_group(marks, 3) do
				local pp, cp, np = left.prop.SysCoord, cur.prop.SysCoord, right.prop.SysCoord
				cur.user.dist_prev = cp - pp
				cur.user.dist_next = np - cp
			end
			return marks
		end,
	},
	{	
		name = 'Запуски распознавания',
		columns = {
			column_num,
			column_recog_run_date,
			column_recog_run_type,
			column_recog_dll_ver
			}, 
		GUIDS = {"{1D5095ED-AF51-43C2-AA13-6F6C86302FB0}"},
	},
	
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', 'СТЫКИ'},
		name = 'Слепые зазоры', 
		columns = {
			column_num,
			column_path_coord, 
			column_sys_coord, 
			column_rail,
			column_recogn_width,
			column_recogn_video_channel,
			column_mark_id,
			column_sleeper_dist_prev,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local width = mark_helper.GetGapWidth(mark)
			return width and width <= 3
		end,	
		post_load = function(marks)
			local prev_pos = {} -- координата пред стыка (по рельсам)
			marks = sort_stable(marks, column_sys_coord.sorter, true)	-- сортируем отметки от драйвера по координате
			for _, mark in ipairs(marks) do	-- проходим по отметкам
				local r = bit32.band(mark.prop.RailMask, 3)	-- получаем номер рельса
				if prev_pos[r] then	-- если есть коордиана предыдущей
					local delta = mark.prop.SysCoord - prev_pos[r]	        -- в пользовательские данные отметки заносим растойние до нее
					if ( delta > 27000 or delta < 10500) then 
						delta=0
					end
					mark.user.dist_prev = delta --tostring(delta) 
				end
				prev_pos[r] = mark.prop.SysCoord	-- и сохраняем положение этой отметки
			end
			return marks	-- возвращаем список для отображения
		end,
	},
}


return filters
