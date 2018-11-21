if not ATAPE then
	require "iuplua" 
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"


local excel_helper = require 'excel_helper'
local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local DEFECT_CODES = require 'report_defect_codes'


function printf(s,...)  print(s:format(...)) end
function sprintf(s,...) return s:format(...) end


local video_joints_juids = 
{
	"{CBD41D28-9308-4FEC-A330-35EAED9FC801}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC802}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC803}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC804}",
}

-- ============================================================================= 

local template_name = 'ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ РЕЛЬСОВЫХ СТЫКОВ.xlsm'


local function report_WeldedBond()
	local template_path = Driver:GetAppPath() .. 'Scripts/' .. template_name
	
	local marks = Driver:GetMarks{GUIDS=video_joints_juids}
	marks = mark_helper.sort_mark_by_coord(marks)
	
	local dlgProgress = luaiup_helper.ProgressDlg()
	
	local report_rows = {}
	for i, mark in ipairs(marks) do
		
		local status = mark_helper.GetWeldedBondStatus(mark)
		if status == 1 then  -- <PARAM name='ConnectorFault' value='1' value_='0-исправен, 1-неисправен'/>
			local row = mark_helper.MakeCommonMarkTemplate(mark)
			row.DEFECT_CODE = DEFECT_CODES.JOINT_WELDED_BOND_FAULT
			table.insert(report_rows, row)
		end
		
		if i % 10 == 0 and not dlgProgress:step(i / #marks, stuff.sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then 
			return
		end
	end
	
	if #report_rows == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end
	
	if #report_rows > 1000 then
		local msg = sprintf('Найдено %d проблемных стыков, построение отчета может занять большое время, продолжить?', #report_rows)
		local cont = iup.Alarm("Warning", msg, "Yes", "No")
		if cont == 2 then
			return
		end
	end
	
	local ext_psp = mark_helper.GetExtPassport(Passport)
	
	local excel = excel_helper(template_path, "В2 СТК", false)
	excel:ApplyPassportValues(ext_psp)
	excel:ApplyRows(report_rows, nil, dlgProgress)
	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)
	excel:SaveAndShow()
end	


local function report_joint_width()
	local template_path = Driver:GetAppPath() .. 'Scripts/' .. template_name
	
	local marks = Driver:GetMarks{GUIDS=video_joints_juids}
	marks = mark_helper.sort_mark_by_coord(marks)
	
	local dlgProgress = luaiup_helper.ProgressDlg()
	
	local report_rows = {}
	for i, mark in ipairs(marks) do
		local gap_width = mark_helper.GetGapWidth(mark)
		if gap_width and gap_width > 24 then
			local row = mark_helper.MakeCommonMarkTemplate(mark)
			row.DEFECT_CODE = DEFECT_CODES.JOINT_EXCEED_GAP_WIDTH
			row.GAP_WIDTH = gap_width
			
			if     gap_width <= 26 then 					row.SPEED_LIMIT = '100'
			elseif gap_width > 26 and gap_width <=30 then	row.SPEED_LIMIT = '60'
			elseif gap_width > 30 and gap_width <=35 then	row.SPEED_LIMIT = '25'
			else											row.SPEED_LIMIT = 'Движение закрывается'
			end
			
			table.insert(report_rows, row)
		end
		
		if i % 10 == 0 and not dlgProgress:step(i / #marks, stuff.sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then 
			return
		end
	end
	
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
	
	local ext_psp = mark_helper.GetExtPassport(Passport)
	
	local excel = excel_helper(template_path, "В2 СТК", false)
	excel:ApplyPassportValues(ext_psp)
	excel:ApplyRows(report_rows, nil, dlgProgress)
	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)
	excel:SaveAndShow()

end	

-- ============================================================================= 



local function AppendReports(reports)
	local sleppers_reports = 
	{
		{name = 'Ведомость отступлений в содержании рельсовых стыков|Определение наличия и состояния приварных рельсовых соединителей',    	fn = report_WeldedBond, 		guids = video_joints_juids},
		{name = 'Ведомость отступлений в содержании рельсовых стыков|Ширина стыкового зазора, мм',    										fn = report_joint_width, 		guids = video_joints_juids},
	}

	for _, report in ipairs(sleppers_reports) do
		table.insert(reports, report)
	end
end


return {
	AppendReports = AppendReports,
}