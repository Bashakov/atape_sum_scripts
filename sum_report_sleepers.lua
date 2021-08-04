if not ATAPE then
	require "iuplua"
end

if false then iup = nil; luacom = nil end -- suppress lua diagnostic (undefined global)

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"

local excel_helper = require 'excel_helper'
local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local DEFECT_CODES = require 'report_defect_codes'
local EKASUI_REPORT = require 'sum_report_ekasui'
local AVIS_REPORT = require 'sum_report_avis'
local sumPOV = require "sumPOV"
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


-- ===================================================================


local function check_distance(ref_dist, MEK, max_diff, cur_dist)
	if cur_dist < 200 then
		return true
	end
	for i = 1, MEK do
		if math.abs(cur_dist/i - ref_dist) <= max_diff then
			return true
		end
	end
	return false
end


-- сделать из отметки таблицу и подставновками
local function MakeSleeperMarkRow(mark)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
	local material = mark_helper.GetSleeperMeterial(mark)

	row.SLEEPER_MATERIAL = material and (material == 1 and "ЖБШ" or "ДШ") or ''
	row.SLEEPER_ANGLE = ''
	row.SLEEPER_DIST = ''
	row.SPEED_LIMIT = ''

	return row
end

local function GetMarks()
	local marks = Driver:GetMarks{GUIDS=guigs_sleepers, ListType="list"}
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end

-- ==========================================================================

local function generate_rows_sleeper_dist(marks, dlgProgress, pov_filter)
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

	local ref_dist = 1000000 / sleeper_count

	local material_diffs =
	{
		[1] = 2*40, -- "бетон",
		[2] = 2*80, -- "дерево",
	}

	local report_rows = {}
	local i = 0
	for left, cur, right in mark_helper.enum_group(marks, 3) do
		i = i + 1

		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
		if pov_filter(cur) then

			if cur.prop.Guid == "{3601038C-A561-46BB-8B0F-F896C2130002}" and
			 (cur.ext.CODE_EKASUI == DEFECT_CODES.SLEEPER_DISTANCE_CONCRETE[1] or
			  cur.ext.CODE_EKASUI == DEFECT_CODES.SLEEPER_DISTANCE_WOODEN[1]) then -- установлена пользователем
				local row = MakeSleeperMarkRow(cur)
				row.SLEEPER_DIST = ''

				row.DEFECT_CODE = cur.ext.CODE_EKASUI
				row.DEFECT_DESC = DEFECT_CODES.code2desc(cur.ext.CODE_EKASUI)

				table.insert(report_rows, row)
			else
				local cur_material = mark_helper.GetSleeperMeterial(cur)
				local max_diff = material_diffs[cur_material] or 80

				local dist_prev = cur.prop.SysCoord - left.prop.SysCoord
				local dist_next = right.prop.SysCoord - cur.prop.SysCoord

				local dist_ok = check_distance(ref_dist, MEK, max_diff, dist_next)

				--printf("%s | %9d %3d | %+8.1f\n", dist_ok and '    ' or '!!!!', cur.prop.SysCoord, max_diff,  dist_next-ref_dist)

				if not dist_ok then
					local row = MakeSleeperMarkRow(cur)
					row.SLEEPER_DIST = dist_next

					if cur_material == 1 then -- "бетон",
						row.DEFECT_CODE = DEFECT_CODES.SLEEPER_DISTANCE_CONCRETE[1]
						row.DEFECT_DESC = DEFECT_CODES.SLEEPER_DISTANCE_CONCRETE[2]
					elseif cur_material == 2 then -- "дерево",
						row.DEFECT_CODE = DEFECT_CODES.SLEEPER_DISTANCE_WOODEN[1]
						row.DEFECT_DESC = DEFECT_CODES.SLEEPER_DISTANCE_WOODEN[2]
					end

					table.insert(report_rows, row)
				end
			end
		end
	end

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
				local row = MakeSleeperMarkRow(mark)
				row.SLEEPER_ANGLE = cur_angle
				if material == 1 then -- "бетон"
					row.DEFECT_CODE = DEFECT_CODES.SLEEPER_ANGLE_CONCRETE[1]
				else -- дерево
					row.DEFECT_CODE = DEFECT_CODES.SLEEPER_ANGLE_WOOD[1]
				end
				row.DEFECT_DESC = DEFECT_CODES.code2desc(row.DEFECT_CODE)
				table.insert(report_rows, row)
			end
		end
	end
	return report_rows
end

local function generate_rows_sleeper_user(marks, dlgProgress, pov_filter)
	if #marks == 0 then return end

	local report_rows = {}
	for i, mark in ipairs(marks) do
		if pov_filter(mark) and mark.prop.Guid == "{3601038C-A561-46BB-8B0F-F896C2130002}" and mark.ext.CODE_EKASUI then
			local row = MakeSleeperMarkRow(mark)
			row.DEFECT_CODE = mark.ext.CODE_EKASUI
			row.DEFECT_DESC = DEFECT_CODES.code2desc(mark.ext.CODE_EKASUI) or string.match(mark.prop.Description, '([^\n]+)\n')
			table.insert(report_rows, row)
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local function generate_rows_sleeper_defects(marks, dlgProgress, pov_filter)
	local code2ekasui =
	{
		-- [0] = "undef",
		[1] = DEFECT_CODES.SLEEPER_FRACTURE_FERROCONCRETE, -- "fracture(ferroconcrete)",
		[2] = DEFECT_CODES.SLEEPER_CHIP_FERROCONCRETE, -- "chip(ferroconcrete)",
		[3] = DEFECT_CODES.SLEEPER_CRACK_WOOD,  -- "crack(wood)",
		[4] = DEFECT_CODES.SLEEPER_ROTTENNESS_WOOD, -- "rottenness(wood)",
	}

	if #marks == 0 then return end

	local report_rows = {}
	for i, mark in ipairs(marks) do
		if pov_filter(mark) then
			local params = mark_helper.GetSleeperFault(mark)
			if params and params.FaultType and code2ekasui[params.FaultType] then
				local code = code2ekasui[params.FaultType]
				local row = MakeSleeperMarkRow(mark)
				row.DEFECT_CODE = code[1]
				row.DEFECT_DESC = code[1]
				table.insert(report_rows, row)
			end
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local function report_not_implement()
	iup.Message('Error', "Отчет не реализован")
end

local function sleepers_report_plot()
	local marks = Driver:GetMarks{GUIDS=guigs_sleepers}
	marks = mark_helper.sort_mark_by_coord(marks)

	local excel = luacom.CreateObject("Excel.Application")
	assert(excel, "Error! Could not run EXCEL object!")

	-- excel.visible = true

	local worksheet = nil


	local fn = sprintf("%s\\sleepers_%s.csv", os.getenv("TEMP"), os.date('%y%m%d%H%M%S'))
	local fo = io.open(fn, 'w+')
	local prev = nil
	for i = 1, #marks do
		local mark = marks[i]
		local prop = mark.prop

		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		local path = sprintf('%d km %5.1f m', km, m + mm/1000)

		local angle = mark_helper.GetSleeperAngle(mark) or 0
		--angle = angle * 180/3.14/1000

		local row = {
			i,
			prop.SysCoord,
			path,
			angle,
			prev and prop.SysCoord-prev or 0
		}
		fo:write(table.concat(row, ';') .. '\n')

		prev = prop.SysCoord
	end
	fo:close()

	local workbook = excel.Workbooks:Open(fn)
	worksheet = workbook.Sheets(1)

	excel.visible = true

	local shape = worksheet.Shapes:AddChart2(1, 4, 250, 10, 800, 250)
	local chart = shape.Chart
	chart.ChartTitle.Text = 'Разворот'
    chart:SetSourceData(worksheet:Range("D:D"))
	chart:SeriesCollection(1).XValues = worksheet:Range("C:C")

	shape = worksheet.Shapes:AddChart2(1, 4, 250, 260, 800, 250)
	chart = shape.Chart
	chart.ChartTitle.Text = "Расстояние"
    chart:SetSourceData(worksheet:Range("E:E"))
	chart:SeriesCollection(1).XValues = worksheet:Range("C:C")
    chart:Axes(2).MaximumScale = 1000
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

local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании шпал|'

	local sleppers_reports =
	{
				-- {name = name_pref..'график',		                       					fn=sleepers_report_plot,	},
		{name = name_pref..'ВСЕ',    																fn=report_ALL, 			},
		{name = name_pref..'Отслеживание соблюдения эпюры шпал',    								fn=report_sleeper_dist, 	},
		{name = name_pref..'Перпендикулярность шпалы относительно оси пути, рад',					fn=report_sleeper_angle,	},
		{name = name_pref..'Дефекты',																fn=report_sleeper_defects,	},
		-- {name = name_pref..'*Параметры и размеры дефектов шпал, мостовых и переводных брусьев, мм',	fn=report_not_implement,	},
		-- {name = name_pref..'*Определение кустовой негодности шпал',									fn=report_not_implement,	},
		-- {name = name_pref..'*Фиксация шпал с разворотом относительно своей оси',					fn=report_not_implement,	},
		{name = name_pref..'ЕКАСУИ ВСЕ',    														fn=ekasui_ALL, 			},
		{name = name_pref..'ЕКАСУИ Отслеживание соблюдения эпюры шпал',    							fn=ekasui_sleeper_dist, 	},
		{name = name_pref..'ЕКАСУИ Перпендикулярность шпалы относительно оси пути, рад',			fn=ekasui_sleeper_angle,	},
		{name = name_pref..'ЕКАСУИ Дефекты',														fn=ekasui_sleeper_defects,	},
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids=guigs_sleepers
		table.insert(reports, report)
	end
end


-- тестирование
if not ATAPE then
	local test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml', nil, {0, 1000000})

	ekasui_sleeper_defects()
	-- report_ALL()
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
}
