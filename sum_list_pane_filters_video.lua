local mark_helper = require 'sum_mark_helper'
local defect_codes = require 'report_defect_codes'

local table_merge = mark_helper.table_merge
local TYPES = require 'sum_types'

local prev_atape = ATAPE
ATAPE = true -- disable debug code while load scripts
	local sum_report_joints = require "sum_report_joints"
	local sum_report_beacon = require 'sum_report_beacon'
ATAPE = prev_atape


local SHOW_SLEEPER_UNKNOWN_MATERIAL = true

-- https://bt.abisoft.spb.ru/view.php?id=816#c4204
local SLEEPER_ANGLE_TRESHOLD_RAD = 0.1


local function filter_sleeper_mark_by_angle(mark, treshold)
	local angle = mark_helper.GetSleeperAngle(mark)
	if not angle then
		return false
	end
	angle = math.abs(angle) / 1000
	return angle >= treshold
end

local function get_sleeper_angle_defect(mark, treshold, material)
	if treshold == 0 then
		return ''
	end

	if filter_sleeper_mark_by_angle(mark, treshold) then
		if material == 1 then -- "бетон",
			return defect_codes.SLEEPER_ANGLE_CONCRETE[1]
		elseif material == 2 then -- "дерево",
			return defect_codes.SLEEPER_ANGLE_WOOD[1]
		end
		return ''
	end

	return false
end

local function parse_velocity(val)
	local t = type(val)
	if t == "number" or t == "nil" then
		return val
	end
	assert(t == 'string')
	if val == '' then
		return nil
	end
	local n = tonumber(val)
	return n or 0
end


local filters =
{
	--!!! вывод всех объектов с ограничением скорости или дефектами // https://bt.abisoft.spb.ru/view.php?id=779
	{
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', 'СТЫКИ'},
		name = 'Замечания с ограничением скорости',
		--!!! добавлены коды из report_defect_codes: "Превышение конструктивной величины стыкового зазора левой рельсовой нити"	"090004016149", "Превышение конструктивной величины стыкового зазора правой рельсовой нити"	"090004016150"
		videogram_defect_codes = {
			-- устаревшие
			'090004000465', -- JOINT_MISSING_BOLT !!! код удален из классификатора
			"090004000999", -- SLEEPER_ANGLE !!! код удален из классификатора

			-- тестированы
			'090004012062', '090004016149', '090004016150', -- JOINT_EXCEED_GAP_WIDTH, JOINT_EXCEED_GAP_WIDTH_LEFT, JOINT_EXCEED_GAP_WIDTH_RIGHT
			'090004000466', -- JOINT_MISSING_BOLT_TWO_GOOD
			'090004000471', -- JOINT_MISSING_BOLT_ONE_GOOD
			"090004000521", -- JOINT_WELDED_BOND_FAULT
			"090004000394", -- FASTENER_MISSING_BOLT, FASTENER_MISSING_CLAMP_BOLT
			"090004000375", -- SLEEPER_DISTANCE_CONCRETE

			-- не тестированы (нет данных)
			'090004000467', -- JOINT_MISSING_BOLT_NO_GOOD
			"090004000370", -- SLEEPER_DISTANCE_WOODEN

			-- не тестированы
			"090004015367", -- BEACON_MISSING_LINE

			-- не устанавливаются
			"090004015840", -- JOINT_NEIGHBO_BLIND_GAP
			"090004012002", -- RAIL_DEFECT_BASE
			"090004012004", -- RAIL_BREAK
			"090004012001", -- RAIL_SURF_DEFECT
			"090004012058", -- JOINT_VER_STEP
			"090004012059", -- JOINT_HOR_STEP
			"090004000474", -- JOINT_FISHPLATE_DEFECT
			"090004000477", -- JOINT_FISHPLATE_MISSING
			"090004012008", -- RAIL_DEFECT_HEAD
		},
		columns = {
			column_num,
			column_path_coord,
			column_pov_common,
			column_defect_code_list,
			column_speed_limit_list,
			column_mark_type_name,
			column_defect_code_desc_list,
		},
		GUIDS = recognition_guids,
		post_load = function(marks, fnContinueCalc)
			local id2defects = {}
			local id2speedlimit = {}

			for group, defect_code, speed_limit in sum_report_joints.iter_blind_group_defect_code(marks, nil, fnContinueCalc) do
				-- JOINT_NEIGHBO_BLIND_GAP_TWO, JOINT_NEIGHBO_BLIND_GAP_MORE_LEFT, JOINT_NEIGHBO_BLIND_GAP_MORE_RIGHT
				-- 'ЗАПРЕЩЕНО'
				local id = group[1].prop.ID
				id2defects[id] = defect_code
				id2speedlimit[id] = parse_velocity(speed_limit)
			end

			local res = {}

			for i, mark in ipairs(marks) do
				local codes, limits = {}, {}
				if true then
					local id = mark.prop.ID
					if id2speedlimit[id] then
						table.insert(codes, id2defects[id])
						table.insert(limits, id2speedlimit[id])
					end
				end

				if true then
					-- JOINT_EXCEED_GAP_WIDTH_LEFT, JOINT_EXCEED_GAP_WIDTH_RIGHT
					-- '100', '60', '25', 'Движение закрывается'
					local defect_code, speed_limit = sum_report_joints.get_mark_gap_width_defect_code(mark)
					speed_limit = parse_velocity(speed_limit)
					if speed_limit then
						table.insert(codes, defect_code)
						table.insert(limits, speed_limit)
					end
				end

				if true then
					-- JOINT_MISSING_BOLT_ONE_GOOD[1], '25',
					-- JOINT_MISSING_BOLT_NO_GOOD[1], 'Закрытие движения'
					local defect_code, speed_limit = sum_report_joints.bolt2defect_limit(mark)
					speed_limit = parse_velocity(speed_limit)
					if speed_limit then
						table.insert(codes, defect_code)
						table.insert(limits, speed_limit)
					end
				end

				if true then
					-- DEFECT_CODES.JOINT_HOR_STEP, JOINT_STEP_VH_LT25
					-- '80', '50', '40', '25',	'15', 'Движение закрывается'
					local defect_code, speed_limit = sum_report_joints.get_joint_step_defect_code(mark)
					speed_limit = parse_velocity(speed_limit)
					if speed_limit then
						table.insert(codes, defect_code)
						table.insert(limits, speed_limit)
					end
				end

				if true then
					-- JOINT_FISHPLATE_DEFECT, JOINT_FISHPLATE_DEFECT_ONE, JOINT_FISHPLATE_DEFECT_BOTH, JOINT_FISHPLATE_DEFECT_SINGLE
					-- 'Движение закрывается', '40','Замечание'
					local defect_code, speed_limit = sum_report_joints.get_fishplate_defect_code(mark)
					speed_limit = parse_velocity(speed_limit)
					if speed_limit then
						table.insert(codes, defect_code)
						table.insert(limits, speed_limit)
					end
				end

				if #limits > 0 then
					mark.user.defect_codes = codes
					mark.user.speed_limits = limits
					table.insert(res, mark)

					if not fnContinueCalc(i / #marks) then
						break
					end
				end
			end
			return res
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
			column_pair_beacon,
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
			local beacons = sum_report_beacon.SearchMissingBeacons()
			beacons:load_marks(marks, nil)

			-- поиск меток не имеющих парных отметок
			for _, mark in ipairs(marks) do
				local found = not beacons:is_miss_mark(mark)
				if beacons.is_firtree(mark) then
					mark.user.correspond_beacon_found = found
				end
				if beacons.is_beacon(mark) then
					mark.user.pair_beacon_found = found
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
		GUIDS = {
			TYPES.UNSPC_OBJ
		},
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
			TYPES.FASTENER,
			TYPES.FASTENER_USER,
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
		name = 'III Соединитель',  -- Приварные соединители https://bt.abisoft.spb.ru/view.php?id=834#c4240
		--videogram_defect_codes = {'000000000001'},
		columns = {
			column_num,
			column_path_coord,
			column_rail,
			column_rail_lr,
			-- column_gap_type,
			-- column_weldedbond_status,
			column_weldedbond_defect_code,
			--column_mark_id, для проверки
			column_pov_common,
		},
		GUIDS = recognition_guids,
		filter = function(mark)
			-- https://bt.abisoft.spb.ru/view.php?id=834
			-- В списке приварные соединители соединителях нужны только неисправные. исправные не нужно отображать
			local code = mark_helper.GetWeldedBondDefectCode(mark)
			return code
		end,
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
		-- https://bt.abisoft.spb.ru/view.php?id=815
		-- https://bt.abisoft.spb.ru/view.php?id=863
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', "Шпалы"},
		name = 'III Шпалы: эпюра',
		columns = {
			column_num,
			column_path_coord,
			column_sleeper_meterial,
			column_sleeper_dist_next,
			column_sleeper_epure_defect_user,
			--column_sys_coord,
			column_pov_common,
			},
		GUIDS = {
			"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}"},
		post_load = function(marks, fnContinueCalc)
			local sleeper_count = 1840
			local MEK = 4
			marks = mark_helper.sort_mark_by_coord(marks)
			local res = {}
			local i = 1
			for mark, right in mark_helper.enum_group(marks, 2) do
				local cp, np = mark.prop.SysCoord, right.prop.SysCoord
				mark.user.dist_next = np - cp
				local material = mark_helper.GetSleeperMeterial(mark)
				if not material and SHOW_SLEEPER_UNKNOWN_MATERIAL then
					material = 1 -- https://bt.abisoft.spb.ru/view.php?id=863#c4393 В случае "не скрывать" - считать все шнапля ЖБ 
				end
				if material == 1 or material == 2 then
					local dist_ok, defect_code = mark_helper.CheckSleeperEpure(mark, sleeper_count, MEK, mark.user.dist_next, material)
					if not dist_ok then
						mark.user.defect_code = defect_code or ''
						table.insert(res, mark)
					end
				end
				if fnContinueCalc and not fnContinueCalc(i / #marks) then
					return {}
				end
				i = i + 1
			end
			return res
		end,
	},
	{
		-- https://bt.abisoft.spb.ru/view.php?id=863
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', "Шпалы"},
		name = 'III Шпалы: дефекты',
		columns = {
			column_num,
			column_path_coord,
			column_sleeper_meterial,
			--column_sleeper_dist_next,
			column_sleeper_fault,
			--column_sys_coord,
			column_pov_common,
			},
		GUIDS = {
			"{1DEFC4BD-FDBB-4AC7-9008-BEEB56048131}",  -- Дефекты шпал
		},
	},
	{
		-- https://bt.abisoft.spb.ru/view.php?id=863
		group = {'ВИДЕОРАСПОЗНАВАНИЕ', "Шпалы"},
		name = 'III Шпалы: разворот',
		columns = {
			column_num,
			column_path_coord,
			column_rail,
			column_sleeper_angle,
			column_sleeper_meterial,
			column_recogn_video_channel,
			column_sleeper_epure_defect_user,
			--column_sys_coord,
			column_pov_common,
			},
		GUIDS = {
			"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}"},
		filter = function (mark)
			local maskChannel = mark.prop.ChannelMask
			if not bit32.btest(maskChannel, 0x1e0000) then -- 17, 18 ,19, 20
				return false
			end

			local material = mark_helper.GetSleeperMeterial(mark)
			if not material and SHOW_SLEEPER_UNKNOWN_MATERIAL then
				material = 1 -- https://bt.abisoft.spb.ru/view.php?id=863#c4393 В случае "не скрывать" - считать все шнапля ЖБ 
			end
			if material == 1 or material == 2 then
				local angle_defect = get_sleeper_angle_defect(mark, SLEEPER_ANGLE_TRESHOLD_RAD, material)
				if angle_defect then
					mark.user.defect_code = angle_defect
					return true
				end
			end
			return false
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
				mark.ext.CODE_EKASUI == defect_codes.JOINT_NEIGHBO_BLIND_GAP_MORE_RIGHT[1]
			) then
				return true
			elseif mark.ext.RAWXMLDATA then
				local width = mark_helper.GetGapWidth(mark)
				return width and width <= 3
			end
			return false
		end,
		post_load = function(marks, fnContinueCalc)
			local prev_pos = {} -- координата пред стыка (по рельсам)
			marks = sort_stable(marks, column_sys_coord.sorter, true)	-- сортируем отметки от драйвера по координате
			for i, mark in ipairs(marks) do	-- проходим по отметкам
				local r = bit32.band(mark.prop.RailMask, 3)	-- получаем номер рельса
				if prev_pos[r] then	-- если есть коордиана предыдущей
					local delta = mark.prop.SysCoord - prev_pos[r]	        -- в пользовательские данные отметки заносим растойние до нее
					if ( delta > 27000 or delta < 10500) then 
						delta=0
					end
					mark.user.dist_prev = delta --tostring(delta) 
				end
				prev_pos[r] = mark.prop.SysCoord	-- и сохраняем положение этой отметки
				if fnContinueCalc and not fnContinueCalc(i / #marks) then
					return {}
				end
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
			column_ekasui_code_speed_limit_tbl,
			column_mark_type_name,
			column_pov_common,
		},
		GUIDS = {
			"{B6BAB49E-4CEC-4401-A106-355BFB2E0001}",
			"{B6BAB49E-4CEC-4401-A106-355BFB2E0002}",
			"{B6BAB49E-4CEC-4401-A106-355BFB2E0011}",
			"{B6BAB49E-4CEC-4401-A106-355BFB2E0012}",
			TYPES.GROUP_FSTR_AUTO,
			TYPES.GROUP_FSTR_USER,
		}
	},
}


return filters
