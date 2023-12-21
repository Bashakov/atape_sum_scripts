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
local TYPES = require 'sum_types'

local ballast_guids =
{
	TYPES.BALLAST_USER,
}



-- =========================================

local function GetMarks()
   local marks = Driver:GetMarks{GUIDS=ballast_guids}
   marks = mark_helper.sort_mark_by_coord(marks)
   return marks
end

-- сделать из отметки таблицу и подстановками
local function MakeBallastMarkRow(mark, defect_code)
	local row = mark_helper.MakeCommonMarkTemplate(mark)

    if defect_code then
		row.DEFECT_CODE = defect_code
	end
	row.DEFECT_DESC = DEFECT_CODES.code2desc(defect_code)
	return row
end

-- =========================================

local function generate_rows_user(marks, dlgProgress, pov_filter)
	if #marks == 0 then return end

	local report_rows = {}
	for i, mark in ipairs(marks) do
		if pov_filter(mark) and mark.prop.Guid == TYPES.BALLAST_USER and mark.ext.CODE_EKASUI then
			local row = MakeBallastMarkRow(mark, mark.ext.CODE_EKASUI)
			table.insert(report_rows, row)
		end

		if i % 31 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

-- =========================================

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

local function make_report_ekasui(...)
	local generators = {...}
	return function()
		local pov_filter = sumPOV.MakeReportFilter(true)
		if not pov_filter then return {} end
		generators = make_gen_pov_filter(generators, pov_filter)
		return EKASUI_REPORT.make_ekasui_generator(GetMarks, table.unpack(generators))()
	end
end

local ekasui_user = make_report_ekasui(generate_rows_user)


local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании балласта|'

	local ballast_reports =
	{
		{name = name_pref..'ЕКАСУИ пользователь', fn=ekasui_user},
    }

    for _, report in ipairs(ballast_reports) do
		if report.fn then
			report.guids = ballast_guids
			table.insert(reports, report)
		end
	end
end

-- =========================================

-- тестирование
if not ATAPE then
	_G.ShowVideo = 0
	local test_report  = require('local_data_driver')
	test_report.Driver('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml', nil, {0, 1000000})
	--test_report('C:\\Avikon\\CheckAvikonReports\\data\\data_27_short.xml')
    --test_report('D:/ATapeXP/Main/TEST/ZeroGap/2019_06_13/Avikon-03M/6284/[494]_2017_06_14_03.xml')

	ekasui_user()
	--report_ALL()
end

return {
	AppendReports = AppendReports,
}