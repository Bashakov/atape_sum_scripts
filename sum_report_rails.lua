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


local table_find = stuff.table_find
local sprintf = stuff.sprintf
local printf = stuff.printf
local errorf = stuff.errorf

-- ==================================================================

local guid_surface_defects = 
{
	"{4FB794A3-0CD7-4E55-B0FB-41B023AA5C6E}",	-- Поверх.(Видео)
}

local filter_juids = stuff.table_merge(guid_surface_defects)

local function get_user_filter_surface()
		local res, user_width, user_lenght, user_area = iup.GetParam("Фильтрация дефектов", nil, 
		"Ширина (мм): %s\n\z
		Высота (мм): %s\n\z
		Площадь (мм): %i\n",
		'', '', 1000)
	
	if not res then
		return
	end
	
	user_width = #user_width > 0 and tonumber(user_width)
	user_lenght = #user_lenght > 0 and tonumber(user_lenght)
	return user_area, user_width, user_lenght
end

-- ============================================================================= 


local function report_rails()
	local user_area, user_width, user_lenght = get_user_filter_surface()
	if not user_area then
		return
	end

	local marks = Driver:GetMarks{GUIDS=filter_juids}
	marks = mark_helper.sort_mark_by_coord(marks)
	
	local dlgProgress = luaiup_helper.ProgressDlg()
	
	local report_rows = {}
	for i, mark in ipairs(marks) do
		if table_find(guid_surface_defects, mark.prop.Guid) and mark.ext.RAWXMLDATA then
			local surf_prm = mark_helper.GetSurfDefectPrm(mark)
			if surf_prm then
			
				-- https://bt.abisoft.spb.ru/view.php?id=251#c592
				local mark_length = surf_prm.SurfaceWidth	
				local mark_width = surf_prm.SurfaceLength
				local mark_area = surf_prm.SurfaceArea
				
				local accept = true
				if mark_length and mark_length >= 60 then
					accept = true
				else
					accept =
						(not user_width or (mark_width and mark_width >= user_width)) and
						(not user_lenght or (mark_length and mark_length >= user_lenght)) and
						(mark_area >= user_area)
				end
				print(user_width, user_lenght, user_area, '|', mark_width, mark_length,  mark_area,  '=', accept)
				
				if accept then
					local row = mark_helper.MakeCommonMarkTemplate(mark)
					row.DEFECT_CODE = DEFECT_CODES.RAIL_SURF_DEFECT
					table.insert(report_rows, row)
				end
			end
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
	
	local template_path = Driver:GetAppPath() .. 'Scripts/ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ РЕЛЬСОВ.xlsm'
	local excel = excel_helper(template_path, "В4 РЛС", false)
	excel:ApplyPassportValues(ext_psp)
	excel:ApplyRows(report_rows, nil, dlgProgress)
	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)
	excel:SaveAndShow()
end	

-- ============================================================================= 



local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании рельсов|'
	
	local sleppers_reports = 
	{
		{name = name_pref .. 'Определение и вычисление размеров поверхностных дефектов рельсов, седловин, в том числе в местах сварки, пробуксовок (длина, ширина и площадь)',    	fn = report_rails},
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids = filter_juids
		table.insert(reports, report)
	end
end

-- тестирование
if not ATAPE then

	test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	
	report_rails()
end

return {
	AppendReports = AppendReports,
}