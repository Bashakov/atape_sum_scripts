if not ATAPE then
	require "iuplua" 
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"

local OOP = require 'OOP'
local stuff = require 'stuff'
local excel_helper = require 'excel_helper'
local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local DEFECT_CODES = require 'report_defect_codes'

local printf = stuff.printf
local sprintf = stuff.sprintf



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

local function SaveAndShow(report_rows, dlgProgress)
	if #report_rows == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end
	
	if #report_rows > 1000 then
		local msg = sprintf('Найдено %d отметок, построение отчета может занять большое время, продолжить?', #report_rows)
		local cont = iup.Alarm("Warning", msg, "Yes", "No")
		if cont == 2 then
			return
		end
	end
	
	local template_path = Driver:GetAppPath() .. 'Scripts/ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ БЕССТЫКОВОГО ПУТИ.xlsm'
	local ext_psp = mark_helper.GetExtPassport(Passport)
	local excel = excel_helper(template_path, "В6 БП", false)
	excel:ApplyPassportValues(ext_psp)
	excel:ApplyRows(report_rows, nil, dlgProgress)
	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)
	excel:SaveAndShow()
end


local function MakeBeaconMarkRow(mark)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
	return row
end

-- ========================================================================= 

local function report_beacon()
	local dlgProgress = luaiup_helper.ProgressDlg()
	local marks = GetMarks()
	
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
	
	SaveAndShow(report_rows, dlgProgress)
end

local function report_not_implement()
	iup.Message('Error', "Отчет не реализован")
end

-- ========================================================================= 

local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании бесстыкового пути|'
	
	local sleppers_reports = 
	{
		{name = name_pref..'Смещения рельсовых плетей относительно «маячных» шпал, мм',    		fn=report_beacon, 			},
		{name = name_pref..'*Определение наличия отсутствующих и неработающих противоугонов',   fn=report_not_implement, 	},
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids=guigs_sleepers
		table.insert(reports, report)
	end
end

-- тестирование
if not ATAPE then
	test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	
	report_beacon()
end

return {
	AppendReports = AppendReports,
}