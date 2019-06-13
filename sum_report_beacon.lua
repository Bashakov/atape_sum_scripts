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

local printf = mark_helper.printf
local sprintf = mark_helper.sprintf



local juids_beacon = 
{
	"{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}",	-- Маячная
	"{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}", 	-- Маячная(Пользователь)
}


local function GetMarks()
	local marks = Driver:GetMarks{GUIDS=video_joints_juids}
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end

local function MakeBeaconMarkRow(mark)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
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
		local offset = mark_helper.GetBeaconOffset(mark)
		
		if offset and math.abs(offset) > max_offset then
			local row = MakeBeaconMarkRow(mark)
			row.BEACON_OFFSET = offset
			row.OUT_PARAM = offset
			
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
	
	return AVIS_REPORT.make_report_generator(GetMarks, 
		report_template_name, sheet_name, ...)
end

local function make_report_ekasui(...)
	return EKASUI_REPORT.make_ekasui_generator(GetMarks, ...)
end	

-- ============================================================================= 

local report_beacon = make_report_generator(generate_row_beacon)
local ekasui_beacon = make_report_ekasui(generate_row_beacon)

-- ========================================================================= 

local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании бесстыкового пути|'
	
	local sleppers_reports = 
	{
		{name = name_pref..'Смещения рельсовых плетей относительно «маячных» шпал, мм',    		fn=report_beacon, 			},
		{name = name_pref..'*Определение наличия отсутствующих и неработающих противоугонов',   fn=report_not_implement, 	},
		
		{name = name_pref..'ЕКАСУИ Смещения рельсовых плетей относительно «маячных» шпал, мм',  fn=ekasui_beacon, 			},
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids=juids_beacon
		table.insert(reports, report)
	end
end

-- тестирование
if not ATAPE then
	test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	
	report_beacon()
	--ekasui_beacon()
end

return {
	AppendReports = AppendReports,
}