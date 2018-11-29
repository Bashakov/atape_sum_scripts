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



-- ========================================================================= 

local guids_fasteners = {
	"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}",
}

local function GetMarks()
	local marks = Driver:GetMarks{GUIDS=guids_fasteners}
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
	
	local template_path = Driver:GetAppPath() .. 'Scripts/ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ СКРЕПЛЕНИЙ.xlsm' 
	local ext_psp = mark_helper.GetExtPassport(Passport)
	local excel = excel_helper(template_path, "В1 СКР", false)
	excel:ApplyPassportValues(ext_psp)
	excel:ApplyRows(report_rows, nil, dlgProgress)
	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)
	excel:SaveAndShow()
end

local function MakeFastenerMarkRow(mark)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
	return row
end

-- ========================================================================= 

local function generate_rows_fastener(marks, dlgProgress)
	
local fastener_type_names = {
	[0] = 'КБ-65',
	[1] = 'Аpc',
	[2] = 'КД',
}
	
--local fastener_fault_names = {
--	[0] = 'норм.',
--	[1] = 'От.ЗБ',  -- отсутствие закладного болта kb65
--	[2] = 'От.Кл',	-- отсуствие клеммы apc
--}
	
	local report_rows = {}
	
	for i, mark in ipairs(marks) do
		local prm = mark_helper.GetFastenetParams(mark)
		local FastenerType = prm and prm.FastenerType or -1
		local FastenerFault = prm and prm.FastenerFault 
		
		if FastenerFault and FastenerFault > 0 then
			local row = MakeFastenerMarkRow(mark)
			
			row.FASTENER_TYPE = fastener_type_names[FastenerType] or ''
			if prm.FastenerFault == 1 then -- отсутствие закладного болта kb65
				row.DEFECT_CODE = DEFECT_CODES.FASTENER_MISSING_BOLT[1]
				row.DEFECT_DESC = DEFECT_CODES.FASTENER_MISSING_BOLT[2]
			elseif prm.FastenerFault == 2 then -- отсуствие клеммы apc
				row.DEFECT_CODE = DEFECT_CODES.FASTENER_MISSING_CLAMP_BOLT[1]
				row.DEFECT_DESC = DEFECT_CODES.FASTENER_MISSING_CLAMP_BOLT[2]
			end
			
			table.insert(report_rows, row)
		end
		
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then 
			return
		end
	end
	
	return report_rows
end


-- ============================================================================= 

local function make_report_generator(...)
	local row_generators = {...}
	
	function gen()
		local dlgProgress = luaiup_helper.ProgressDlg()
		local marks = GetMarks()
		
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
		SaveAndShow(report_rows, dlgProgress)
	end
	
	return gen
end	

local report_fastener = make_report_generator(generate_rows_fastener)

local report_not_implement = function()	iup.Message('Error', "Отчет не реализован") end

-- ========================================================================= 

local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании скреплений|'
	
	local sleppers_reports = 
	{
		{name = name_pref..'Определение параметров и состояния рельсовых скреплений (наличие визуально фиксируемых ослабленных скреплений, сломанных подкладок, отсутствие болтов, негодные прокладки, закладные и клеммные болты, шурупы, клеммы, анкеры)',    					fn=report_fastener, 			},
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids=guids_fasteners
		table.insert(reports, report)
	end
end

-- тестирование
if not ATAPE then
	test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	
	report_fastener()
end

return {
	AppendReports = AppendReports,
}