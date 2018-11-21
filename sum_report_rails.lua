if not ATAPE then
	require "iuplua" 
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"

local stuff = require 'stuff'
local excel_helper = require 'excel_helper'
local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local DEFECT_CODES = require 'report_defect_codes'


function printf(s,...)  print(s:format(...)) end
function sprintf(s,...) return s:format(...) end


local guid_surface_defects = 
{
	"{4FB794A3-0CD7-4E55-B0FB-41B023AA5C6E}",	-- Поверх.(Видео)
}

local filter_juids = stuff.table_merge(guid_surface_defects)


-- ============================================================================= 

local function mark_is_surface_defect(mark)
	local mg = mark.prop.Guid
	for i, g in ipairs(guid_surface_defects) do
		if mg == g then
			return true
		end
	end
	return false
end


local function report_rails()
	local template_path = Driver:GetAppPath() .. 'Scripts/ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ РЕЛЬСОВ.xlsm'
	local marks = Driver:GetMarks{GUIDS=filter_juids}
	marks = mark_helper.sort_mark_by_coord(marks)
	
	local dlgProgress = luaiup_helper.ProgressDlg()
	
	local report_rows = {}
	for i, mark in ipairs(marks) do
		if mark_is_surface_defect(mark) then
--			local prm = mark_helper.GetSurfDefectPrm(mark)
--			if prm and prm['SurfaceFault'] == 0 then  -- <PARAM name="SurfaceFault" value="0" value_="0-черный пов.дефект; 1-"/>
			
			local row = mark_helper.MakeCommonMarkTemplate(mark)
			row.DEFECT_CODE = DEFECT_CODES.RAIL_SURF_DEFECT
	
			table.insert(report_rows, row)
		end
	
		if i % 10 == 0 and not dlgProgress:step(i / #marks, stuff.sprintf('Scan %d / %d mark, found %d', i, #marks, #report_rows)) then 
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
	
	local excel = excel_helper(template_path, "В4 РЛС", false)
	excel:ApplyPassportValues(ext_psp)
	excel:ApplyRows(report_rows, nil, dlgProgress)
	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)
	excel:SaveAndShow()
end	

-- ============================================================================= 



local function AppendReports(reports)
	local sleppers_reports = 
	{
		{name = 'Ведомость отступлений в содержании рельсов|Определение и вычисление размеров поверхностных дефектов рельсов, седловин, в том числе в местах сварки, пробуксовок (длина, ширина и площадь)',    	fn = report_rails, 		guids = filter_juids},
	}

	for _, report in ipairs(sleppers_reports) do
		table.insert(reports, report)
	end
end


return {
	AppendReports = AppendReports,
}