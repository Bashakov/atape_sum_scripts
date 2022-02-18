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
local functional = require "functional"
local remove_grouped_marks = require "sum_report_group_scanner"
local ErrorUserAborted = require "UserAborted"

local printf = mark_helper.printf
local sprintf = mark_helper.sprintf

-- =========================================================================

local guids_fasteners =
{
	"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}",	-- Скрепление
	"{3601038C-A561-46BB-8B0F-F896C2130001}",	-- Скрепления(Пользователь)
}

local guids_fasteners_groups =
{
	"{B6BAB49E-4CEC-4401-A106-355BFB2E0021}",   -- GROUP_FSTR_AUTO
	"{B6BAB49E-4CEC-4401-A106-355BFB2E0022}", 	-- GROUP_FSTR_USER
}

local function GetMarks(ekasui, pov_filter)
	if not pov_filter then
		pov_filter = sumPOV.MakeReportFilter(ekasui)
	end
	if not pov_filter then return {} end
	local gg = mark_helper.table_merge(guids_fasteners, guids_fasteners_groups)
	local marks = Driver:GetMarks{GUIDS=gg}
	marks = pov_filter(marks)
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end

local function MakeFastenerMarkRow(mark, defect_code)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
	row.FASTENER_TYPE = ''

	row.DEFECT_CODE = defect_code or ''
	row.DEFECT_DESC = DEFECT_CODES.code2desc(defect_code) or string.match(mark.prop.Description, '([^\n]+)\n') or ''

	return row
end

local function get_user_options(mark)
	local text = mark.ext.DEFECT_OPTIONS
	local res = {}
	local _ = string.gsub(text or '', '([^\n]+)',
		function(s)
			local n, v = string.match(s, '([^:]+):(.*)')
			-- print(s, n, v)
			if n then res[n] = v end
		end)
	return res
end

-- =========================================================================


local function igenerate_rows_fastener(marks, dlgProgress)
	return coroutine.wrap(function ()
	local fastener_type_names = {
		[0] = 'КБ-65',
		[1] = 'Аpc',
		[2] = 'ДО', -- скрепление на деревянной шпале на костылях
		[3] = 'КД', -- скрепление на деревянной шпале как КБ-65 но на двух шурупах
	}

	local defect_codes =
	{
		DEFECT_CODES.FASTENER_MISSING_CLAMP_BOLT[1],
		DEFECT_CODES.FASTENER_MISSING_CLAMP[1],
		DEFECT_CODES.FASTENER_MISSING_BOLT[1],
	}

	local accepted = 0
	for i, mark in ipairs(marks) do
		if ("{3601038C-A561-46BB-8B0F-F896C2130001}" == mark.prop.Guid and
		    mark_helper.table_find(defect_codes, mark.ext.CODE_EKASUI)) or
			mark_helper.table_find(guids_fasteners_groups, mark.prop.Guid)
		then
			local row = MakeFastenerMarkRow(mark, mark.ext.CODE_EKASUI)
			row.FASTENER_TYPE = get_user_options(mark).connector_type or ''

			coroutine.yield(row)
			accepted = accepted + 1
		else
			local prm = mark_helper.GetFastenetParams(mark)
			local FastenerType = prm and prm.FastenerType or -1
			local FastenerFault = prm and prm.FastenerFault

			if FastenerFault and FastenerFault > 0 then
				local defect_code

				if prm.FastenerFault == 1 then -- отсутствие клеммного болта kb65
					defect_code = DEFECT_CODES.FASTENER_MISSING_CLAMP_BOLT[1]
				elseif prm.FastenerFault == 2 then -- отсутствие клеммы apc
					defect_code = DEFECT_CODES.FASTENER_MISSING_CLAMP[1]
				elseif prm.FastenerFault == 10 then -- отсутствие закладного болта kb65
					defect_code = DEFECT_CODES.FASTENER_MISSING_BOLT[1]
				elseif prm.FastenerFault == 11 then -- отсутствие клеммного и закладного болта kb65 - имитируем закладной
					defect_code = DEFECT_CODES.FASTENER_MISSING_BOLT[1]
				end

				local row = MakeFastenerMarkRow(mark, defect_code)
				row.FASTENER_TYPE = fastener_type_names[FastenerType] or ''

				coroutine.yield(row)
				accepted = accepted + 1
			end
		end

		if i % 300 == 0 then collectgarbage("collect") end
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d СКРЕПЛЕНИЙ, найдено %d', i, #marks, accepted)) then
			ErrorUserAborted()
		end
	end
	end)
end


local function igenerate_rows_fastener_user(marks, dlgProgress)
	return coroutine.wrap(function ()

	--local report_rows = {}
	local accepted = 0
	for i, mark in ipairs(marks) do
		if mark.prop.Guid == "{3601038C-A561-46BB-8B0F-F896C2130001}" and mark.ext.CODE_EKASUI then
			local row = MakeFastenerMarkRow(mark, mark.ext.CODE_EKASUI)
			row.FASTENER_TYPE = get_user_options(mark).connector_type or ''

			coroutine.yield(row)
			accepted = accepted + 1
		end

		if i % 300 == 0 then collectgarbage("collect") end
		if i % 10 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, accepted)) then
			ErrorUserAborted()
		end
	end
	end)
end

local function igen_adapter(fn)
	return function (...)
		local args = {...}
		return ErrorUserAborted.skip(function ()
			local g = fn(table.unpack(args))
			local rows = functional.list(g)
			rows = remove_grouped_marks(rows, guids_fasteners_groups, false)
			return rows
		end)
	end
end

local generate_rows_fastener = igen_adapter(igenerate_rows_fastener)
local generate_rows_fastener_user = igen_adapter(igenerate_rows_fastener_user)

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
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml', nil, {0, 1000000})

	--report_fastener()
	ekasui_fastener()
	-- report_fastener_user()
end

return {
	AppendReports = AppendReports,
	videogram = videogram,
	all_generators = {
		{generate_rows_fastener_user, 	"Установленые пользователем"},
		{generate_rows_fastener, 		"Состояние рельсовых скреплений"},
	},
	get_marks = function (pov_filter)
		return GetMarks(false, pov_filter)
	end,
}
