require "luacom"

if not ATAPE then
	require "iuplua" 
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'
local mark_helper = require 'sum_mark_helper'

-- ============================================================

local function SaveAndShow(report_rows, dlgProgress, report_template_name, sheet_name)
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
	
	local template_path = Driver:GetAppPath() .. 'Scripts/'  .. report_template_name
	local ext_psp = mark_helper.GetExtPassport(Passport)
	local excel = excel_helper(template_path, sheet_name, false)
	
	excel:ApplyPassportValues(ext_psp)
	excel:ApplyRows(report_rows, nil, dlgProgress)
	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)
	excel:SaveAndShow()
end


local function make_report_generator(getMarks, report_template_name, sheet_name, ...)
	local row_generators = {...}
		
	function gen()
		local dlgProgress = luaiup_helper.ProgressDlg()
		local marks = getMarks()
		
		local report_rows = {}
		for _, fn_gen in ipairs(row_generators) do
			local cur_rows = fn_gen(marks, dlgProgress)
			for _, row in ipairs(cur_rows) do
				table.insert(report_rows, row)
			end
		end
		
		report_rows = mark_helper.sort_stable(report_rows, function(row)
			local c = row.SYS
			return c
		end)
	
		SaveAndShow(report_rows, dlgProgress, report_template_name, sheet_name)
	end
	
	return gen
end	

local function IsAvailable()
	return EKASUI
end

-- ===========================================================

return {
	make_report_generator = make_report_generator,
	IsAvailable = IsAvailable,
}
