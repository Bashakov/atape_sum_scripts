local mark_helper = require 'sum_mark_helper'
local defect_codes = require 'report_defect_codes'
local table_merge = mark_helper.table_merge

local prev_atape = ATAPE
ATAPE = true -- disable debug code while load scripts
	local sum_report_joints = require "sum_report_joints"
ATAPE = prev_atape

local filters = 
{
	--!!! вывод всех объектов с ограничением скорости или дефектами // https://bt.abisoft.spb.ru/view.php?id=779
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', 'СТЫКИ'},
		name = 'Все замечания', 
		--!!! добавлены коды из report_defect_codes: "Превышение конструктивной величины стыкового зазора левой рельсовой нити"	"090004016149", "Превышение конструктивной величины стыкового зазора правой рельсовой нити"	"090004016150"
		videogram_defect_codes = {'090004012062', '090004016149', '090004016150', '090004000465','090004000466','090004000467','090004000471', "090004012002", "090004012004", "090004012001", "090004012008", "090004012062", "090004015840", "090004012058", "090004012059", "090004000474", "090004000477", "090004000465", "090004000521", "090004000394", "090004000394", "090004000394", "090004000370", "090004000375", "090004000370", "090004000375", "090004000999", "000000000000", "090004015367"}, --!!! все вместе
		columns = {
			column_num, 
			column_path_coord,
			column_pov_common,
			column_mark_type_name,
			column_joint_speed_limit,

			--column_sys_coord, 
			--column_rail,
			--column_recogn_width_inactive,
			--column_recogn_width_active,
			--column_recogn_width_tread,
			--column_recogn_width_user,
			--column_recogn_bolt,
			--column_recogn_video_channel,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local valid_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
			return valid_on_half and valid_on_half < 2
		end,
	},

	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', 'СТЫКИ'},
		name = 'Стыковые зазоры', 
		--videogram_defect_codes = {'090004012062', '090004016149', '090004016150'},
		columns = {
			column_num, 
			column_path_coord, 
			-- column_sys_coord, 
			column_rail,
			column_recogn_width_inactive,
			column_recogn_width_active,
			column_recogn_width_tread,
			column_recogn_width_user,
			column_gap_type,
			column_recogn_bolt,
			column_recogn_video_channel,
			column_pov_common,
			}, 
		GUIDS = table_merge(recognition_guids, '{3601038C-A561-46BB-8B0F-F896C2130003}'),
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', 'СТЫКИ'},
		name = 'Отсутствующие болты (вне норматива)', 
		-- videogram_defect_codes = {'090004000465'},
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_recogn_bolt,
			column_joint_speed_limit,
			column_gap_type,
			--column_recogn_reability,
			column_recogn_video_channel,
			column_pov_common,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local join_type = mark_helper.GetGapType(mark) 
			local valid_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
			return valid_on_half and valid_on_half < 2 and join_type ~= 2
		end,
		-- get_color = function(row, col)
		-- 	if col == 1 then
		-- 		return
		-- 	end
		-- 	local mark = work_marks_list[row]
		-- 	if not mark.user.color then
		-- 		local valid_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
		-- 		if valid_on_half and valid_on_half == 0 then
		-- 			mark.user.color = {0xff0000, 0xffffff}
		-- 		else
		-- 			mark.user.color = {0x000000, 0xffffff}
		-- 		end
		-- 	end
		-- 	return mark.user.color
		-- end
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Маячные отметки',
		--videogram_defect_codes = {'000000000000'},
		columns = {
			column_num,
			column_path_coord, 
			column_rail,
			column_beacon_offset,
			column_firtree_beacon,
			column_pov_common,
			column_mark_type_name
			}, 
		GUIDS = {
			"{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}", 	-- Маячная(Пользователь)
			"{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}",	-- Маячная
			"{3601038C-A561-46BB-8B0F-F896C2130006}",	-- Бесстыковой путь(Пользователь)
			"{D3736670-0C32-46F8-9AAF-3816DE00B755}",	-- Маячная Ёлка
		},
		post_load = function(marks)
			-- строим список отметок с рисками по рельсам, для поиска
			local beacons = {} -- список маячных отметок с рисками по рельсам
			for _, mark in ipairs(marks) do
				if mark.prop.Guid == "{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}" or
				   mark.prop.Guid == "{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}" then
					local rail_mask = bit32.band(mark.prop.RailMask, 0x03)
					if not beacons[rail_mask] then beacons[rail_mask] = {} end
					table.insert(beacons[rail_mask], mark)
				end
			end
			-- проходим по всем елкам и ищем для них соответствующие отметка с рисками
			local MAX_DISTANCE_TO_BEACON_TO_MISS = 300 -- интервал в котором относительно елки ищется маячная метка  
			for _, mark in ipairs(marks) do
				if mark.prop.Guid == "{D3736670-0C32-46F8-9AAF-3816DE00B755}" then
					local rail_mask = bit32.band(mark.prop.RailMask, 0x03)
					if beacons[rail_mask] then
						for _, bm in ipairs(beacons[rail_mask]) do
							local dist = math.abs(mark.prop.SysCoord - bm.prop.SysCoord)
							if dist < MAX_DISTANCE_TO_BEACON_TO_MISS then
								mark.user.beacon_id = bm.prop.ID
							end
						end
					end
				end
			end
			return marks
		end,
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
		--videogram_defect_codes = {'090004000457','090004000389','090004000402','090004015853','090004000400','090004000384','090004000395','090004000409','090004003539','090004000394','090004000385','090004000397','090004000405','090004000401','090004000478',},
		columns = {
			column_num,
			column_path_coord, 
			column_rail,
			column_fastener_type,
			column_fastener_fault,
			column_recogn_video_channel,
--			column_recogn_reability,
--			column_fastener_width,
			column_pov_common,
			}, 
		GUIDS = {
			"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}",
			"{3601038C-A561-46BB-8B0F-F896C2130001}",
		}
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Горизонтальные уступы', 
		--videogram_defect_codes = {'090004012059'},
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_recogn_width,
			column_recogn_rail_gap_step,
			column_recogn_video_channel,
			column_pov_common,
			}, 
		GUIDS = table_merge(recognition_guids, '{3601038C-A561-46BB-8B0F-F896C2130003}'),
		filter = function(mark)
			if mark.prop.Guid == '{3601038C-A561-46BB-8B0F-F896C2130003}' and mark.ext.CODE_EKASUI == '090004012059' then
				return true
			elseif mark.ext.RAWXMLDATA then
				local step = mark_helper.GetRailGapStep(mark)
				return step
			end
			return false
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
			--column_connections_defect,
			column_recogn_video_channel,
			column_pov_common,
			}, 
		GUIDS = recognition_guids,
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Приварные соединители', 
		--videogram_defect_codes = {'000000000001'},
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_rail_lr,
			column_weldedbond_status,
			--column_mark_id, для проверки
			column_pov_common,
		}, 
		GUIDS = recognition_guids,
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Поверхностные дефекты', 
		--videogram_defect_codes = {'090004012001'},
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_surf_defect_type,
			column_surf_defect_area,
			column_surf_defect_len,
			column_surf_defect_wdh,
			column_recogn_video_channel,
			column_pov_common,
			}, 
		GUIDS = recognition_surface_defects,
	},	
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ',},
		name = 'Дефекты накладок', 
		--videogram_defect_codes = {'090004000474'},
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_fishplate_state,
			column_recogn_video_channel,
			column_pov_common,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local fault = mark_helper.GetFishplateState(mark)
			return fault > 0
		end,
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', "Шпалы"},
		name = 'Шпалы(эпюра,перпедикулярность)',
		--videogram_defect_codes = {'090004000370', '090004000375'},
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
			column_pov_common,
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
		filter = function(mark)
			local maskChannel = mark.prop.ChannelMask
			local mask21 = bit32.lshift(1, 21)
			local mask22 = bit32.lshift(1, 22)
			return not(bit32.btest(maskChannel, mask21) or bit32.btest(maskChannel, mask22))
		end,
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', "Шпалы"},
		name = 'Шпалы Все',
		--videogram_defect_codes = {'090004000370', '090004000375'},
		columns = {
			column_num,
			column_path_coord,
			column_rail,
			column_mark_type_name,
			column_recogn_video_channel,
			column_pov_common,
			},
		GUIDS = {
			"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}",	-- Шпалы
			"{3601038C-A561-46BB-8B0F-F896C2130002}",	-- Шпалы(Пользователь)
			"{53987511-8176-470D-BE43-A39C1B6D12A3}",   -- SleeperTop
			"{1DEFC4BD-FDBB-4AC7-9008-BEEB56048131}",   -- SleeperDefect
		},
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', "Шпалы"},
		name = 'Шпалы сверху',
		--videogram_defect_codes = {'090004000370', '090004000375'},
		columns = {
			column_num,
			column_path_coord,
			column_rail,
			column_sleeper_meterial,
			column_recogn_video_channel,
			column_pov_common,
			},
		GUIDS = {
			"{53987511-8176-470D-BE43-A39C1B6D12A3}",   -- SleeperTop
		},
	},
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', "Шпалы"},
		name = 'Шпалы(дефекты)',
		--videogram_defect_codes = {'090004000370', '090004000375'},
		columns = {
			column_num,
			column_path_coord,
			column_rail,
			column_sleeper_fault,
			column_sleeper_meterial,
			column_recogn_video_channel,
			column_pov_common,
			},
		GUIDS = {
			"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}", -- Шпалы
			"{1DEFC4BD-FDBB-4AC7-9008-BEEB56048131}", -- SleeperDefect
		},
		filter = function (mark)
			local params = mark_helper.GetSleeperFault(mark)
			return params and params.FaultType and params.FaultType > 0
		end
	},
	--!!!добавлен новый элемент в фильтр - шпалы с разворотом более условного порога
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', "Шпалы"},
		name = 'Шпалы с разворотом',
		columns = {
			column_num,
			column_path_coord, 
			column_sleeper_angle,
			column_sleeper_meterial,
			column_pov_common,
			},
		GUIDS = {'{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}'},
		filter = function(mark)
			local sl_angle = mark_helper.GetSleeperAngle(mark)
			return sl_angle and sl_angle > 20 -- !!!установка порога
		end,
	},
	{	
		group = {'ВИДЕОРАСПОЗНАВАНИЕ'},
		name = 'Запуски распознавания',
		columns = {
			column_num,
			column_recog_dll_ver_VP,
			column_recog_dll_ver_cpu,
			column_recog_dll_ver_gpu,
			column_recog_dll_ver_mod,
			column_recog_run_date,
			column_recog_run_type,
			-- column_recog_dll_ver
		},
		GUIDS = {"{1D5095ED-AF51-43C2-AA13-6F6C86302FB0}"},
	},
	
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', 'СТЫКИ'},
		name = 'Слепые зазоры', 
		videogram_direct_set_defect = defect_codes.JOINT_NEIGHBO_BLIND_GAP,
		columns = {
			column_num,
			column_path_coord, 
			column_sys_coord, 
			column_rail,
			column_recogn_width,
			column_recogn_video_channel,
			column_mark_id,
			column_sleeper_dist_prev,
			column_pov_common,
			}, 
		GUIDS = table_merge(recognition_guids, '{3601038C-A561-46BB-8B0F-F896C2130003}'),
		filter = function(mark)
			if mark.prop.Guid == '{3601038C-A561-46BB-8B0F-F896C2130003}' and (
				mark.ext.CODE_EKASUI == defect_codes.JOINT_NEIGHBO_BLIND_GAP[1] or
				mark.ext.CODE_EKASUI == defect_codes.JOINT_NEIGHBO_BLIND_GAP_TWO[1] or
				mark.ext.CODE_EKASUI == defect_codes.JOINT_NEIGHBO_BLIND_GAP_MORE_LEFT[1] or
				mark.ext.CODE_EKASUI == defect_codes.JOINT_NEIGHBO_BLIND_GAP_MORE_RIGTH[1]
			) then
				return true
			elseif mark.ext.RAWXMLDATA then
				local width = mark_helper.GetGapWidth(mark)
				return width and width <= 3
			end
			return false
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
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', 'Групповые дефекты'},
		name = 'Групповые дефекты',
		columns = {
			column_num,
			column_path_coord_begin_end,
			column_length,
			column_rail,
			column_group_defect_count,
			column_ekasui_code,
			column_mark_type_name,
			column_pov_common,
		},
		GUIDS = {
			"{B6BAB49E-4CEC-4401-A106-355BFB2E0001}",
			"{B6BAB49E-4CEC-4401-A106-355BFB2E0002}",
			"{B6BAB49E-4CEC-4401-A106-355BFB2E0011}",
			"{B6BAB49E-4CEC-4401-A106-355BFB2E0012}",
			"{B6BAB49E-4CEC-4401-A106-355BFB2E0021}",
			"{B6BAB49E-4CEC-4401-A106-355BFB2E0022}",
		}
	},
}


return filters
