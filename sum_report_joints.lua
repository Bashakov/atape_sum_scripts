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

local function make_result_row(mark)
	local row = mark_helper.MakeCommonMarkTemaple(mark)
	row.DEFECT_CODE = table.concat(mark.user.arr_defect_codes, ', ')
	return row
end


local function report_WeldedBond()
	local template_path = Driver:GetAppPath() .. 'Scripts/ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ РЕЛЬСОВЫХ СТЫКОВ.xlsm'
	local marks = Driver:GetMarks{GUIDS=video_joints_juids}
	marks = mark_helper.sort_mark_by_coord(marks)
	
	local dlgProgress = luaiup_helper.ProgressDlg()
	
	local out_marks = {}
	for i, mark in ipairs(marks) do
		local status = mark_helper.GetWeldedBondStatus(mark)
		if status == 1 then  -- <PARAM name='ConnectorFault' value='1' value_='0-исправен, 1-неисправен'/>
			mark.user.arr_defect_codes = {DEFECT_CODES.JOINT_WELDED_BOND_FAULT}
			table.insert(out_marks, mark)
		end
		
		if i % 10 == 0 and not dlgProgress:step(i / #marks, stuff.sprintf('Scan for fault WeldedBond %d / %d mark, found %d', i, #marks, #out_marks)) then 
			return
		end
	end
	
	if #out_marks == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end
	
	if #out_marks > 1000 then
		local msg = sprintf('Найдено %d проблемных стыков, построение отчета может занять большое время, продолжить?', #out_marks)
		local cont = iup.Alarm("Warning", msg, "Yes", "No")
		if cont == 2 then
			return
		end
	end
	
	local ext_psp = mark_helper.GetExtPassport(Passport)
	
	local excel = excel_helper(template_path, "В2 СТК", false)
	excel:ApplyPassportValues(ext_psp)
	excel:ApplyRows(out_marks, make_result_row, dlgProgress)
	excel:AppendTemplateSheet(ext_psp, out_marks, make_result_row, 3)
	excel:SaveAndShow()
end	

-- ============================================================================= 



local function AppendReports(reports)
	local sleppers_reports = 
	{
		{name = 'Ведомость отступлений в содержании рельсовых стыков|Определение наличия и состояния приварных рельсовых соединителей',    	fn = report_WeldedBond, 		guids = video_joints_juids},
	}

	for _, report in ipairs(sleppers_reports) do
		table.insert(reports, report)
	end
end


return {
	AppendReports = AppendReports,
}