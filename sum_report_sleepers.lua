if not ATAPE then
	require "iuplua"
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"

local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local DEFECT_CODES = require 'report_defect_codes'
local EKASUI_REPORT = require 'sum_report_ekasui'
local AVIS_REPORT = require 'sum_report_avis'
local sumPOV = require "sumPOV"
local EKASUI = require "sum_report_ekasui"
local remove_grouped_marks = require "sum_report_group_scanner"
require 'ExitScope'

local printf = mark_helper.printf
local sprintf = mark_helper.sprintf

local guigs_sleepers =
{
	"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}",	-- Шпалы
	"{3601038C-A561-46BB-8B0F-F896C2130002}",	-- Шпалы(Пользователь)
	"{53987511-8176-470D-BE43-A39C1B6D12A3}",   -- SleeperTop
	"{1DEFC4BD-FDBB-4AC7-9008-BEEB56048131}",   -- SleeperDefect
}

local guigs_sleepers_group =
{
	"{B6BAB49E-4CEC-4401-A106-355BFB2E0011}",   -- GROUP_SPR_AUTO
	"{B6BAB49E-4CEC-4401-A106-355BFB2E0012}",   -- GROUP_SPR_USER
}


-- ===================================================================

local SLEEPER_MATERIAL_TBL =
{
	[1] = "ЖБШ",
	[2] = "ДШ",
}

-- сделать из отметки таблицу и подставновками
local function MakeSleeperMarkRow(mark, defect_code)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
	local material = mark_helper.GetSleeperMeterial(mark)

	row.SLEEPER_MATERIAL = material and SLEEPER_MATERIAL_TBL[material] or ''
	row.SLEEPER_ANGLE = ''
	row.SLEEPER_DIST = ''
	row.SPEED_LIMIT = ''

	if defect_code then
		row.DEFECT_CODE = defect_code
	end
	
	row.DEFECT_DESC = DEFECT_CODES.code2desc(defect_code) or string.match(mark.prop.Description, '([^\n]+)\n')

	return row
end

local function GetMarks()
	local guids = mark_helper.table_merge(guigs_sleepers, guigs_sleepers_group)
	local marks = Driver:GetMarks{GUIDS=guids, ListType="list"}
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end

local function add_node(parent, name, attrib)
	local dom = parent.ownerDocument or parent
	local node = dom:createElement(name)
	parent:appendChild(node)
	for n, v in pairs(attrib or {}) do
		node:setAttribute(n, v)
	end
	return node
end

-- ==========================================================================

local function generate_rows_sleeper_dist(marks, dlgProgress, pov_filter)
	local dist_defect_codes =
	{
		DEFECT_CODES.SLEEPER_DISTANCE_CONCRETE[1],
		DEFECT_CODES.SLEEPER_DISTANCE_WOODEN[1],
	}

	if #marks == 1 and marks[1].user and marks[1].user.dist_prev and marks[1].user.dist_next then
		-- вызов видеограммы из панели отметок, добавим файковые отметки по карям, чтобы алгоритм отработал поис
		local cm = marks[1]
		local pm = {prop={SysCoord=cm.prop.SysCoord - cm.user.dist_prev}}
		local nm = {prop={SysCoord=cm.prop.SysCoord + cm.user.dist_next}}
		marks = {pm, marks[1], nm}
	end

	if #marks  < 3 then
		return
	end

	local ok, sleeper_count, MEK = true, 1840, 4
	if true then -- показывать ли диалог
		ok, sleeper_count, MEK  = iup.GetParam("Отчет оп шпалам", nil,
			"Эпюра шпал: %i\n\z
			МКЭ: %i\n",
			sleeper_count, MEK)
	end
	if not ok then
		return
	end

	local report_rows = {}
	local i = 0

	local user_and_groups = mark_helper.table_merge({"{3601038C-A561-46BB-8B0F-F896C2130002}"}, guigs_sleepers_group)

	for _, cur, right in mark_helper.enum_group(marks, 3) do
		i = i + 1

		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
		if pov_filter(cur) then
			if mark_helper.table_find(user_and_groups, cur.prop.Guid) and
			   mark_helper.table_find(dist_defect_codes, cur.ext.CODE_EKASUI) then
				-- установлена пользователем или групповая
				local row = MakeSleeperMarkRow(cur, cur.ext.CODE_EKASUI)
				table.insert(report_rows, row)
			else
				local dist_next = right.prop.SysCoord - cur.prop.SysCoord
				local dist_ok, defect_code = mark_helper.CheckSleeperEpure(cur, sleeper_count, MEK, dist_next)

				--printf("%s | %9d %3d | %+8.1f\n", dist_ok and '    ' or '!!!!', cur.prop.SysCoord, max_diff,  dist_next-ref_dist)

				if not dist_ok then
					local row = MakeSleeperMarkRow(cur, defect_code)
					row.SLEEPER_DIST = dist_next
					table.insert(report_rows, row)
				end
			end
		end
	end

	report_rows = remove_grouped_marks(report_rows, guigs_sleepers_group, true)
	return report_rows
end


local function generate_rows_sleeper_angle(marks, dlgProgress, pov_filter)

	local ok, angle_threshold = true, 5.7
	ok, angle_threshold  = iup.GetParam("Отчет оп шпалам", nil, "Разворот: %r\n", angle_threshold)
	if not ok then
		return
	end

	local report_rows = {}

	for i, mark in ipairs(marks) do
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end

		if pov_filter(mark) then
			local cur_angle = mark_helper.GetSleeperAngle(mark) or 0
			cur_angle = cur_angle * 180/3.14/1000

			if math.abs(cur_angle) > angle_threshold then
				local material = mark_helper.GetSleeperMeterial(mark)

				-- printf("%9d  %+8.1f\n", mark.prop.SysCoord, cur_angle)
				local defect_code
				if material == 1 then -- "бетон"
					defect_code = DEFECT_CODES.SLEEPER_ANGLE_CONCRETE[1]
				else -- дерево
					defect_code = DEFECT_CODES.SLEEPER_ANGLE_WOOD[1]
				end

				local row = MakeSleeperMarkRow(mark, defect_code)
				row.SLEEPER_ANGLE = cur_angle
				table.insert(report_rows, row)
			end
		end
	end
	report_rows = remove_grouped_marks(report_rows, guigs_sleepers_group, true)
	return report_rows
end

local function generate_rows_sleeper_user(marks, dlgProgress, pov_filter)
	if #marks == 0 then return end

	local report_rows = {}
	for i, mark in ipairs(marks) do
		if pov_filter(mark) and mark.prop.Guid == "{3601038C-A561-46BB-8B0F-F896C2130002}" and mark.ext.CODE_EKASUI then
			local row = MakeSleeperMarkRow(mark, mark.ext.CODE_EKASUI)
			table.insert(report_rows, row)
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local defectcode2ekasui =
{
	-- [0] = "undef",
	[1] = DEFECT_CODES.SLEEPER_FRACTURE_FERROCONCRETE[1], 	-- "fracture(ferroconcrete)",
	[2] = DEFECT_CODES.SLEEPER_CHIP_FERROCONCRETE[1], 		-- "chip(ferroconcrete)",
	[3] = DEFECT_CODES.SLEEPER_CRACK_WOOD[1],  				-- "crack(wood)",
	[4] = DEFECT_CODES.SLEEPER_ROTTENNESS_WOOD[1], 			-- "rottenness(wood)",
}


local function generate_rows_sleeper_defects(marks, dlgProgress, pov_filter)


	if #marks == 0 then return end

	local report_rows = {}
	for i, mark in ipairs(marks) do
		if pov_filter(mark) then
			local params = mark_helper.GetSleeperFault(mark)
			if params and params.FaultType and defectcode2ekasui[params.FaultType] then
				local row = MakeSleeperMarkRow(mark, defectcode2ekasui[params.FaultType])
				table.insert(report_rows, row)
			end
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	report_rows = remove_grouped_marks(report_rows, guigs_sleepers_group, true)
	return report_rows
end

local function sleeper_SDMI()
	EnterScope(function(defer)
		local fromKM = Passport.FromKm or string.match(Passport.START_CHOORD, '^(-?%d+):') or ''
		local toKM = Passport.ToKm or string.match(Passport.END_CHOORD, '^(-?%d+):') or ''

		local proezd_params = EKASUI.AskEkasuiParam()
		if not proezd_params then return end

		local dlg = luaiup_helper.ProgressDlg('Отчет ЕКАСУИ')
		defer(dlg.Destroy, dlg)

		local marks = GetMarks()
		local dom = luacom.CreateObject('Msxml2.DOMDocument.6.0')
		assert(dom)

		local node_sleepers = add_node(dom, 'sleepers')
		local node_proezd = add_node(node_sleepers, 'proezd', {
			proezd=proezd_params.proezd,
			proverka=proezd_params.proverka,
			road=proezd_params.road,
			vagon=proezd_params.vagon,
			assetnum=proezd_params.assetnum,
			km_begin=fromKM,
			m_begin="0",
			km_end=toKM,
			m_end="0",
		})
		local node_floors = add_node(node_proezd, 'floors')
		for i, mark in ipairs(marks) do
			local center = mark.prop.SysCoord + mark.prop.Len / 2
			center = mark_helper.round(center, 0)
			local km, m, mm = Driver:GetPathCoord(center)

			local node_floor = add_node(node_floors, 'floor', {km=km, m=m, sm=mark_helper.round(mm / 10, 0), syskoor=center})
			if i%100 == 0 and not dlg:step(i / #marks, sprintf('Сохранение шпал %d / %d', i, #marks)) then
				return
			end
		end

		local path_dst = sprintf("%s\\sdmisleep_%s_%s.xml", EKASUI_PARAMS.ExportFolder, Passport.SOURCE, proezd_params.proezd)
		local f = io.open(path_dst, 'w+b')
		f:write(mark_helper.msxml_node_to_string(node_sleepers.ownerDocument))
		f:close()

		local anwser = iup.Alarm("ATape", sprintf("Сохранен файл: %s", path_dst), "Показать", "Закрыть")
		if 1 == anwser then
			os.execute(path_dst)
		end
	end)
end

-- =============================================================================

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

local function make_report_generator(...)
	local generators = {...}
	return function()
		local pov_filter = sumPOV.MakeReportFilter(false)
		if not pov_filter then return {} end

		local report_template_name = 'ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ ШПАЛ.xlsm'
		local sheet_name = 'В3 ШП'

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

	local function gen(mark)
		local report_rows = {}
		if mark and mark_helper.table_find(guigs_sleepers, mark.prop.Guid) then
			for _, fn_gen in ipairs(row_generators) do
				local cur_rows = fn_gen({mark}, nil)
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

local report_sleeper_dist = make_report_generator(generate_rows_sleeper_dist)
local report_sleeper_angle = make_report_generator(generate_rows_sleeper_angle)
local report_sleeper_defects = make_report_generator(generate_rows_sleeper_defects)
local report_ALL = make_report_generator(
	generate_rows_sleeper_dist,
	generate_rows_sleeper_angle,
	generate_rows_sleeper_user,
	generate_rows_sleeper_defects
)

local ekasui_sleeper_dist = make_report_ekasui(generate_rows_sleeper_dist)
local ekasui_sleeper_angle = make_report_ekasui(generate_rows_sleeper_angle)
local ekasui_sleeper_defects = make_report_ekasui(generate_rows_sleeper_defects)
local ekasui_ALL = make_report_ekasui(
	generate_rows_sleeper_dist,
	generate_rows_sleeper_angle,
	generate_rows_sleeper_user,
	generate_rows_sleeper_defects
)

local videogram = make_report_videogram(
	generate_rows_sleeper_dist,
	generate_rows_sleeper_angle
)

-- =============================================================================

local function PrepareSleepers()
	return EnterScope(function (defer)
		local dlg = luaiup_helper.ProgressDlg('Обработка шпал')
        defer(dlg.Destroy, dlg)
		local gg = {
			"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}",	-- Шпалы
		}

		local sleeper_count, MEK = 1840, 4
		local angle_threshold = 5.7
		local marks_to_save = {}

		local marks = Driver:GetMarks{GUIDS=gg, ListType="all"}
		marks = mark_helper.sort_mark_by_coord(marks)
		local i = 0
		for cur, right in mark_helper.enum_group(marks, 2) do
			i = i + 1
			if i % 43 == 0 and not dlg:step(i / #marks, sprintf('Обработка %d / %d', i, #marks)) then
				return
			end
			--if i > 1000 then break end
			local mark_defects = {}

			-- сохраним материал
			local material = mark_helper.GetSleeperMeterial(cur)
			if not material and SHOW_SLEEPER_UNKNOWN_MATERIAL then
				material = 1 -- https://bt.abisoft.spb.ru/view.php?id=863#c4393 В случае "не скрывать" - считать все шнапля ЖБ 
			end
			cur.ext.SLEEPERS_METERIAL = material

			-- сохраним эпюру
			local dist_next = right.prop.SysCoord - cur.prop.SysCoord
			cur.ext.SLEEPERS_NEXT = dist_next

			local disk_ok, defect_code = mark_helper.CheckSleeperEpure(cur, sleeper_count, MEK, dist_next)
			if not disk_ok and defect_code ~= '' then
				table.insert(mark_defects, defect_code)
			end

			-- сохраним разворот
			local angle = mark_helper.GetSleeperAngle(cur)
			if not angle then
				angle = 0
			end
			cur.ext.SLEEPERS_ANGLE = angle
			angle = angle * 180/3.14/1000

			if math.abs(angle) > angle_threshold then
				if material == 1 then -- "бетон"
					table.insert(mark_defects, DEFECT_CODES.SLEEPER_ANGLE_CONCRETE[1])
				else -- дерево
					table.insert(mark_defects, DEFECT_CODES.SLEEPER_ANGLE_WOOD[1])
				end
			end

			-- дефектность
			local params_fault = mark_helper.GetSleeperFault(cur)
			if params_fault and params_fault.FaultType and defectcode2ekasui[params_fault.FaultType] then
				table.insert(mark_defects, defectcode2ekasui[params_fault.FaultType])
			end

			-- запишем все найденные коды дефектов в отметку
			if #mark_defects > 0 then
				mark_defects = table.concat(mark_defects, ",")
				cur.ext.DEFECT_CODES = mark_defects
			end
			table.insert(marks_to_save, cur);

			print(cur.prop.ID, cur.prop.SysCoord, cur.ext.SLEEPERS_NEXT, cur.ext.SLEEPERS_ANGLE, cur.ext.DEFECT_CODES)
			if #marks_to_save > 1000 then
				Driver:SaveMarks(marks_to_save)
				marks_to_save = {}
			end
		end

		if #marks_to_save > 0 then
			Driver:SaveMarks(marks_to_save)
		end
	end);
end

local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании шпал|'

	local sleppers_reports =
	{
				-- {name = name_pref..'график',		                       					fn=sleepers_report_plot,	},
		{name = name_pref..'ВСЕ',    																fn=report_ALL, 			},
		{name = name_pref..'Отслеживание соблюдения эпюры шпал',    								fn=report_sleeper_dist, 	},
		{name = name_pref..'Перпендикулярность шпалы относительно оси пути, рад',					fn=report_sleeper_angle,	},
		{name = name_pref..'Дефекты',																fn=report_sleeper_defects,	},
		{name = name_pref..'ЕКАСУИ ВСЕ',    														fn=ekasui_ALL, 			},
		{name = name_pref..'ЕКАСУИ Отслеживание соблюдения эпюры шпал',    							fn=ekasui_sleeper_dist, 	},
		{name = name_pref..'ЕКАСУИ Перпендикулярность шпалы относительно оси пути, рад',			fn=ekasui_sleeper_angle,	},
		{name = name_pref..'ЕКАСУИ Дефекты',														fn=ekasui_sleeper_defects,	},

		{name = name_pref..'шпалы для СДМИ',														fn=sleeper_SDMI,	},	-- https://bt.abisoft.spb.ru/view.php?id=793
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids=guigs_sleepers
		table.insert(reports, report)
	end
end


-- тестирование
if not ATAPE then
	local test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml', nil, {395000, 405000})

	-- report_sleeper_dist()
	--ekasui_sleeper_defects()
	--report_sleeper_defects()

	--ekasui_sleeper_dist()
	-- sleeper_SDMI()
	-- report_ALL()
	PrepareSleepers()
end

return {
	AppendReports = AppendReports,
	videogram = videogram,
	all_generators = {
		{generate_rows_sleeper_dist, 	"Соблюдения эпюры шпал"},
		{generate_rows_sleeper_angle, 	"Перпендикулярность шпалы"},
		{generate_rows_sleeper_user, 	"Установленые пользователем"},
		{generate_rows_sleeper_defects, "Дефекты"}
	},
	get_marks = function (pov_filter)
		return GetMarks()
	end,
	PrepareSleepers = PrepareSleepers
}
