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

local printf = mark_helper.printf
local sprintf = mark_helper.sprintf



local juids_beacon =
{
	"{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}",	-- Маячная
	"{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}", 	-- Маячная(Пользователь)
	"{3601038C-A561-46BB-8B0F-F896C2130006}",	-- Бесстыковой путь(Пользователь)
}


local function GetMarks(ekasui)
	local pov_filter = sumPOV.MakeReportFilter(ekasui)
	if not pov_filter then return {} end
	local marks = Driver:GetMarks{GUIDS=juids_beacon}
	marks = pov_filter(marks)
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end

local function MakeBeaconMarkRow(mark)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
	row.BEACON_OFFSET = ''
	row.OUT_PARAM = ''
	return row
end

-- =========================================================================

local function generate_row_beacon(marks, dlgProgress)

	local ok, max_offset = true, 10
	ok, max_offset  = iup.GetParam("Отчет по маячным отметкам", nil, "Смещение: %i\n", max_offset)
	if not ok then
		return
	end

	local report_rows = {}
	for i, mark in ipairs(marks) do
		if mark.prop.Guid == "{3601038C-A561-46BB-8B0F-F896C2130006}" and mark.ext.CODE_EKASUI == DEFECT_CODES.BEACON_UBNORMAL_MOVED[1] then
			local row = MakeBeaconMarkRow(mark)
			row.DEFECT_CODE = mark.ext.CODE_EKASUI
			row.DEFECT_DESC = DEFECT_CODES.code2desc(mark.ext.CODE_EKASUI) or string.match(mark.prop.Description, '([^\n]+)\n')
			table.insert(report_rows, row)
		else
			local offset = mark_helper.GetBeaconOffset(mark)

			if offset and math.abs(offset) > max_offset then
				local row = MakeBeaconMarkRow(mark)
				row.BEACON_OFFSET = offset
				row.OUT_PARAM = offset
				row.DEFECT_CODE = DEFECT_CODES.BEACON_UBNORMAL_MOVED[1]
				row.DEFECT_DESC = DEFECT_CODES.BEACON_UBNORMAL_MOVED[2]
				table.insert(report_rows, row)
			end
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local function generate_row_beacon_user(marks, dlgProgress)

	local report_rows = {}
	for i, mark in ipairs(marks) do
		if mark.prop.Guid == "{3601038C-A561-46BB-8B0F-F896C2130006}" and mark.ext.CODE_EKASUI then
			local row = MakeBeaconMarkRow(mark)
			row.DEFECT_CODE = mark.ext.CODE_EKASUI
			row.DEFECT_DESC = DEFECT_CODES.code2desc(mark.ext.CODE_EKASUI) or string.match(mark.prop.Description, '([^\n]+)\n')
			table.insert(report_rows, row)
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local function report_not_implement()
	iup.Message('Error', "Отчет не реализован")
end

-- =========================================================================

local function make_report_generator(...)

	local report_template_name = 'ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ БЕССТЫКОВОГО ПУТИ.xlsm'
	local sheet_name = 'В6 БП'

	return AVIS_REPORT.make_report_generator(function() return GetMarks(false) end,
		report_template_name, sheet_name, ...)
end

local function make_report_ekasui(...)
	return EKASUI_REPORT.make_ekasui_generator(function() return GetMarks(true) end, ...)
end

local function make_report_videogram(...)
	local row_generators = {...}

	local function gen(mark)
		local report_rows = {}
		if mark and mark_helper.table_find(juids_beacon, mark.prop.Guid) then
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

local report_beacon = make_report_generator(generate_row_beacon)
local ekasui_beacon = make_report_ekasui(generate_row_beacon)
local videogram = make_report_videogram(generate_row_beacon)

local report_beacon_user = make_report_generator(generate_row_beacon_user)
local ekasui_beacon_user = make_report_ekasui(generate_row_beacon_user)

-- =========================================================================

local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании бесстыкового пути|'

	local sleppers_reports =
	{
		{name = name_pref..'Смещения рельсовых плетей относительно «маячных» шпал, мм',    		fn=report_beacon, 			},
		{name = name_pref..'*Определение наличия отсутствующих и неработающих противоугонов',   fn=report_not_implement, 	},

		{name = name_pref..'ЕКАСУИ Смещения рельсовых плетей относительно «маячных» шпал, мм',  fn=ekasui_beacon, 			},

		{name = name_pref..'Пользовательские',    				fn=report_beacon_user, },
		{name = name_pref..'ЕКАСУИ Пользовательские',    		fn=ekasui_beacon_user, },
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids=juids_beacon
		table.insert(reports, report)
	end
end

-- тестирование
if not ATAPE then
	local test_report  = require('test_report')
	--test_report('D:\\ATapeXP\\Main\\494\\Москва Курская - Подольск\\Москва Курская - Подольск\\2019_05_16\\Avikon-03M\\4240\\[494]_2019_03_15_01.xml')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')

	-- report_beacon_user()
	ekasui_beacon_user()
	-- report_beacon()
	--ekasui_beacon()
end

return {
	AppendReports = AppendReports,
	videogram = videogram,
}
