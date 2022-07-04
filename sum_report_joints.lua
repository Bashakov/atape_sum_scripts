if not ATAPE then
	require "iuplua"
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"

local OOP = require 'OOP'
local mark_helper = require 'sum_mark_helper'
local DEFECT_CODES = require 'report_defect_codes'
local EKASUI_REPORT = require 'sum_report_ekasui'
local AVIS_REPORT = require 'sum_report_avis'
local sumPOV = require "sumPOV"
local remove_grouped_marks = require "sum_report_group_scanner"
local TYPES = require 'sum_types'

local printf = mark_helper.printf
local sprintf = mark_helper.sprintf


local video_joints_juids =
{
	TYPES.VID_INDT_1,	-- Стык(Видео)
	TYPES.VID_INDT_2,	-- Стык(Видео)
	TYPES.VID_INDT_3,	-- СтыкЗазор(Пользователь)
	TYPES.VID_INDT_ATS,	-- АТСтык(Видео)

	TYPES.VID_ISO, 	-- ИзоСтык(Видео)

	TYPES.RAIL_JOINT_USER,	-- Рельсовые стыки(Пользователь)
}

local joints_group_defects =
{
	"{B6BAB49E-4CEC-4401-A106-355BFB2E0001}",	-- GROUP_GAP_AUTO
	"{B6BAB49E-4CEC-4401-A106-355BFB2E0002}",	-- GROUP_GAP_USER
}

-- =============================================================================


local function GetMarks()
 	local gg = mark_helper.table_merge(video_joints_juids, joints_group_defects)
	local marks = Driver:GetMarks{GUIDS=gg}
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end


local function MakeJointMarkRow(mark, defect_code, gap_width)
	local row = mark_helper.MakeCommonMarkTemplate(mark)

	row.SPEED_LIMIT = ''
	row.GAP_WIDTH = gap_width or mark_helper.GetGapWidth(mark)
	row.BLINK_GAP_COUNT = ''

	if defect_code then
		if type(defect_code) == 'table' then defect_code = defect_code[1] end
		assert(type(defect_code) == 'string')
		row.DEFECT_CODE = defect_code
		row.DEFECT_DESC = DEFECT_CODES.code2desc(defect_code)
	end
	return row
end


-- ============================================================================= --


local function get_mark_gap_width_defect_code(mark)
	local function width2speed(gap_width)
		if gap_width <= 26 then return '100' end
		if gap_width <= 30 then	return '60'	 end
		if gap_width <= 35 then	return '25'	 end
		return 'Движение закрывается'
	end

	local function get_code_by_rail(defect_code)
		--[[ https://bt.abisoft.spb.ru/view.php?id=722#c3398
		1. новый прикол дефект 090004012062 разнесен по 2 ниткам.
		Превышение конструктивной ширины зазора левой нити(90004016149) и правой нити(90004016150). ]]
		if not defect_code or defect_code == DEFECT_CODES.JOINT_EXCEED_GAP_WIDTH[1] then
			local rail_pos = mark_helper.GetMarkRailPos(mark)
			if rail_pos	== -1 then
				defect_code = DEFECT_CODES.JOINT_EXCEED_GAP_WIDTH_LEFT[1]
			else
				defect_code = DEFECT_CODES.JOINT_EXCEED_GAP_WIDTH_RIGHT[1]
			end
		end
		return defect_code
	end

	if mark.prop.Guid == TYPES.RAIL_JOINT_USER and (
			mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_EXCEED_GAP_WIDTH[1] or
			mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_EXCEED_GAP_WIDTH_LEFT[1] or
			mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_EXCEED_GAP_WIDTH_RIGHT[1]
		) then
			local defect_code = get_code_by_rail(mark.ext.CODE_EKASUI)
			local gap_width = mark_helper.GetGapWidth(mark)
			return defect_code, width2speed(gap_width), gap_width
	else
		local gap_width = mark_helper.GetGapWidth(mark)
		if gap_width and gap_width > 24 then
			local defect_code = get_code_by_rail(mark.ext.CODE_EKASUI)
			return defect_code, width2speed(gap_width), gap_width
		end
	end
end

local function make_mark_gap_width_exceed(mark)
	local defect_code, speed_limit, gap_width = get_mark_gap_width_defect_code(mark)
	if defect_code then
		local row = MakeJointMarkRow(mark, defect_code, gap_width)
		row.SPEED_LIMIT = speed_limit
		assert(row.GAP_WIDTH == gap_width)
		return row
	end
end

local function generate_rows_joint_width(marks, dlgProgress, pov_filter)
	local report_rows = {}
	for i, mark in ipairs(marks) do
		if pov_filter(mark) then
			local row = make_mark_gap_width_exceed(mark)
			if row then
				table.insert(report_rows, row)
			end
		end
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end
	return report_rows
end

-- -------------------------------------------- --

-- поиск групп слепых зазоров по одному рельсу
local function scan_for_neigh_blind_joint(marks, fnProgress)

	local WIDTH_THRESHOLD = 3
	local groups = {}
	local rail_group = {[1]={}, [2]={}}

	marks = mark_helper.sort_mark_by_coord(marks)
	for i, mark in ipairs(marks) do
		local rail_mask = mark.prop.RailMask
		local width = mark_helper.GetGapWidth(mark) or 100000
		for r, g in ipairs(rail_group) do
			if bit32.band(r, rail_mask) ~= 0 then
				if width <= WIDTH_THRESHOLD then
					table.insert(g, mark)
				else
					if #g >= 2 then
						table.insert(groups, g)
					end
					rail_group[r] = {}
				end
			end
		end

		if i % 20 == 0 and not fnProgress(i / #marks, string.format('Поиск %d / %d', i, #marks)) then
			break
		end
	end

	for _, g in ipairs(rail_group) do
		if #g >= 2 then
			table.insert(groups, g)
		end
	end

	groups = mark_helper.sort_stable(groups, function(group)
		local c = group[1].prop.SysCoord
		return c
	end)

	return groups
end

local function get_blind_defect_code(mark)
	local blind_defect_codes =
	{
		DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP[1],
		DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_TWO[1],
		DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_LEFT[1],
		DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_RIGHT[1],
	}
	if( mark.prop.Guid == TYPES.RAIL_JOINT_USER or mark_helper.table_find(joints_group_defects, mark.prop.Guid)) and
		mark_helper.table_find(blind_defect_codes, mark.ext.CODE_EKASUI) then
			return mark.ext.CODE_EKASUI, nil
	end
end

local function iter_blind_group_defect_code(marks, pov_filter, fnProgress)
	pov_filter = pov_filter or function () return {1} end

	local function group2defectcode(group)
		if #pov_filter(group) > 0 then
			local rail_pos = mark_helper.GetMarkRailPos(group[1])
			-- [[https://bt.abisoft.spb.ru/view.php?id=765]]
			if #group == 2 then
				return DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_TWO[1]
			elseif(rail_pos == -1) then
				return DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_LEFT[1]
			else
				return DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_RIGHT[1]
			end
		end
	end

	local function group2speedlimit(group)
		local temperature = mark_helper.GetTemperature(group[1]) or 0
		if temperature > 0 then                     -- считаем, при 20 градусах лето ???
			local to_report = false
			local speed_limit

			local RAIL_12500_LENGTH_MIN = 10500
			local RAIL_12500_LENGTH_MAX = 14500
			local RAIL_25000_LENGTH_MIN = 23000
			local RAIL_25000_LENGTH_MAX = 27000

			local SysCoord1 = group[1].prop.SysCoord
			local SysCoord2 = group[#group].prop.SysCoord

			local rail_max_length = 0 -- максимальная длина из группы
			for j = 1, #group-1 do
				rail_max_length	= math.max(rail_max_length, group[j+1].prop.SysCoord - group[j].prop.SysCoord)
			end

			local rail_group_length = 0
			rail_group_length = math.max( rail_group_length,  SysCoord2 - SysCoord1 )
			local rail_average_length = rail_group_length/(#group-1)

			-- ограничиваем по длине отметки включаемые в отчет
			-- если максимальная длина звена в диапазоне и 12.5 и 25 звеньев - то в отчет
			if ( rail_max_length > RAIL_12500_LENGTH_MIN and rail_max_length < RAIL_25000_LENGTH_MAX) then
				to_report = true
			end

			--print( "****", #group, rail_group_length, rail_max_length, rail_average_length, SysCoord1, SysCoord1, to_report )

			-- определяем является ли звено 25-метровым - находится в диапазоне.
			if ( rail_max_length > RAIL_25000_LENGTH_MIN and  rail_max_length< RAIL_25000_LENGTH_MAX ) then
				if  #group >= 2 then -- ограничение для 25 метрового: звена  больше 2-ух подряд
					speed_limit = 'ЗАПРЕЩЕНО'
					to_report = true
				end
			end

			-- определяем является ли звено 12.5-метровым - находится в диапазоне.
			if ( rail_max_length > RAIL_12500_LENGTH_MIN and  rail_max_length< RAIL_12500_LENGTH_MAX ) then
				if #group >= 4 then -- ограничение для 12.5 метрового: звена  больше 4-ух подряд
					speed_limit = 'ЗАПРЕЩЕНО'
					to_report = true
				end
			end

			if to_report then
				return to_report, speed_limit
			end
		end
	end

	local groups = scan_for_neigh_blind_joint(marks, fnProgress)
	return coroutine.wrap(function()
		for i, group in ipairs(groups) do
			local defect_code = group2defectcode(group)
			if defect_code then
				local to_report, speed_limit = group2speedlimit(group)
				-- добавляем в отчет
				if to_report then
					coroutine.yield(group, defect_code, speed_limit)
				end
			end
		end
	end)
end

local function generate_rows_neigh_blind_joint(marks, dlgProgress, pov_filter)
	local function fnProgress(f, text)
		return not dlgProgress or dlgProgress:step(f, text)
	end
	local report_rows = {}

	for _, mark in ipairs(marks) do
		if pov_filter(mark) then
			local defect_code = get_blind_defect_code(mark)
			if defect_code then
				table.insert(report_rows, MakeJointMarkRow(mark, defect_code))
			end
		end
	end

	for group, defect_code, speed_limit in iter_blind_group_defect_code(marks, pov_filter, fnProgress) do
		local row = MakeJointMarkRow(group[1], defect_code)
		row.BLINK_GAP_COUNT = #group
		if speed_limit then
			row.SPEED_LIMIT = speed_limit
		end
		table.insert(report_rows, row)
	end

	report_rows = remove_grouped_marks(report_rows, joints_group_defects, false)
	return report_rows
end

-- -------------------------------------------- --

local function get_joint_step_defect_code(mark)
	local function get_speed_limit(step_vert, temperature)
		if     step_vert > 1 and step_vert <= 2 then	return temperature > 25 and '80' or '50'
		elseif step_vert > 2 and step_vert <= 4 then	return temperature > 25 and '40' or '25'
		elseif step_vert > 4 and step_vert <= 5 then	return '15'
		else                                         	return 'Движение закрывается'
		end
	end

	if mark.prop.Guid == TYPES.RAIL_JOINT_USER and (
		mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_HOR_STEP[1] or
		mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_STEP_VH_LT25[1]) then
			return mark.ext.CODE_EKASUI, ''
	else
		local step_vert = mark_helper.GetRailGapStep(mark) or 0
		step_vert = math.abs(step_vert)
		if step_vert > 1 then
			local temperature = mark_helper.GetTemperature(mark) or 0
			return DEFECT_CODES.JOINT_STEP_VH_LT25[1], get_speed_limit(step_vert, temperature)
		end
	end
end

local function generate_rows_joint_step(marks, dlgProgress, pov_filter)
	local report_rows = {}
	for i, mark in ipairs(marks) do
		if pov_filter(mark) then
			local defect_code, speed_limit = get_joint_step_defect_code(mark)
			if defect_code then
				local row = MakeJointMarkRow(mark, defect_code)
				if speed_limit then
					row.SPEED_LIMIT = speed_limit
				end
				table.insert(report_rows, row)
			end
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local function get_fishplate_defect_code(mark)
	--[[ Дмитрий 14:23
	Закрытие движения при изломе накладки.
	Замечание при трещине одной накладки.
	40 км/ч при трещине двух накладок.
]]
	local eaksui_code = mark.ext.CODE_EKASUI
	if mark.prop.Guid == TYPES.RAIL_JOINT_USER and (
		eaksui_code == DEFECT_CODES.JOINT_FISHPLATE_DEFECT[1] or
		eaksui_code == DEFECT_CODES.JOINT_FISHPLATE_DEFECT_ONE[1] or
		eaksui_code == DEFECT_CODES.JOINT_FISHPLATE_DEFECT_BOTH[1]
	) then
		return eaksui_code, nil
	else
		local fishpalte_fault, fishpalte_fault_cnt = mark_helper.GetFishplateState(mark)
		if fishpalte_fault and fishpalte_fault > 0 then
			local defect_code
			if fishpalte_fault_cnt == 1 then
				defect_code = DEFECT_CODES.JOINT_FISHPLATE_DEFECT_SINGLE[1]
			else
				defect_code = DEFECT_CODES.JOINT_FISHPLATE_DEFECT_BOTH[1]
			end

			local speed_limit
			if fishpalte_fault == 4 then
				speed_limit = 'Движение закрывается'
			elseif fishpalte_fault == 3 then
				if fishpalte_fault_cnt > 1 then
					speed_limit = '40'
				else
					speed_limit = 'Замечание'
				end
			end
			return defect_code, speed_limit
		end
	end
end

local function generate_rows_fishplate(marks, dlgProgress, pov_filter)
	local report_rows = {}
	for i, mark in ipairs(marks) do

--		local fishplate_fault_str = {
--			[0] = 'испр.',
--			[1] = 'надр.',
--			[3] = 'трещ.',
--			[4] = 'изл.',
--		}

		if pov_filter(mark) then
			local defect_code, speed_limit = get_fishplate_defect_code(mark)
			if defect_code then
				local row = MakeJointMarkRow(mark, defect_code)
				if speed_limit then
					row.SPEED_LIMIT = speed_limit
				end
				table.insert(report_rows, row)
			end
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local function bolt2defect_limit(mark)
	local valid_on_half, broken_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
	local join_type = mark_helper.GetGapType(mark) -- АТС - болты - не выводить неисправность по отсутствию болтов https://bt.abisoft.spb.ru/view.php?id=773#c3792
	if broken_on_half and broken_on_half ~= 0 and join_type ~= 2 then
		if valid_on_half == 1 then
			return DEFECT_CODES.JOINT_MISSING_BOLT_ONE_GOOD[1], '25'
		elseif valid_on_half == 0 then
			return DEFECT_CODES.JOINT_MISSING_BOLT_NO_GOOD[1], 'Закрытие движения'
		else
			return DEFECT_CODES.JOINT_MISSING_BOLT_TWO_GOOD[1], ''	-- в столбце 14 вместо ?? нужно ""/пусто/ничего. https://bt.abisoft.spb.ru/view.php?id=867
		end
	end
end

local function generate_rows_missing_bolt(marks, dlgProgress, pov_filter)
	local report_rows = {}
	for i, mark in ipairs(marks) do
		if not pov_filter or pov_filter(mark) then
			if mark.prop.Guid == TYPES.RAIL_JOINT_USER and (
				mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_MISSING_BOLT[1] or
				mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_MISSING_BOLT_NO_GOOD[1] or
				mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_MISSING_BOLT_ONE_GOOD[1] or
				mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_MISSING_BOLT_TWO_GOOD[1]
			)
			then
				local row = MakeJointMarkRow(mark, mark.ext.CODE_EKASUI)
				table.insert(report_rows, row)
			else
				local code, limit = bolt2defect_limit(mark)
				if code then
					local row = MakeJointMarkRow(mark, code)
					row.SPEED_LIMIT = limit
					table.insert(report_rows, row)
				end
			end
		end

		if i % 300 == 0 then collectgarbage("collect") end
		if i % 10 == 0 and dlgProgress and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end
	return report_rows
end

local function generate_rows_WeldedBond(marks, dlgProgress, pov_filter)
	local report_rows = {}
	for i, mark in ipairs(marks) do
		if pov_filter(mark) and mark_helper.table_find(video_joints_juids, mark.prop.Guid) then
			local code = mark_helper.GetWeldedBondDefectCode(mark)
			if code then
				table.insert(report_rows, MakeJointMarkRow(mark, code))
			end
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end
	return report_rows
end

local function generate_rows_user(marks, dlgProgress, pov_filter)
	if #marks == 0 then return end

	local report_rows = {}
	for i, mark in ipairs(marks) do
		if pov_filter(mark) and mark.prop.Guid == TYPES.RAIL_JOINT_USER and mark.ext.CODE_EKASUI then
			local row = make_mark_gap_width_exceed(mark)
			if not row then
				row = MakeJointMarkRow(mark, mark.ext.CODE_EKASUI)
			end
			table.insert(report_rows, row)
		end
		if i % 10 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end
	return report_rows
end

-- вместо функций генераторов, вставляем функции обертки вызывающие генераторы с доп параметрами
local function make_gen_pov_filter(generator, ...)
	local args = {...}
	for i, gen in ipairs(generator) do
		generator[i] = function (marks, dlgProgress)
			return gen(marks, dlgProgress, table.unpack(args))
		end
	end
	return generator
end

-- =============================================================================

local function make_report_generator(...)
	local generators = {...}
	return function()
		local pov_filter = sumPOV.MakeReportFilter(false)
		if not pov_filter then return {} end

		local report_template_name = 'ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ РЕЛЬСОВЫХ СТЫКОВ.xlsm'
		local sheet_name = 'В2 СТК'

		generators = make_gen_pov_filter(generators, pov_filter)
		return AVIS_REPORT.make_report_generator(GetMarks,
			report_template_name, sheet_name, table.unpack(generators))()
	end
end

local function make_report_ekasui(...)
	local generators = {...}
	return function()
		local pov_filter = sumPOV.MakeReportFilter(true)
		if not pov_filter then return {} end
		generators = make_gen_pov_filter(generators, pov_filter)
		return EKASUI_REPORT.make_ekasui_generator(GetMarks, table.unpack(generators))()
	end
end

local function make_report_videogram(...)
	local row_generators = {...}
	local function fake_pov_filter() return true end
	local dlgProgress = nil

	local function gen(mark)
		local report_rows = {}
		if mark and mark_helper.table_find(video_joints_juids, mark.prop.Guid) then
			for _, fn_gen in ipairs(row_generators) do
				local cur_rows = fn_gen({mark}, dlgProgress, fake_pov_filter)
				for _, row in ipairs(cur_rows) do
					table.insert(report_rows, row)
				end
			end
		end
		return report_rows
	end

	return gen
end

-- =============================================================================

local all_generators = {
	generate_rows_user,
	generate_rows_joint_width,
	generate_rows_neigh_blind_joint,
	generate_rows_joint_step,
	generate_rows_fishplate,
	generate_rows_missing_bolt,
	generate_rows_WeldedBond
}

local report_joint_width = make_report_generator(generate_rows_joint_width)
local report_neigh_blind_joint = make_report_generator(generate_rows_neigh_blind_joint)
local report_joint_step = make_report_generator(generate_rows_joint_step)
local report_fishplate = make_report_generator(generate_rows_fishplate)
local report_missing_bolt = make_report_generator(generate_rows_missing_bolt)
local report_WeldedBond = make_report_generator(generate_rows_WeldedBond)
local report_ALL = make_report_generator(
	table.unpack(all_generators)
)

local ekasui_joint_width = make_report_ekasui(generate_rows_joint_width)
local ekasui_neigh_blind_joint = make_report_ekasui(generate_rows_neigh_blind_joint)
local ekasui_joint_step = make_report_ekasui(generate_rows_joint_step)
local ekasui_fishplate = make_report_ekasui(generate_rows_fishplate)
local ekasui_missing_bolt = make_report_ekasui(generate_rows_missing_bolt)
local ekasui_WeldedBond = make_report_ekasui(generate_rows_WeldedBond)
local ekasui_ALL = make_report_ekasui(
	table.unpack(all_generators)
)


local videogram = make_report_videogram(
	table.unpack(all_generators)
)


-- =============================================================================


local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании рельсовых стыков|'

	local sleppers_reports =
	{
		{name = name_pref..'ВСЕ',    																	fn = report_ALL, 				},
		{name = name_pref..'Ширина стыкового зазора, мм',    											fn = report_joint_width, 				},
		{name = name_pref..'Определение двух подряд и более нулевых зазоров',    						fn = report_neigh_blind_joint,			},
		{name = name_pref..'Горизонтальные ступеньки в стыках, мм',    									fn = report_joint_step,					},
		{name = name_pref..'Определение наличия и состояния (надрыв, трещина, излом) накладок',			fn = report_fishplate,					},
		{name = name_pref..'Определение наличия и состояния (ослаблен, раскручен, не типовой) стыковых болтов',		fn = report_missing_bolt,	},
		{name = name_pref..'Определение наличия и состояния приварных рельсовых соединителей',    		fn = report_WeldedBond, 				},

		{name = name_pref..'ЕКАСУИ ВСЕ',																		fn = ekasui_ALL,			},
		{name = name_pref..'ЕКАСУИ Ширина стыкового зазора, мм',    											fn = ekasui_joint_width, 				},
		{name = name_pref..'ЕКАСУИ Определение двух подряд и более нулевых зазоров',    						fn = ekasui_neigh_blind_joint,			},
		{name = name_pref..'ЕКАСУИ  ступеньки в стыках, мм',    												fn = ekasui_joint_step,					},
		{name = name_pref..'ЕКАСУИ Определение наличия и состояния (надрыв, трещина, излом) накладок',			fn = ekasui_fishplate,					},
		{name = name_pref..'ЕКАСУИ Определение наличия и состояния (ослаблен, раскручен, не типовой) стыковых болтов',		fn = ekasui_missing_bolt,	},
		{name = name_pref..'ЕКАСУИ Определение наличия и состояния приварных рельсовых соединителей',    		fn = ekasui_WeldedBond, 				},
	}

	for _, report in ipairs(sleppers_reports) do
		if report.fn then
			report.guids = mark_helper.table_merge(video_joints_juids, joints_group_defects)
			table.insert(reports, report)
		end
	end
end

-- тестирование
if not ATAPE then
	_G.ShowVideo = 0
	local test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml', nil, {0, 100000000})
	--test_report('C:\\Avikon\\CheckAvikonReports\\data\\data_27_short.xml')
    --test_report('D:/ATapeXP/Main/TEST/ZeroGap/2019_06_13/Avikon-03M/6284/[494]_2017_06_14_03.xml')

	-- local report = reports[1]
	-- print(report.name)
	-- report.fn()

	--ekasui_fishplate()
	report_ALL()
end



return {
	AppendReports = AppendReports,
	videogram = videogram,
	all_generators = {
		{generate_rows_user, 				"Установленые пользователем"},
		{generate_rows_joint_width, 		"Ширина стыкового зазора"},
		{generate_rows_neigh_blind_joint, 	"Определение двух подряд и более нулевых зазоров"},
		{generate_rows_joint_step, 			"Горизонтальные ступеньки в стыках"},
		{generate_rows_fishplate, 			"Состояние накладок"},
		{generate_rows_missing_bolt, 		"Состояние стыковых болтов"},
		{generate_rows_WeldedBond,			"Состояние приварных рельсовых соединителей"},
	},
	get_marks = GetMarks,
	bolt2defect_limit = bolt2defect_limit,
	get_mark_gap_width_defect_code = get_mark_gap_width_defect_code,
	get_joint_step_defect_code = get_joint_step_defect_code,
	get_fishplate_defect_code = get_fishplate_defect_code,
	iter_blind_group_defect_code = iter_blind_group_defect_code,
}
