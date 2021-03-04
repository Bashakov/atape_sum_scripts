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
local sumPOV = require "sumPOV"
require 'ExitScope'

local printf = mark_helper.printf
local sprintf = mark_helper.sprintf

local guigs_sleepers =
{
	"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}",	-- Шпалы
	"{3601038C-A561-46BB-8B0F-F896C2130002}",	-- Шпалы(Пользователь)
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
	local marks = Driver:GetMarks{GUIDS=guigs_sleepers}
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end

local function SaveAndShow(report_rows, dlgProgress)
	local template_path = Driver:GetAppPath() .. 'Scripts/ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ ШПАЛ.xlsm'

	if #report_rows == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end

	if #report_rows > 1000 then
		local msg = sprintf('Найдено %d проблемных шпал, построение отчета может занять большое время, продолжить?', #report_rows)
		local cont = iup.Alarm("Warning", msg, "Yes", "No")
		if cont == 2 then
			return
		end
	end

	local ext_psp = mark_helper.GetExtPassport(Passport)

	local excel = excel_helper(template_path, "В3 ШП", false)
	excel:ApplyPassportValues(ext_psp)
	excel:ApplyRows(report_rows, nil, dlgProgress)
	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)
	excel:SaveAndShow()
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
				-- printf("%9d  %+8.1f\n", mark.prop.SysCoord, cur_angle)
				local row = MakeSleeperMarkRow(mark)
				row.SLEEPER_ANGLE = cur_angle
				row.DEFECT_CODE = DEFECT_CODES.SLEEPER_ANGLE[1]
				row.DEFECT_DESC = DEFECT_CODES.SLEEPER_ANGLE[2]
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

local function make_report_generator(...)
	local row_generators = {...}


	local function gen()
		EnterScope(function (defer)
			local pov_filter = sumPOV.MakeReportFilter(false)
			if not pov_filter then return {} end

			local marks = GetMarks()
			local dlgProgress = luaiup_helper.ProgressDlg()
			defer(dlgProgress.Destroy, dlgProgress)

			local mark_ids = {}
			local report_rows = {}
			for _, fn_gen in ipairs(row_generators) do
				local cur_rows = fn_gen(marks, dlgProgress, pov_filter)
				if not cur_rows then
					break
				end
				for _, row in ipairs(cur_rows) do
					if not mark_ids[row.mark_id] then
						mark_ids[row.mark_id] = true
						table.insert(report_rows, row)
					end
				end
			end

			report_rows = mark_helper.sort_stable(report_rows, function(row)
				return row.SYS
			end)
			SaveAndShow(report_rows, dlgProgress)
		end)
	end

	return gen
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

local report_ALL = make_report_generator(
	generate_rows_sleeper_dist,
	generate_rows_sleeper_angle,
	generate_rows_sleeper_user
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
		{name = name_pref..'*Параметры и размеры дефектов шпал, мостовых и переводных брусьев, мм',	fn=report_not_implement,	},
		{name = name_pref..'*Определение кустовой негодности шпал',									fn=report_not_implement,	},
		{name = name_pref..'*Фиксация шпал с разворотом относительно своей оси',					fn=report_not_implement,	},
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids=guigs_sleepers
		table.insert(reports, report)
	end
end


-- тестирование
if not ATAPE then
	local test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')

	report_ALL()
end

return {
	AppendReports = AppendReports,
	videogram = videogram,
	all_generators = {
		generate_rows_sleeper_dist,
		generate_rows_sleeper_angle,
		generate_rows_sleeper_user
	},
	get_marks = function (pov_filter)
		return GetMarks()
	end,
}
