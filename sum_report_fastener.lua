if not ATAPE then
	require "iuplua"
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"


local mark_helper = require 'sum_mark_helper'
local DEFECT_CODES = require 'report_defect_codes'
local EKASUI_REPORT = require 'sum_report_ekasui'
local AVIS_REPORT = require 'sum_report_avis'
local sumPOV = require "sumPOV"

local printf = mark_helper.printf
local sprintf = mark_helper.sprintf

-- =========================================================================

local guids_fasteners = 
{
	"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}",	-- Скрепление
	"{3601038C-A561-46BB-8B0F-F896C2130001}",	-- Скрепления(Пользователь)
}

local function GetMarks(ekasui, pov_filter)
	if not pov_filter then
		pov_filter = sumPOV.MakeReportFilter(ekasui)
	end
	if not pov_filter then return {} end
	local marks = Driver:GetMarks{GUIDS=guids_fasteners}
	marks = pov_filter(marks)
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end

local function MakeFastenerMarkRow(mark)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
	row.FASTENER_TYPE = ''
	return row
end

local function get_user_options(mark)
	local text = mark.ext.DEFECT_OPTIONS
	local res = {}
	string.gsub(text or '', '([^\n]+)', function(s)
			local n, v = string.match(s, '([^:]+):(.*)')
			-- print(s, n, v)
			if n then res[n] = v end
		end)
	return res
end

-- =========================================================================

local function generate_rows_fastener(marks, dlgProgress)

	local fastener_type_names = {
		[0] = 'КБ-65',
		[1] = 'Аpc',
		[2] = 'ДО', -- скрепление на деревянной шпале на костылях
		[3] = 'КД', -- скрепление на деревянной шпале как КБ-65 но на двух шурупах
	}


	--local fastener_fault_names = {
	--	[0] = 'норм.',
	--	[1] = 'От.ЗБ',  -- отсутствие закладного болта kb65
	--	[2] = 'От.Кл',	-- отсутствие клеммы apc
	--}

	local report_rows = {}

	for i, mark in ipairs(marks) do
		if mark.prop.Guid == "{3601038C-A561-46BB-8B0F-F896C2130001}" and
		 (mark.ext.CODE_EKASUI == DEFECT_CODES.FASTENER_MISSING_CLAMP_BOLT[1] or
		  mark.ext.CODE_EKASUI == DEFECT_CODES.FASTENER_MISSING_CLAMP[1] or
		  mark.ext.CODE_EKASUI == DEFECT_CODES.FASTENER_MISSING_BOLT[1]) then
			local row = MakeFastenerMarkRow(mark)
			row.DEFECT_CODE = mark.ext.CODE_EKASUI
			row.DEFECT_DESC = DEFECT_CODES.code2desc(mark.ext.CODE_EKASUI) or string.match(mark.prop.Description, '([^\n]+)\n')
			row.FASTENER_TYPE = get_user_options(mark).connector_type or ''
			table.insert(report_rows, row)
		else
			local prm = mark_helper.GetFastenetParams(mark)
			local FastenerType = prm and prm.FastenerType or -1
			local FastenerFault = prm and prm.FastenerFault

			if FastenerFault and FastenerFault > 0 then
				local row = MakeFastenerMarkRow(mark)

				row.FASTENER_TYPE = fastener_type_names[FastenerType] or ''
				if prm.FastenerFault == 1 then -- отсутствие клеммного болта kb65
					row.DEFECT_CODE = DEFECT_CODES.FASTENER_MISSING_CLAMP_BOLT[1]
					row.DEFECT_DESC = DEFECT_CODES.FASTENER_MISSING_CLAMP_BOLT[2]
				elseif prm.FastenerFault == 2 then -- отсутствие клеммы apc
					row.DEFECT_CODE = DEFECT_CODES.FASTENER_MISSING_CLAMP[1]
					row.DEFECT_DESC = DEFECT_CODES.FASTENER_MISSING_CLAMP[2]
				elseif prm.FastenerFault == 10 then -- отсутствие закладного болта kb65
					row.DEFECT_CODE = DEFECT_CODES.FASTENER_MISSING_BOLT[1]
					row.DEFECT_DESC = DEFECT_CODES.FASTENER_MISSING_BOLT[2]
				elseif prm.FastenerFault == 11 then -- отсутствие клеммного и закладного болта kb65 - имитируем закладной
					row.DEFECT_CODE = DEFECT_CODES.FASTENER_MISSING_BOLT[1]
					row.DEFECT_DESC = DEFECT_CODES.FASTENER_MISSING_BOLT[2]
				end

				table.insert(report_rows, row)
			end
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local function generate_rows_fastener_user(marks, dlgProgress)
	if #marks == 0 then return end

	local report_rows = {}
	for i, mark in ipairs(marks) do
		if mark.prop.Guid == "{3601038C-A561-46BB-8B0F-F896C2130001}" and mark.ext.CODE_EKASUI then
			local row = MakeFastenerMarkRow(mark)
			row.DEFECT_CODE = mark.ext.CODE_EKASUI
			row.DEFECT_DESC = DEFECT_CODES.code2desc(mark.ext.CODE_EKASUI) or string.match(mark.prop.Description, '([^\n]+)\n')
			row.FASTENER_TYPE = get_user_options(mark).connector_type or ''
			table.insert(report_rows, row)
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local function report_not_implement()
	iup.Message('Error', "Отчет не реализован")
end

-- =============================================================================

local function make_report_generator(...)

	local report_template_name = 'ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ СКРЕПЛЕНИЙ.xlsm'
	local sheet_name = 'В1 СКР'

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
		if mark and mark_helper.table_find(guids_fasteners, mark.prop.Guid) then
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

-- =========================================================================

local report_fastener = make_report_generator(generate_rows_fastener)
local ekasui_fastener = make_report_ekasui(generate_rows_fastener)
local videogram = make_report_videogram(generate_rows_fastener)

local report_fastener_all = make_report_generator(generate_rows_fastener_user, generate_rows_fastener)
local ekasui_fastener_all = make_report_ekasui(generate_rows_fastener_user, generate_rows_fastener)

-- =========================================================================

local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании скреплений|'
	local name_fastener = '\
Определение параметров и состояния рельсовых скреплений \
(наличие визуально фиксируемых ослабленных скреплений, сломанных подкладок, \
отсутствие болтов, негодные прокладки, закладные и клеммные болты, шурупы, клеммы, анкеры)'

	local sleppers_reports =
	{
		{name = name_pref..'Все',    						fn=report_fastener_all, },
		{name = name_pref..'ЕКАСУИ Все',    				fn=ekasui_fastener_all, },
		{name = name_pref.. name_fastener,    				fn=report_fastener, },
		{name = name_pref..'ЕКАСУИ ' .. name_fastener,    	fn=ekasui_fastener, },
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids=guids_fasteners
		table.insert(reports, report)
	end
end

-- тестирование
if not ATAPE then
	local test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')

	report_fastener()
	-- ekasui_fastener()
	-- report_fastener_user()
end

return {
	AppendReports = AppendReports,
	videogram = videogram,
	all_generators = {generate_rows_fastener_user, generate_rows_fastener},
	get_marks = function (pov_filter)
		return GetMarks(false, pov_filter)
	end,
}
